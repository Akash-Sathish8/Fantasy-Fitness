//
//  PlayerProfile.swift
//  Fantasy Fitness
//

import Foundation

enum GuildClass: String, CaseIterable, Identifiable {
    case warrior, ranger, monk, paladin

    var id: Self { self }

    var name: String { rawValue.capitalized }

    var focus: String {
        switch self {
        case .warrior: "Strength"
        case .ranger: "Endurance"
        case .monk: "Calisthenics"
        case .paladin: "Hybrid"
        }
    }
}

enum StatKind: String, CaseIterable, Identifiable {
    case strength, endurance, speed, agility, vitality

    var id: Self { self }

    var name: String { rawValue.capitalized }

    /// Where the stat comes from in real life.
    var source: String {
        switch self {
        case .strength: "Compound lifts, PRs, volume"
        case .endurance: "Cardio duration and volume"
        case .speed: "Pace and sprint times"
        case .agility: "Plyometrics and drills"
        case .vitality: "Sleep, protein and calorie targets"
        }
    }
}

/// Read-only view of the player. XP, stats and inventory are computed server-side.
struct PlayerProfile {
    var displayName: String
    var guildClass: GuildClass
    var rank: String
    var level: Int
    /// Total XP, plus the totals where the current and next level start.
    var xp: Int
    var levelStartXP: Int
    var nextLevelXP: Int
    var energy: Int
    var maxEnergy: Int
    var bodyweightLb: Double?
    var stats: [StatKind: Int]
    var equipped: [Item]
    var appearance: Appearance
    var hasCompletedOnboarding: Bool

    var levelProgress: Double {
        let span = nextLevelXP - levelStartXP
        return span > 0 ? Double(xp - levelStartXP) / Double(span) : 0
    }
}

// MARK: - Sample data (previews and offline demo mode)

extension PlayerProfile {
    static let sample = PlayerProfile(
        displayName: "Rowan",
        guildClass: .warrior,
        rank: "E",
        level: 14,
        xp: 20_340,
        levelStartXP: 18_200,
        nextLevelXP: 21_000,
        energy: EnergyRules.dailyStart,
        maxEnergy: 5,
        bodyweightLb: 185,
        stats: [.strength: 42, .endurance: 28, .speed: 19, .agility: 23, .vitality: 35],
        equipped: [.ironHelm, .leatherJerkin, .oakLongsword, .emberCharm],
        appearance: Appearance(),
        hasCompletedOnboarding: true
    )

    /// Shown for a moment while a signed-in player's profile loads.
    static let empty = PlayerProfile(
        displayName: "Adventurer", guildClass: .warrior, rank: "F", level: 1,
        xp: 0, levelStartXP: 0, nextLevelXP: 200, energy: EnergyRules.dailyStart, maxEnergy: 5, bodyweightLb: nil,
        stats: [:], equipped: [], appearance: Appearance(), hasCompletedOnboarding: false
    )
}

// MARK: - Daily rules (mirror the server; see supabase/migrations)

/// Energy: every player starts each day with at least this much (generate_quests).
/// Each dungeon run spends 1; logging workouts, cardio or 7h+ sleep adds 1, up to the max.
enum EnergyRules {
    static let dailyStart = 4
}

/// Sleep: a night of at least this many hours earns Well-Rested and +1 Energy
/// (after_sleep_logged trigger). A check-in (log_rested_night) records exactly this.
enum Recovery {
    static let wellRestedHours = 7.0

    /// "Well-Rested · slept 7+ hours", or the goal when last night isn't logged yet.
    /// A check-in records exactly the threshold, so it doesn't claim a precise number.
    static func summary(lastNight hours: Double?) -> String {
        guard let hours else { return "Slept \(wellRestedHours.formatted())+ hours? Check in to earn Well-Rested" }
        if hours >= wellRestedHours { return "Well-Rested · slept \(wellRestedHours.formatted())+ hours" }
        let slept = hours.formatted(.number.precision(.fractionLength(0...1)))
        return "Last night: \(slept) h · aim for \(wellRestedHours.formatted())+"
    }
}
