//
//  BattleSession.swift
//  Fantasy Fitness
//
//  State for one dungeon fight. Wraps the `BattleState` engine (Services/BattleRules.swift)
//  and adds what the screen needs: which step of the turn it's on, the log line, and the
//  last hit on each side for animations. The view reports the outcome to the server;
//  this never talks to Supabase.
//

import Foundation
import Observation

@Observable
final class BattleSession {
    enum Phase: Equatable {
        /// Pick an action; the boss's next move is showing.
        case choosing
        /// The timing meter is running for this action.
        case aiming(PlayerAction, MeterZones, startedAt: Date)
        /// Your hit landed; the boss moves next.
        case bossTurn
        case won
        case lost
    }

    /// One hit for the floating number and shake. `id` changes on every hit.
    struct Hit: Equatable {
        enum Kind { case damage, critical, glancing, miss, heal, dodge, blocked }

        let id: Int
        let kind: Kind
        let text: String
    }

    private(set) var state: BattleState
    private(set) var phase: Phase = .choosing
    private(set) var log: String
    private(set) var hitOnBoss: Hit?
    private(set) var hitOnPlayer: Hit?
    /// Count up only on hits that land, so a card shakes for damage but not for a heal or dodge.
    private(set) var bossShakes = 0
    private(set) var playerShakes = 0
    private var hitCount = 0

    init(player: Fighter, boss: Boss, seed: UInt64) {
        state = BattleState(player: player, boss: boss, seed: seed)
        log = "\(boss.name) stirs. Watch its next move."
    }

    /// Stats and gear are read once, at the start: the store reloads mid-fight.
    convenience init(profile: PlayerProfile, dungeon: Dungeon, runID: UUID) {
        self.init(player: Fighter(profile: profile), boss: Boss(dungeon: dungeon),
                  seed: BattleRandom.seed(for: runID))
    }

    var player: Fighter { state.player }
    var boss: Boss { state.boss }
    var isOver: Bool { phase == .won || phase == .lost }

    /// The boss's next move, e.g. "Heavy swing · 24 damage".
    var intentText: String {
        switch state.intent {
        case .swipe: "Swipe · \(state.incomingDamage(for: .swipe)) damage"
        case .heavySwing: "Heavy swing · \(state.incomingDamage(for: .heavySwing)) damage"
        case .brace: "Bracing · halves your hit"
        }
    }

    var skillStatus: String {
        state.isSkillReady ? "Ready" : "\(state.skillCooldown) turn\(state.skillCooldown == 1 ? "" : "s")"
    }

    // MARK: - Turn

    /// Starts an action. With `usingMeter` false (VoiceOver), it lands as a normal hit.
    func choose(_ action: PlayerAction, usingMeter: Bool = true) {
        guard phase == .choosing else { return }
        if action == .skill && !state.isSkillReady { return }
        if action.usesMeter && usingMeter {
            phase = .aiming(action, state.rollZones(for: action), startedAt: .now)
        } else {
            resolve(action, meter: .solid)
        }
    }

    /// Stops the meter where the marker is at `date`.
    func stopMeter(at date: Date) {
        guard case .aiming(let action, let zones, let startedAt) = phase else { return }
        let position = MeterZones.markerPosition(after: date.timeIntervalSince(startedAt),
                                                 sweep: player.sweepDuration)
        resolve(action, meter: zones.classify(position))
    }

    /// The boss carries out its move. The view calls this after a short pause.
    func finishBossTurn() {
        guard phase == .bossTurn else { return }
        let events = state.bossActs()
        apply(events)
        phase = state.outcome == .lost ? .lost : .choosing
    }

    private func resolve(_ action: PlayerAction, meter: MeterResult) {
        let events = state.playerActs(action, meter: meter)
        apply(events)
        phase = state.outcome == .won ? .won : .bossTurn
    }

    // MARK: - Log and hits

    private func apply(_ events: [BattleEvent]) {
        var lines: [String] = []
        for event in events {
            switch event {
            case .playerHit(let action, let result, let damage, let wasBraced):
                lines.append(hitLine(action: action, result: result, damage: damage, wasBraced: wasBraced))
                hitOnBoss = hit(damage == 0 ? .miss : result == .critical ? .critical
                                    : result == .glancing ? .glancing : .damage,
                                damage == 0 ? "Miss" : "−\(damage)")
                if damage > 0 { bossShakes += 1 }
            case .guarded:
                lines.append("You raise your guard.")
            case .healed(let amount):
                lines.append("You heal \(amount).")
                hitOnPlayer = hit(.heal, "+\(amount)")
            case .bossEnraged:
                lines.append("\(boss.name) is enraged!")
            case .bossHit(let move, let damage, let guarded):
                let attack = move == .heavySwing ? "heavy swing" : "swipe"
                if !guarded {
                    lines.append("\(boss.name)'s \(attack) hits for \(damage).")
                } else if damage == 0 {
                    lines.append("Your guard holds. The \(attack) does no damage.")
                } else {
                    lines.append("Your guard holds. The \(attack) only hits for \(damage).")
                }
                hitOnPlayer = hit(guarded ? .blocked : .damage, damage == 0 ? "Blocked" : "−\(damage)")
                if damage > 0 { playerShakes += 1 }
            case .dodged(let move):
                lines.append("You dodge the \(move == .heavySwing ? "heavy swing" : "swipe")!")
                hitOnPlayer = hit(.dodge, "Dodged")
            case .bossBraced:
                lines.append("\(boss.name) holds its guard.")
            case .won:
                lines.append("\(boss.name) falls!")
            case .lost:
                lines.append("You fall back to rest. No stats lost, so train up and try again.")
            }
        }
        if !lines.isEmpty { log = lines.joined(separator: " ") }
    }

    private func hitLine(action: PlayerAction, result: MeterResult, damage: Int, wasBraced: Bool) -> String {
        let name = switch action {
        case .strike: "Strike"
        case .heavyBlow: "Heavy Blow"
        case .skill: player.skill.name
        case .defend: "Guard"
        }
        if damage == 0 { return "Your \(name) whiffs!" }
        let quality = switch result {
        case .critical: "Critical! "
        case .glancing: "Glancing. "
        case .solid: ""
        }
        let braced = wasBraced ? " It braced and took half." : ""
        return "\(quality)\(name) hits for \(damage).\(braced)"
    }

    private func hit(_ kind: Hit.Kind, _ text: String) -> Hit {
        hitCount += 1
        return Hit(id: hitCount, kind: kind, text: text)
    }
}

// MARK: - Previews

extension BattleSession {
    /// The demo player against the Mossy Crypt, `turns` turns in (Strike every turn).
    static func preview(turns: Int = 0, seed: UInt64 = 7) -> BattleSession {
        let session = BattleSession(player: Fighter(profile: .sample), boss: Boss(dungeon: Dungeon.sampleMap[1]),
                                    seed: seed)
        for _ in 0..<turns where !session.isOver {
            session.choose(.strike, usingMeter: false)
            session.finishBossTurn()
        }
        return session
    }
}

// MARK: - From the app's models

extension Fighter {
    /// Real stats plus equipped gear's bonuses.
    init(profile: PlayerProfile) {
        self.init(name: profile.displayName, skill: profile.guildClass.skill,
                  strength: profile.stats[.strength] ?? 0,
                  endurance: profile.stats[.endurance] ?? 0,
                  speed: profile.stats[.speed] ?? 0,
                  agility: profile.stats[.agility] ?? 0,
                  vitality: profile.stats[.vitality] ?? 0,
                  gearAttack: profile.equipped.reduce(0) { $0 + $1.attackBonus },
                  gearDefense: profile.equipped.reduce(0) { $0 + $1.defenseBonus })
    }
}

extension Boss {
    init(dungeon: Dungeon) {
        self.init(name: dungeon.boss, health: dungeon.bossHealth)
    }
}

extension GuildClass {
    var skill: ClassSkill {
        switch self {
        case .warrior: .cleave
        case .ranger: .volley
        case .monk: .flurry
        case .paladin: .smite
        }
    }
}
