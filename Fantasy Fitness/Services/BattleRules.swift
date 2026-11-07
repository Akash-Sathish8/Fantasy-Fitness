//
//  BattleRules.swift
//  Fantasy Fitness
//
//  The dungeon fight engine: combat numbers, boss moves and one turn at a time. Plain
//  Foundation with no app types, so it can be simulated or tested on its own and later
//  run on the server. Real stats and gear set the numbers; the timing meter only scales a
//  hit up or down a little, so training stays the main source of power.
//
//  The server still trusts the phone's result (see CLAUDE.md, "Known gap"). Every fight's
//  randomness comes from a seed, so a fight can be replayed from the run id and the inputs.
//

import Foundation

// MARK: - Tuning

/// Every number the fight uses. Balance was checked by simulating thousands of fights per
/// dungeon for a new player, a mid-level player and a strong lifter; retune here.
nonisolated enum BattleRules {
    // Your side. Stats come from real training: Strength is best 1RM / bodyweight × 40,
    // Vitality 5 per good night (max 70), Endurance cardio minutes / 10, Speed pace in km/h.
    static let baseHealth = 100
    static let baseAttack = 10
    /// Attack rises 1 for every this much Strength.
    static let strengthPerAttack = 4
    /// Health rises 1 for every this much Endurance.
    static let endurancePerHealth = 2

    // Timing meter: nudges damage, never replaces training.
    static let hitZoneWidth = 0.5
    static let baseGoldZone = 0.12
    static let goldZonePerAgility = 0.0025
    static let maxGoldZone = 0.3
    /// Seconds for the marker to cross the meter once.
    static let baseSweep = 1.4
    static let sweepPerSpeed = 0.02
    static let maxSweep = 2.0
    static let glancingMultiplier = 0.5
    static let criticalMultiplier = 1.3

    // The boss.
    static let bossBaseHit = 5
    /// Boss hits rise 1 for every this much boss health.
    static let bossHealthPerHit = 8
    static let heavySwingMultiplier = 2.0
    static let enrageBelow = 0.3
    static let enrageMultiplier = 1.25
    static let braceMultiplier = 0.5
    static let guardMultiplier = 0.25
    static let swipeWeight = 50
    static let heavySwingWeight = 30
    static let braceWeight = 20

    // Your actions.
    static let heavyBlowPower = 1.5
    /// Turns between skill uses.
    static let skillCooldown = 3
    /// Turns before the first use, so the skill is ready on turn 3.
    static let skillFirstCooldown = 2
    static let smiteHealShare = 0.15
}

// MARK: - Fighters

/// Each class's special move.
nonisolated enum ClassSkill: String, CaseIterable, Sendable {
    case cleave, volley, flurry, smite

    var name: String { rawValue.capitalized }

    var power: Double {
        switch self {
        case .cleave: 2.0
        case .volley: 1.8
        case .flurry: 1.0
        case .smite: 1.2
        }
    }

    /// What it does besides damage.
    var summary: String {
        switch self {
        case .cleave: "A huge two-handed blow"
        case .volley: "Pierces the boss's guard"
        case .flurry: "Dodges the boss's next attack"
        case .smite: "Heals \(Int((BattleRules.smiteHealShare * 100).rounded()))% of your health"
        }
    }
}

/// The player in a fight, built from real stats and equipped gear.
nonisolated struct Fighter: Sendable {
    let name: String
    let skill: ClassSkill
    let maxHealth: Int
    let attack: Int
    let defense: Int
    /// Share of the meter that lands a critical hit.
    let goldZone: Double
    /// Seconds for the marker to cross the meter once. Higher Speed gives more time.
    let sweepDuration: Double

    // Where the numbers come from, for the loadout.
    let healthFromVitality: Int
    let healthFromEndurance: Int
    let attackFromStrength: Int
    let attackFromGear: Int

    init(name: String, skill: ClassSkill, strength: Int, endurance: Int, speed: Int, agility: Int,
         vitality: Int, gearAttack: Int, gearDefense: Int) {
        self.name = name
        self.skill = skill
        healthFromVitality = max(vitality, 0)
        healthFromEndurance = max(endurance, 0) / BattleRules.endurancePerHealth
        attackFromStrength = max(strength, 0) / BattleRules.strengthPerAttack
        attackFromGear = max(gearAttack, 0)
        maxHealth = BattleRules.baseHealth + healthFromVitality + healthFromEndurance
        attack = BattleRules.baseAttack + attackFromStrength + attackFromGear
        defense = max(gearDefense, 0)
        goldZone = min(BattleRules.baseGoldZone + Double(max(agility, 0)) * BattleRules.goldZonePerAgility,
                       BattleRules.maxGoldZone)
        sweepDuration = min(BattleRules.baseSweep + Double(max(speed, 0)) * BattleRules.sweepPerSpeed,
                            BattleRules.maxSweep)
    }
}

nonisolated struct Boss: Sendable {
    let name: String
    let maxHealth: Int
    let baseHit: Int

    init(name: String, health: Int) {
        self.name = name
        maxHealth = max(health, 1)
        baseHit = BattleRules.bossBaseHit + maxHealth / BattleRules.bossHealthPerHit
    }
}

/// What the boss will do after your action. Shown before you choose.
nonisolated enum BossMove: Sendable {
    case swipe, heavySwing, brace
}

nonisolated enum PlayerAction: Hashable, Sendable {
    /// Shown as "Guard".
    case strike, heavyBlow, defend, skill

    var usesMeter: Bool { self != .defend }
}

// MARK: - Timing meter

nonisolated enum MeterResult: Sendable {
    /// Outside the hit zone. A Heavy Blow whiffs.
    case glancing
    case solid
    /// Inside the gold zone.
    case critical

    var multiplier: Double {
        switch self {
        case .glancing: BattleRules.glancingMultiplier
        case .solid: 1
        case .critical: BattleRules.criticalMultiplier
        }
    }
}

/// Where the hit and gold zones sit on one swing, as shares of the meter (0…1).
nonisolated struct MeterZones: Equatable, Sendable {
    let hitStart: Double
    let hitWidth: Double
    let goldStart: Double
    let goldWidth: Double

    func classify(_ position: Double) -> MeterResult {
        if position >= goldStart && position <= goldStart + goldWidth { return .critical }
        if position >= hitStart && position <= hitStart + hitWidth { return .solid }
        return .glancing
    }

    /// Where the marker is (0…1) after `elapsed` seconds: it starts at the left and sweeps
    /// back and forth, taking `sweep` seconds per crossing. Drawing and scoring both use this.
    static func markerPosition(after elapsed: TimeInterval, sweep: TimeInterval) -> Double {
        guard sweep > 0 else { return 0 }
        let crossings = max(elapsed, 0) / sweep
        let leg = crossings.truncatingRemainder(dividingBy: 2)
        return leg <= 1 ? leg : 2 - leg
    }
}

// MARK: - The fight

nonisolated enum BattleEvent: Equatable, Sendable {
    /// Your attack. Damage 0 is a whiffed Heavy Blow.
    case playerHit(action: PlayerAction, result: MeterResult, damage: Int, wasBraced: Bool)
    case guarded
    case healed(Int)
    case bossEnraged
    case bossHit(move: BossMove, damage: Int, guarded: Bool)
    case dodged(BossMove)
    case bossBraced
    case won
    case lost
}

/// One fight, a turn at a time: you act, then the boss carries out the move it showed and
/// picks its next one. Value type, so a fight can be copied, simulated or replayed.
nonisolated struct BattleState: Sendable {
    nonisolated enum Outcome: Sendable { case won, lost }

    let player: Fighter
    let boss: Boss
    private(set) var playerHealth: Int
    private(set) var bossHealth: Int
    /// The move the boss will make this turn, after your action.
    private(set) var intent: BossMove = .swipe
    private(set) var isEnraged = false
    /// Turns until the class skill is ready; 0 means ready.
    private(set) var skillCooldown = BattleRules.skillFirstCooldown
    private(set) var turn = 1
    private(set) var outcome: Outcome?

    private var guarding = false
    private var dodging = false
    private var lastMove: BossMove?
    private var rng: BattleRandom

    init(player: Fighter, boss: Boss, seed: UInt64) {
        self.player = player
        self.boss = boss
        playerHealth = player.maxHealth
        bossHealth = boss.maxHealth
        rng = BattleRandom(seed: seed)
        intent = nextMove()
    }

    var isSkillReady: Bool { skillCooldown == 0 }

    /// Places the hit and gold zones for one swing. Heavy Blow gets half the gold zone.
    mutating func rollZones(for action: PlayerAction) -> MeterZones {
        let hitWidth = BattleRules.hitZoneWidth
        let goldWidth = action == .heavyBlow ? player.goldZone / 2 : player.goldZone
        let hitStart = Double.random(in: 0.05...(0.95 - hitWidth), using: &rng)
        let goldStart = Double.random(in: hitStart...(hitStart + hitWidth - goldWidth), using: &rng)
        return MeterZones(hitStart: hitStart, hitWidth: hitWidth, goldStart: goldStart, goldWidth: goldWidth)
    }

    /// Your half of the turn. `meter` is ignored for Guard.
    mutating func playerActs(_ action: PlayerAction, meter: MeterResult = .solid) -> [BattleEvent] {
        guard outcome == nil else { return [] }
        if action == .skill && !isSkillReady { return [] }

        if action == .defend {
            // The cooldown ticks once per turn, in bossActs, whatever you chose.
            guarding = true
            return [.guarded]
        }

        var events: [BattleEvent] = []
        let power: Double = switch action {
        case .heavyBlow: BattleRules.heavyBlowPower
        case .skill: player.skill.power
        default: 1
        }
        let braced = intent == .brace && !(action == .skill && player.skill == .volley)
        var damage = 0
        if !(action == .heavyBlow && meter == .glancing) {
            var raw = Double(player.attack) * power * meter.multiplier
            if braced { raw *= BattleRules.braceMultiplier }
            damage = max(Int(raw.rounded()), 1)
        }
        bossHealth = max(bossHealth - damage, 0)
        events.append(.playerHit(action: action, result: meter, damage: damage, wasBraced: braced))

        if action == .skill {
            skillCooldown = BattleRules.skillCooldown
            switch player.skill {
            case .flurry:
                dodging = true
            case .smite:
                let heal = min(Int((Double(player.maxHealth) * BattleRules.smiteHealShare).rounded()),
                               player.maxHealth - playerHealth)
                if heal > 0 {
                    playerHealth += heal
                    events.append(.healed(heal))
                }
            case .cleave, .volley:
                break
            }
        }

        if bossHealth == 0 {
            outcome = .won
            events.append(.won)
        } else if !isEnraged && Double(bossHealth) < Double(boss.maxHealth) * BattleRules.enrageBelow {
            isEnraged = true
            events.append(.bossEnraged)
        }
        return events
    }

    /// The boss's half: it carries out the move it showed, then picks the next one.
    mutating func bossActs() -> [BattleEvent] {
        guard outcome == nil else { return [] }
        var events: [BattleEvent] = []
        switch intent {
        case .brace:
            events.append(.bossBraced)
        case .swipe, .heavySwing:
            if dodging {
                events.append(.dodged(intent))
            } else {
                let damage = incomingDamage(for: intent, guarding: guarding)
                playerHealth = max(playerHealth - damage, 0)
                events.append(.bossHit(move: intent, damage: damage, guarded: guarding))
                if playerHealth == 0 {
                    outcome = .lost
                    events.append(.lost)
                }
            }
        }

        guarding = false
        dodging = false
        skillCooldown = max(skillCooldown - 1, 0)
        turn += 1
        lastMove = intent
        if outcome == nil { intent = nextMove() }
        return events
    }

    /// What a boss move would do to you right now. Shown on the next-move chip.
    func incomingDamage(for move: BossMove, guarding: Bool = false) -> Int {
        guard move != .brace else { return 0 }
        var raw = Double(boss.baseHit) * (move == .heavySwing ? BattleRules.heavySwingMultiplier : 1)
        if isEnraged { raw *= BattleRules.enrageMultiplier }
        var damage = max(Int(raw.rounded()) - player.defense, 1)
        if guarding { damage = Int((Double(damage) * BattleRules.guardMultiplier).rounded()) }
        return damage
    }

    /// Weighted pick; never two heavy swings in a row.
    private mutating func nextMove() -> BossMove {
        var options: [(BossMove, Int)] = [(.swipe, BattleRules.swipeWeight), (.brace, BattleRules.braceWeight)]
        if lastMove != .heavySwing { options.append((.heavySwing, BattleRules.heavySwingWeight)) }
        var roll = Int.random(in: 0..<options.reduce(0) { $0 + $1.1 }, using: &rng)
        for (move, weight) in options {
            if roll < weight { return move }
            roll -= weight
        }
        return .swipe
    }
}

// MARK: - Randomness

/// SplitMix64: small, fast and the same on every device, so a seed replays a fight.
nonisolated struct BattleRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    /// A seed from a run id (FNV-1a over its bytes), so each run has its own fight.
    static func seed(for id: UUID) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        withUnsafeBytes(of: id.uuid) { bytes in
            for byte in bytes {
                hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3
            }
        }
        return hash
    }

    mutating func next() -> UInt64 {
        state &+= 0x9e37_79b9_7f4a_7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
        z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
        return z ^ (z >> 31)
    }
}
