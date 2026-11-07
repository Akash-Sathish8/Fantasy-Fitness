//
//  Rows.swift
//  Fantasy Fitness
//
//  Codable mirrors of the Supabase tables (see supabase/migrations) and their
//  mapping into the app's models. Column names stay snake_case via CodingKeys.
//  Rows are Codable both ways because the local cache stores them as they arrived.
//

import Foundation

// MARK: - Players

nonisolated struct ProfileRow: Codable, Sendable {
    let id: UUID
    let displayName: String
    let guildClass: String
    let rank: String
    let xp: Int
    let level: Int
    let levelStartXP: Int
    let nextLevelXP: Int
    let energy: Int
    let maxEnergy: Int
    let bodyweightLb: Double?
    let calorieTarget: Int
    let proteinTargetG: Int
    let carbsTargetG: Int
    let fatTargetG: Int
    let hasCompletedOnboarding: Bool

    enum CodingKeys: String, CodingKey {
        case id, rank, xp, level, energy
        case displayName = "display_name"
        case guildClass = "guild_class"
        case levelStartXP = "level_start_xp"
        case nextLevelXP = "next_level_xp"
        case maxEnergy = "max_energy"
        case bodyweightLb = "bodyweight_lb"
        case calorieTarget = "calorie_target"
        case proteinTargetG = "protein_target_g"
        case carbsTargetG = "carbs_target_g"
        case fatTargetG = "fat_target_g"
        case hasCompletedOnboarding = "has_completed_onboarding"
    }

    var targets: Macros {
        Macros(calories: calorieTarget, protein: proteinTargetG, carbs: carbsTargetG, fat: fatTargetG)
    }

    func profile(stats: StatsRow?, equipped: [Item]) -> PlayerProfile {
        PlayerProfile(
            displayName: displayName,
            guildClass: GuildClass(rawValue: guildClass) ?? .warrior,
            rank: rank,
            level: level,
            xp: xp,
            levelStartXP: levelStartXP,
            nextLevelXP: nextLevelXP,
            energy: energy,
            maxEnergy: maxEnergy,
            bodyweightLb: bodyweightLb,
            stats: stats?.values ?? [:],
            equipped: equipped,
            hasCompletedOnboarding: hasCompletedOnboarding
        )
    }
}

nonisolated struct StatsRow: Codable, Sendable {
    let strength: Int
    let endurance: Int
    let speed: Int
    let agility: Int
    let vitality: Int

    var values: [StatKind: Int] {
        [.strength: strength, .endurance: endurance, .speed: speed, .agility: agility, .vitality: vitality]
    }
}

// MARK: - Gear

nonisolated struct ItemRow: Codable, Sendable {
    let id: String
    let name: String
    let slot: String
    let rarity: String
    let effect: String
    let flavor: String
    /// Optional so a server without the combat-bonus migration, or a snapshot saved before
    /// it, still decodes; missing means 0.
    let attackBonus: Int?
    let defenseBonus: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, slot, rarity, effect, flavor
        case attackBonus = "attack_bonus"
        case defenseBonus = "defense_bonus"
    }

    var item: Item? {
        guard let slot = ItemSlot(rawValue: slot), let rarity = Rarity(name: rarity) else { return nil }
        return Item(id: id, name: name, slot: slot, rarity: rarity, effect: effect, flavor: flavor,
                    attackBonus: attackBonus ?? 0, defenseBonus: defenseBonus ?? 0)
    }
}

nonisolated struct InventoryRow: Codable, Sendable {
    let itemID: String
    let equipped: Bool

    enum CodingKeys: String, CodingKey {
        case equipped
        case itemID = "item_id"
    }
}

extension Rarity {
    nonisolated init?(name: String) {
        guard let match = Rarity.allCases.first(where: { String(describing: $0) == name }) else { return nil }
        self = match
    }
}

// MARK: - Quests

nonisolated struct QuestRow: Codable, Sendable {
    let id: UUID
    let kind: String
    let arc: String
    let title: String
    let rewards: [String]
    let startsOn: String
    let endsOn: String
    let objectives: [QuestObjectiveRow]

    enum CodingKeys: String, CodingKey {
        case id, kind, arc, title, rewards
        case startsOn = "starts_on"
        case endsOn = "ends_on"
        case objectives = "quest_objectives"
    }

    var quest: Quest? {
        guard let kind = QuestKind(rawValue: kind) else { return nil }
        return Quest(
            id: id.uuidString,
            kind: kind,
            arc: arc,
            title: title,
            objectives: objectives.sorted { $0.position < $1.position }.map(\.objective),
            rewards: rewards
        )
    }
}

nonisolated struct QuestObjectiveRow: Codable, Sendable {
    let id: UUID
    let position: Int
    let name: String
    let detail: String
    let target: Double
    let progress: Double
    let isComplete: Bool
    let metric: String
    let exercise: String?
    let minReps: Int?
    let minWeightLb: Double?

    enum CodingKeys: String, CodingKey {
        case id, position, name, detail, target, progress, metric, exercise
        case isComplete = "is_complete"
        case minReps = "min_reps"
        case minWeightLb = "min_weight_lb"
    }

    var objective: QuestObjective {
        // Show running counts ("2 of 4") for objectives that take more than one step.
        let showsCount = target > 1 && !isComplete
        let count = "\(progress.formatted()) of \(target.formatted())"
        return QuestObjective(
            id: id.uuidString,
            name: name,
            detail: showsCount ? [detail, count].filter { !$0.isEmpty }.joined(separator: " · ") : detail,
            isComplete: isComplete,
            lift: metric == "lift" ? exercise.map {
                LiftTarget(exercise: $0, sets: Int(target), minReps: minReps ?? 1,
                           minWeightLb: minWeightLb ?? 0, setsDone: Int(progress))
            } : nil
        )
    }
}

// MARK: - Dungeons and exams

nonisolated struct DungeonRow: Codable, Sendable {
    let id: String
    let name: String
    let tier: String
    let requiredRank: String
    let boss: String
    let bossHealth: Int
    let energyCost: Int
    let systemImage: String
    let mapX: Double
    let mapY: Double

    enum CodingKeys: String, CodingKey {
        case id, name, tier, boss
        case requiredRank = "required_rank"
        case bossHealth = "boss_health"
        case energyCost = "energy_cost"
        case systemImage = "system_image"
        case mapX = "map_x"
        case mapY = "map_y"
    }

    func dungeon(playerRank: String, cleared: Set<String>) -> Dungeon {
        let status: Dungeon.Status
        if GuildRank.isBelow(playerRank, requiredRank) {
            status = .locked(requirement: "Requires \(requiredRank)-rank")
        } else if cleared.contains(id) {
            status = .cleared
        } else {
            status = .available
        }
        return Dungeon(id: id, name: name, tier: tier, boss: boss, bossHealth: bossHealth,
                       energyCost: energyCost, status: status, systemImage: systemImage,
                       mapPosition: CGPoint(x: mapX, y: mapY))
    }
}

nonisolated struct DungeonRunRow: Codable, Sendable {
    let dungeonID: String

    enum CodingKeys: String, CodingKey {
        case dungeonID = "dungeon_id"
    }
}

nonisolated struct RunResultRow: Decodable, Sendable {
    let xp: Int
    let itemIDs: [String]
    let chestRarity: String

    enum CodingKeys: String, CodingKey {
        case xp
        case itemIDs = "item_ids"
        case chestRarity = "chest_rarity"
    }
}

nonisolated struct RankExamRow: Codable, Sendable {
    let id: String
    let rank: String
    let lift: String
    let bodyweightMultiple: Double

    enum CodingKeys: String, CodingKey {
        case id, rank, lift
        case bodyweightMultiple = "bodyweight_multiple"
    }

    func exam(bodyweight: Double?) -> RankExam {
        RankExam(id: id, rank: rank, lift: lift, bodyweightMultiple: bodyweightMultiple, bodyweight: bodyweight)
    }
}

/// Guild ranks in order, F (lowest) to S.
nonisolated enum GuildRank {
    static let order = ["F", "E", "D", "C", "B", "A", "S"]

    static func isBelow(_ rank: String, _ other: String) -> Bool {
        (order.firstIndex(of: rank) ?? 0) < (order.firstIndex(of: other) ?? 0)
    }
}

// MARK: - Tavern

nonisolated struct RecipeSummaryRow: Codable, Sendable {
    let id: UUID
    let authorID: UUID?
    let name: String
    let mealType: String
    let minutes: Int
    let servings: Int
    let calories: Int?
    let proteinG: Int?
    let carbsG: Int?
    let fatG: Int?
    let avgTaste: Double
    let avgEase: Double
    let avgCost: Double
    let ratingCount: Int

    enum CodingKeys: String, CodingKey {
        case id, name, minutes, servings, calories
        case authorID = "author_id"
        case mealType = "meal_type"
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case avgTaste = "avg_taste"
        case avgEase = "avg_ease"
        case avgCost = "avg_cost"
        case ratingCount = "rating_count"
    }

    func recipe(ingredients: [Ingredient], currentUser: UUID?) -> Recipe {
        Recipe(
            id: id.uuidString,
            name: name,
            mealType: MealType(rawValue: mealType) ?? .snack,
            minutes: minutes,
            servings: servings,
            // Zero until macros are calculated from the ingredients.
            macros: Macros(calories: calories ?? 0, protein: proteinG ?? 0, carbs: carbsG ?? 0, fat: fatG ?? 0),
            ingredients: ingredients,
            ratings: RecipeRatings(taste: avgTaste, ease: avgEase, cost: avgCost, count: ratingCount),
            isMine: authorID != nil && authorID == currentUser
        )
    }
}

nonisolated struct IngredientRow: Codable, Sendable {
    let recipeID: UUID
    let position: Int
    let name: String
    let amount: String

    enum CodingKeys: String, CodingKey {
        case position, name, amount
        case recipeID = "recipe_id"
    }
}

nonisolated struct SleepLogRow: Codable, Sendable {
    let nightOf: String
    let hours: Double

    enum CodingKeys: String, CodingKey {
        case hours
        case nightOf = "night_of"
    }
}

nonisolated struct MealLogRow: Codable, Sendable {
    let calories: Int
    let proteinG: Int
    let carbsG: Int
    let fatG: Int

    enum CodingKeys: String, CodingKey {
        case calories
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
    }
}

// MARK: - Local cache

/// Everything the screens show from the server, fetched together and cached as one.
nonisolated struct ServerSnapshot: Codable, Sendable {
    let fetchedAt: Date
    /// Local date of the fetch. `meals` only covers this day.
    let day: String
    let email: String?
    let profile: ProfileRow
    let stats: StatsRow?
    let items: [ItemRow]
    let inventory: [InventoryRow]
    let quests: [QuestRow]
    let dungeons: [DungeonRow]
    let clearedDungeonIDs: [String]
    let exams: [RankExamRow]
    let recipes: [RecipeSummaryRow]
    let ingredients: [IngredientRow]
    let meals: [MealLogRow]
    let lastSleep: SleepLogRow?
}

// MARK: - Writes

nonisolated struct NewRating: Encodable, Sendable {
    let recipe_id: UUID
    let taste: Int
    let ease: Int
    let cost: Int
}

nonisolated struct NewWorkoutSet: Encodable, Sendable {
    let id: UUID
    let exercise: String
    let weight_lb: Double
    let reps: Int
    let performed_at: String
}

nonisolated struct SubmitWorkoutParams: Encodable, Sendable {
    let p_id: UUID
    let p_workout_date: String
    let p_started_at: String
    let p_is_exam: Bool
    let p_sets: [NewWorkoutSet]
    let p_quest_id: UUID?
}

nonisolated struct LogMealParams: Encodable, Sendable {
    let p_id: UUID
    let p_recipe_id: UUID
    let p_servings: Double
    let p_eaten_on: String
}

nonisolated struct NewIngredient: Encodable, Sendable {
    let name: String
    let amount: String
}

/// The player's local calendar date as "yyyy-MM-dd", which the server uses for
/// daily and weekly quest windows.
nonisolated enum LocalDate {
    static func string(for date: Date = .now, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func yesterday(calendar: Calendar = .current) -> String {
        string(for: calendar.date(byAdding: .day, value: -1, to: .now) ?? .now, calendar: calendar)
    }
}
