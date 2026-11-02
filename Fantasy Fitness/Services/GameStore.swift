//
//  GameStore.swift
//  Fantasy Fitness
//
//  The app's single source of player data. Reads come from Supabase; writes send
//  raw data (meals, ratings, sets) or call server functions that decide rewards.
//  Without Config/Secrets.plist it runs in offline demo mode on sample data.
//

import Foundation
import Observation
import Supabase

@Observable
final class GameStore {
    /// Progress of the most recent load. Screens show a loading or error board while
    /// there is no data yet; after that, refresh failures keep the last good data.
    enum LoadState: Equatable {
        case idle, loading, loaded
        case failed(String)
    }

    private(set) var isSignedIn = false
    private(set) var loadState: LoadState = .idle
    /// Set when a refresh fails while older data is still on screen.
    private(set) var refreshError: String?
    private(set) var profile: PlayerProfile?
    /// Hours slept last night, if the player has logged it.
    private(set) var lastNightSleepHours: Double?
    private(set) var accountEmail: String?
    private(set) var quests: [QuestKind: Quest] = [:]
    private(set) var inventory: [Item] = []
    private(set) var dungeons: [Dungeon] = []
    private(set) var recipes: [Recipe] = []
    private(set) var rations = DailyRations(eaten: .zero, target: .zero)
    private(set) var unlockedExam: RankExam?
    /// Last error to show the player; views clear it after presenting.
    var errorMessage: String?

    @ObservationIgnored let client: SupabaseClient?
    @ObservationIgnored private var userID: UUID?
    @ObservationIgnored private var catalog: [String: Item] = [:]

    init(client: SupabaseClient? = Backend.client) {
        self.client = client
    }

    var isDemo: Bool { client == nil }
    var hasData: Bool { profile != nil }
    var player: PlayerProfile { profile ?? .empty }
    var equippedIDs: Set<String> { Set(player.equipped.map(\.id)) }

    // MARK: - Auth

    /// Restores a saved session so returning players skip the login sheet.
    func resumeSession() async -> Bool {
        guard let client, client.auth.currentSession != nil else { return false }
        do {
            _ = try await client.auth.session
            return await loadForSignIn()
        } catch {
            return false
        }
    }

    func signInWithApple(idToken: String, nonce: String) async -> Bool {
        await authenticate {
            try await $0.auth.signInWithIdToken(credentials: .init(provider: .apple, idToken: idToken, nonce: nonce))
        }
    }

    func signInWithGoogle() async -> Bool {
        await authenticate {
            try await $0.auth.signInWithOAuth(provider: .google, redirectTo: Backend.authRedirectURL)
        }
    }

    func signIn(email: String, password: String) async -> Bool {
        await authenticate { try await $0.auth.signIn(email: email, password: password) }
    }

    /// Creates an account. Returns false if Supabase wants the email confirmed first.
    func signUp(email: String, password: String) async -> Bool {
        guard let client else { return await authenticate { _ in nil } }
        do {
            let response = try await client.auth.signUp(email: email, password: password)
            guard response.session != nil else {
                errorMessage = "Check your email and tap the confirmation link on this device. "
                    + "If you open it elsewhere, come back and log in once it says you're confirmed."
                return false
            }
            return await loadForSignIn()
        } catch {
            errorMessage = Self.message(for: error)
            return false
        }
    }

    /// Finishes sign-in from an email confirmation (or other auth) link that opened the app.
    func handleAuthRedirect(_ url: URL) async -> Bool {
        guard let client, url.scheme == Backend.authRedirectURL.scheme else { return false }
        do {
            try await client.auth.session(from: url)
            return await loadForSignIn()
        } catch {
            errorMessage = "That link didn't work (\(Self.message(for: error))). Try logging in with your email and password."
            return false
        }
    }

    func signOut() async {
        try? await client?.auth.signOut()
        isSignedIn = false
        loadState = .idle
        refreshError = nil
        userID = nil
        accountEmail = nil
        lastNightSleepHours = nil
        profile = nil
        quests = [:]
        inventory = []
        dungeons = []
        recipes = []
        unlockedExam = nil
    }

    private func authenticate(_ action: (SupabaseClient) async throws -> Session?) async -> Bool {
        guard let client else {
            loadDemo()
            return true
        }
        do {
            _ = try await action(client)
            return await loadForSignIn()
        } catch {
            errorMessage = Self.message(for: error)
            return false
        }
    }

    // MARK: - Loading

    /// Loads after signing in. If the data can't be fetched, sign-in fails with a message
    /// rather than dropping the player into empty screens.
    private func loadForSignIn() async -> Bool {
        await load()
        if case .failed(let message) = loadState {
            errorMessage = "Signed in, but your guild data couldn't load: \(message)"
            return false
        }
        return isSignedIn
    }

    /// Fetches everything the screens show. Safe to call repeatedly (pull to refresh,
    /// returning to the app, after every write).
    func load() async {
        guard let client else {
            loadDemo()
            return
        }
        if !hasData { loadState = .loading }
        do {
            let user = try await client.auth.session.user
            userID = user.id
            accountEmail = user.email
            let today = LocalDate.string()
            let yesterday = LocalDate.string(for: Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now)

            // Starts the day on the server: tops Energy up to 4 and posts today's daily,
            // this week's weekly and an active story quest (once onboarding is done).
            try await client.rpc("generate_quests", params: ["p_today": today]).execute()
            let profileRow = try await fetchProfile(client, user: user.id)

            async let statsRows: [StatsRow] = client.from("stats").select().execute().value
            async let itemRows: [ItemRow] = client.from("items").select().execute().value
            async let inventoryRows: [InventoryRow] = client.from("inventory").select("item_id, equipped").execute().value
            async let questRows: [QuestRow] = client.from("quests")
                .select("id, kind, arc, title, rewards, starts_on, quest_objectives(id, position, name, detail, target, progress, is_complete, metric, exercise, min_reps, min_weight_lb)")
                .lte("starts_on", value: today)
                .gte("ends_on", value: today)
                .order("starts_on", ascending: false)
                .execute().value
            async let dungeonRows: [DungeonRow] = client.from("dungeons").select().order("sort_order").execute().value
            async let clearedRows: [DungeonRunRow] = client.from("dungeon_runs").select("dungeon_id")
                .eq("victory", value: true).execute().value
            async let examRows: [RankExamRow] = client.rpc("unlocked_exams").execute().value
            async let recipeRows: [RecipeSummaryRow] = client.from("recipe_summaries").select()
                .order("created_at").execute().value
            async let ingredientRows: [IngredientRow] = client.from("recipe_ingredients").select().execute().value
            async let mealRows: [MealLogRow] = client.from("meal_logs").select("calories, protein_g, carbs_g, fat_g")
                .eq("eaten_on", value: today).execute().value
            async let sleepRows: [SleepLogRow] = client.from("sleep_logs").select("night_of, hours")
                .gte("night_of", value: yesterday).order("night_of", ascending: false).limit(1).execute().value

            catalog = Dictionary(try await itemRows.compactMap(\.item).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let owned = try await inventoryRows
            inventory = owned.compactMap { catalog[$0.itemID] }
            let equipped = owned.filter(\.equipped).compactMap { catalog[$0.itemID] }
            profile = profileRow.profile(stats: try await statsRows.first, equipped: equipped)

            var byKind: [QuestKind: Quest] = [:]
            for quest in try await questRows.compactMap(\.quest) where byKind[quest.kind] == nil {
                byKind[quest.kind] = quest
            }
            quests = byKind

            let cleared = Set(try await clearedRows.map(\.dungeonID))
            dungeons = try await dungeonRows.map { $0.dungeon(playerRank: profileRow.rank, cleared: cleared) }
            unlockedExam = try await examRows.first?.exam(bodyweight: profileRow.bodyweightLb)

            let ingredients = Dictionary(grouping: try await ingredientRows, by: \.recipeID)
            recipes = try await recipeRows.map { row in
                row.recipe(
                    ingredients: (ingredients[row.id] ?? []).sorted { $0.position < $1.position }
                        .map { Ingredient(name: $0.name, amount: $0.amount) },
                    currentUser: user.id
                )
            }

            let meals = try await mealRows
            rations = DailyRations(
                eaten: Macros(calories: meals.map(\.calories).reduce(0, +),
                              protein: meals.map(\.proteinG).reduce(0, +),
                              carbs: meals.map(\.carbsG).reduce(0, +),
                              fat: meals.map(\.fatG).reduce(0, +)),
                target: profileRow.targets
            )
            lastNightSleepHours = try await sleepRows.first?.hours
            isSignedIn = true
            loadState = .loaded
            refreshError = nil
        } catch is CancellationError {
            // A newer refresh replaced this one; keep whatever is on screen.
        } catch {
            let message = Self.message(for: error)
            if hasData {
                refreshError = message
            } else {
                loadState = .failed(message)
            }
        }
    }

    private func fetchProfile(_ client: SupabaseClient, user: UUID) async throws -> ProfileRow {
        try await client.from("profiles").select().eq("id", value: user).single().execute().value
    }

    /// Demo-mode store filled with sample data, for SwiftUI previews.
    static var preview: GameStore {
        let store = GameStore(client: nil)
        store.loadDemo()
        return store
    }

    private func loadDemo() {
        profile = .sample
        quests = [.daily: .sampleDaily, .weekly: .sampleWeekly, .story: .sampleStory]
        inventory = Item.sampleInventory
        dungeons = Dungeon.sampleMap
        recipes = Recipe.samples
        rations = .sample
        unlockedExam = .sample
        lastNightSleepHours = 7.5
        isSignedIn = true
        loadState = .loaded
    }

    // MARK: - Onboarding

    func completeOnboarding(guildClass: GuildClass, displayName: String, bodyweightLb: Double?) async -> Bool {
        guard let client else {
            profile?.guildClass = guildClass
            profile?.hasCompletedOnboarding = true
            return true
        }
        return await perform {
            try await client.rpc("complete_onboarding", params: OnboardingParams(
                p_class: guildClass.rawValue,
                p_display_name: displayName,
                p_bodyweight_lb: bodyweightLb,
                p_today: LocalDate.string()
            )).execute()
        }
    }

    // MARK: - Gear

    func equip(_ item: Item) async {
        guard let client else {
            profile?.equipped.removeAll { $0.slot == item.slot }
            profile?.equipped.append(item)
            return
        }
        _ = await perform { try await client.rpc("equip_item", params: ["p_item_id": item.id]).execute() }
    }

    func unequip(_ item: Item) async {
        guard let client else {
            profile?.equipped.removeAll { $0 == item }
            return
        }
        _ = await perform { try await client.rpc("unequip_item", params: ["p_item_id": item.id]).execute() }
    }

    // MARK: - Dungeons

    /// Spends Energy and opens a run. Returns nil (and sets `errorMessage`) if the server refuses.
    func startRun(in dungeon: Dungeon) async -> UUID? {
        guard let client else { return UUID() }
        do {
            let runID: UUID = try await client.rpc("start_dungeon_run", params: ["p_dungeon_id": dungeon.id])
                .execute().value
            await load()  // shows the Energy just spent
            return runID
        } catch {
            errorMessage = Self.message(for: error)
            return nil
        }
    }

    /// Reports the outcome; the server decides XP and loot.
    func finishRun(_ runID: UUID, victory: Bool) async -> LootDrop? {
        guard let client else { return victory ? .sampleDungeon : nil }
        do {
            let result: RunResultRow = try await client.rpc("finish_dungeon_run", params: FinishRunParams(
                p_run_id: runID, p_victory: victory
            )).execute().value
            await load()
            guard victory else { return nil }
            return LootDrop(title: "Dungeon cleared",
                            chestRarity: Rarity(name: result.chestRarity) ?? .common,
                            xp: result.xp,
                            items: result.itemIDs.compactMap { catalog[$0] })
        } catch {
            errorMessage = Self.message(for: error)
            return nil
        }
    }

    // MARK: - Tavern

    func logMeal(_ recipe: Recipe, servings: Double = 1) async -> Bool {
        guard let client, let recipeID = UUID(uuidString: recipe.id) else {
            rations = DailyRations(eaten: rations.eaten + recipe.macros, target: rations.target)
            return true
        }
        return await perform {
            try await client.from("meal_logs")
                .insert(NewMealLog(recipe_id: recipeID, servings: servings, eaten_on: LocalDate.string()))
                .execute()
        }
    }

    func rate(_ recipe: Recipe, taste: Int, ease: Int, cost: Int) async -> Bool {
        guard let client, let recipeID = UUID(uuidString: recipe.id) else { return true }
        return await perform {
            try await client.from("recipe_ratings")
                .upsert(NewRating(recipe_id: recipeID, taste: taste, ease: ease, cost: cost),
                        onConflict: "recipe_id,user_id", returning: .minimal)
                .execute()
        }
    }

    func createRecipe(name: String, mealType: MealType, minutes: Int = 15, servings: Int = 1,
                      ingredients: [Ingredient]) async -> Bool {
        guard let client else {
            recipes.append(Recipe(id: UUID().uuidString, name: name, mealType: mealType, minutes: minutes,
                                  servings: servings, macros: .zero, ingredients: ingredients,
                                  ratings: RecipeRatings(taste: 0, ease: 0, cost: 0, count: 0), isMine: true))
            return true
        }
        return await perform {
            try await client.rpc("create_recipe", params: CreateRecipeParams(
                p_name: name,
                p_meal_type: mealType.rawValue,
                p_minutes: minutes,
                p_servings: servings,
                p_ingredients: ingredients.map { NewIngredient(name: $0.name, amount: $0.amount) }
            )).execute()
        }
    }

    // MARK: - Workouts

    /// Uploads a finished workout's sets, then asks the server to award XP, stats and
    /// quest progress. For the upcoming Workout session screen.
    /// Returns the server's payout, or nil (with `errorMessage` set) if it couldn't be saved.
    func submitWorkout(sets: [LoggedSet], questID: String? = nil, isExam: Bool = false) async -> WorkoutResult? {
        guard let client else {
            return WorkoutResult(xpGained: min(10 * sets.count, 300), sets: sets.count)
        }
        let workoutID = UUID()
        do {
            try await client.from("workouts").insert(NewWorkout(
                id: workoutID,
                quest_id: questID.flatMap(UUID.init(uuidString:)),
                workout_date: LocalDate.string(),
                is_exam: isExam
            ), returning: .minimal).execute()
            try await client.from("workout_sets").insert(sets.map {
                NewWorkoutSet(workout_id: workoutID, exercise: $0.exercise, weight_lb: $0.weightLb, reps: $0.reps)
            }, returning: .minimal).execute()
            let result: WorkoutResult = try await client.rpc("complete_workout", params: ["p_workout_id": workoutID])
                .execute().value
            await load()
            return result
        } catch {
            errorMessage = Self.message(for: error)
            return nil
        }
    }

    // MARK: - Helpers

    /// Runs a write, then reloads so the UI shows the server's results.
    private func perform(_ write: () async throws -> Void) async -> Bool {
        do {
            try await write()
            await load()
            return true
        } catch {
            errorMessage = Self.message(for: error)
            return false
        }
    }

    private static func message(for error: Error) -> String {
        if let error = error as? PostgrestError { return error.message }
        if let error = error as? AuthError { return error.message }
        return error.localizedDescription
    }
}

/// One set as entered in the Workout session.
struct LoggedSet: Identifiable, Hashable {
    var id = UUID()
    let exercise: String
    let weightLb: Double
    let reps: Int
}

/// What `complete_workout` paid out.
nonisolated struct WorkoutResult: Decodable, Sendable {
    let xpGained: Int
    let sets: Int

    enum CodingKeys: String, CodingKey {
        case sets
        case xpGained = "xp_gained"
    }
}

// MARK: - RPC parameters

nonisolated private struct OnboardingParams: Encodable, Sendable {
    let p_class: String
    let p_display_name: String
    let p_bodyweight_lb: Double?
    let p_today: String
}

nonisolated private struct FinishRunParams: Encodable, Sendable {
    let p_run_id: UUID
    let p_victory: Bool
}

nonisolated private struct CreateRecipeParams: Encodable, Sendable {
    let p_name: String
    let p_meal_type: String
    let p_minutes: Int
    let p_servings: Int
    let p_ingredients: [NewIngredient]
}

extension Macros {
    static let zero = Macros(calories: 0, protein: 0, carbs: 0, fat: 0)

    static func + (lhs: Macros, rhs: Macros) -> Macros {
        Macros(calories: lhs.calories + rhs.calories, protein: lhs.protein + rhs.protein,
               carbs: lhs.carbs + rhs.carbs, fat: lhs.fat + rhs.fat)
    }
}
