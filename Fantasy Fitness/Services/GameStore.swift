//
//  GameStore.swift
//  Fantasy Fitness
//
//  The app's single source of player data. Views read it from here; it shows the
//  local cache straight away and SyncService keeps that cache in step with Supabase.
//  Workouts, meals and sleep check-ins (SleepService) are saved on the device first. Actions the server has to decide
//  on the spot (gear, dungeons, recipes) need a connection and call it directly.
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
    private(set) var profile: PlayerProfile?
    private(set) var accountEmail: String?
    private(set) var quests: [QuestKind: Quest] = [:]
    private(set) var inventory: [Item] = []
    private(set) var dungeons: [Dungeon] = []
    private(set) var recipes: [Recipe] = []
    private(set) var rations = DailyRations(eaten: .zero, target: .zero)
    private(set) var unlockedExam: RankExam?
    /// The workout left unfinished, shown as "Resume workout".
    private(set) var workoutDraft: WorkoutDraft?
    /// Workout session or battle on screen; reward reveals wait until it closes.
    var isInFullScreenFlow = false
    /// Last error to show the player; views clear it after presenting.
    var errorMessage: String?

    @ObservationIgnored let client: SupabaseClient?
    @ObservationIgnored let sync: SyncService
    @ObservationIgnored let sleep: SleepService
    @ObservationIgnored let food: FoodService
    @ObservationIgnored private let local: LocalStore
    @ObservationIgnored private var userID: UUID?
    @ObservationIgnored private var catalog: [String: Item] = [:]
    @ObservationIgnored private var latestSnapshot: ServerSnapshot?

    init(client: SupabaseClient? = Backend.client) {
        self.client = client
        local = LocalStore(inMemory: client == nil)
        sync = SyncService(client: client, local: local)
        sleep = SleepService(local: local, sync: sync)
        food = FoodService(client: client)
        sync.onSnapshot = { [weak self] in self?.apply($0) }
    }

    var isDemo: Bool { client == nil }
    var hasData: Bool { profile != nil }
    var player: PlayerProfile { profile ?? .empty }
    var equippedIDs: Set<String> { Set(player.equipped.map(\.id)) }
    var refreshError: String? { sync.refreshError }

    /// The next uploaded workout to celebrate, once nothing full screen is in the way.
    var rewardReveal: RewardReveal? {
        guard !isInFullScreenFlow, let reward = sync.rewards.first else { return nil }
        return RewardReveal(id: reward.id, loot: lootDrop(for: reward.result))
    }

    // MARK: - Auth

    /// Restores a saved session so returning players skip the login sheet. With a local
    /// copy of their data they're in immediately, even offline, and it refreshes behind them.
    func resumeSession() async -> Bool {
        guard let client, let session = client.auth.currentSession else { return false }
        if let cached = local.snapshot(for: session.user.id) {
            startUsing(session.user.id)
            apply(cached)
            sync.requestSync()
            return true
        }
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
            errorMessage = ServerError.message(for: error)
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
            errorMessage = "That link didn't work (\(ServerError.message(for: error))). Try logging in with your email and password."
            return false
        }
    }

    /// Uploads what it can first. Anything left stays queued for this player's next login;
    /// only their cached copy of server data is removed.
    func signOut() async {
        if sync.pendingCount > 0 { await sync.sync(waitingUpTo: .seconds(5)) }
        try? await client?.auth.signOut()
        if let userID { try? local.deleteSnapshot(for: userID) }
        sync.setUser(nil)
        sleep.setUser(nil)
        isSignedIn = false
        loadState = .idle
        userID = nil
        latestSnapshot = nil
        accountEmail = nil
        profile = nil
        quests = [:]
        inventory = []
        dungeons = []
        recipes = []
        unlockedExam = nil
        workoutDraft = nil
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
            errorMessage = ServerError.message(for: error)
            return false
        }
    }

    // MARK: - Loading

    /// Loads after signing in. If the data can't be fetched, sign-in fails with a message
    /// rather than dropping the player into empty screens.
    private func loadForSignIn() async -> Bool {
        guard let client, let session = try? await client.auth.session else { return false }
        startUsing(session.user.id)
        await load()
        if case .failed(let message) = loadState {
            errorMessage = "Signed in, but your guild data couldn't load: \(message)"
            return false
        }
        return isSignedIn
    }

    private func startUsing(_ user: UUID) {
        userID = user
        sync.setUser(user)
        sleep.setUser(user)
        workoutDraft = local.draft(for: user)
    }

    /// Uploads anything queued and refreshes from the server. Safe to call repeatedly
    /// (pull to refresh, returning to the app, after every write).
    func load() async {
        guard client != nil else {
            loadDemo()
            return
        }
        if !hasData { loadState = .loading }
        await sync.sync()
        if !hasData {
            loadState = .failed(sync.refreshError ?? "You're offline. Connect once to load your guild.")
        } else if sync.isOffline, let latestSnapshot {
            apply(latestSnapshot)  // the date may have moved on since this was fetched
        }
    }

    /// Turns a snapshot into what the screens show, leaving out anything past its dates.
    private func apply(_ snapshot: ServerSnapshot) {
        latestSnapshot = snapshot
        let today = LocalDate.string()
        accountEmail = snapshot.email

        catalog = Dictionary(snapshot.items.compactMap(\.item).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        inventory = snapshot.inventory.compactMap { catalog[$0.itemID] }
        let equipped = snapshot.inventory.filter(\.equipped).compactMap { catalog[$0.itemID] }
        profile = snapshot.profile.profile(stats: snapshot.stats, equipped: equipped)

        var byKind: [QuestKind: Quest] = [:]
        for row in snapshot.quests where row.startsOn <= today && row.endsOn >= today {
            if let quest = row.quest, byKind[quest.kind] == nil { byKind[quest.kind] = quest }
        }
        quests = byKind

        let cleared = Set(snapshot.clearedDungeonIDs)
        dungeons = snapshot.dungeons.map { $0.dungeon(playerRank: snapshot.profile.rank, cleared: cleared) }
        unlockedExam = snapshot.exams.first?.exam(bodyweight: snapshot.profile.bodyweightLb)

        let ingredients = Dictionary(grouping: snapshot.ingredients, by: \.recipeID)
        recipes = snapshot.recipes.map { row in
            row.recipe(
                ingredients: (ingredients[row.id] ?? []).sorted { $0.position < $1.position }.map(\.ingredient),
                currentUser: userID
            )
        }

        let served = snapshot.day == today ? snapshot.meals : []
        let notYetServed = userID.map { local.meals(for: $0) }?.filter { $0.eatenOn == today } ?? []
        let platesNotYetServed = userID.map { local.plates(for: $0) }?.filter { $0.eatenOn == today } ?? []
        rations = DailyRations(
            eaten: served.reduce(Macros.zero) {
                $0 + Macros(calories: $1.calories, protein: $1.proteinG, carbs: $1.carbsG, fat: $1.fatG)
            } + notYetServed.reduce(Macros.zero) { $0 + $1.macros }
              + platesNotYetServed.reduce(Macros.zero) { $0 + $1.macros },
            target: snapshot.profile.targets
        )
        sleep.apply(snapshot.lastSleep)
        isSignedIn = true
        loadState = .loaded
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
        sleep.setUser(nil, isDemo: true)
        isSignedIn = true
        loadState = .loaded
        // Demo workouts go through the same local store, which only needs some id.
        userID = userID ?? UUID()
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
            errorMessage = ServerError.message(for: error)
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
            errorMessage = ServerError.message(for: error)
            return nil
        }
    }

    // MARK: - Tavern

    /// Saves the meal on the device and counts it toward today's rations right away.
    func logMeal(_ recipe: Recipe, servings: Double = 1) -> Bool {
        guard client != nil, let userID, let recipeID = UUID(uuidString: recipe.id) else {
            rations = DailyRations(eaten: rations.eaten + recipe.macros, target: rations.target)
            return true
        }
        do {
            try local.addMeal(LocalMeal(userID: userID, recipeID: recipeID, servings: servings,
                                        eatenOn: LocalDate.string(), macros: recipe.macros))
        } catch {
            errorMessage = "Couldn't save that on this device. \(error.localizedDescription)"
            return false
        }
        sync.queueChanged()
        if let latestSnapshot { apply(latestSnapshot) }
        sync.requestSync()
        return true
    }

    /// Saves a plate of searched foods on the device and counts it toward today's rations
    /// right away. The server sums the real macros from its food data when it arrives.
    func logPlate(name: String, items: [PlateItem]) -> Bool {
        let macros = FoodMath.plate(items)
        guard client != nil, let userID else {
            rations = DailyRations(eaten: rations.eaten + macros, target: rations.target)
            return true
        }
        let name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(FoodLimits.nameLength))
        do {
            try local.addPlate(LocalPlateMeal(
                userID: userID, name: name, eatenOn: LocalDate.string(),
                items: items.map { NewPlateItem(food_id: $0.food.id, grams: $0.grams) }, macros: macros
            ))
        } catch {
            errorMessage = "Couldn't save that on this device. \(error.localizedDescription)"
            return false
        }
        sync.queueChanged()
        if let latestSnapshot { apply(latestSnapshot) }
        sync.requestSync()
        return true
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

    /// The server works out per-serving macros from the ingredients picked from the food
    /// search; typed-in ingredients are saved but not counted.
    func createRecipe(name: String, mealType: MealType, minutes: Int = 15, servings: Int = 1,
                      ingredients: [RecipeIngredientDraft]) async -> Bool {
        let name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(FoodLimits.nameLength))
        guard let client else {
            let counted = ingredients.compactMap { draft in draft.food.map { ($0.per100g, draft.grams) } }
            recipes.append(Recipe(id: UUID().uuidString, name: name, mealType: mealType, minutes: minutes,
                                  servings: servings,
                                  macros: counted.isEmpty ? .zero : FoodMath.perServing(counted, servings: servings),
                                  ingredients: ingredients.map(\.ingredient),
                                  ratings: RecipeRatings(taste: 0, ease: 0, cost: 0, count: 0), isMine: true))
            return true
        }
        return await perform {
            try await client.rpc("create_recipe", params: CreateRecipeParams(
                p_name: name,
                p_meal_type: mealType.rawValue,
                p_minutes: minutes,
                p_servings: servings,
                p_ingredients: ingredients.map { draft in
                    draft.food.map {
                        NewIngredient(name: draft.name, amount: FoodMath.gramsText(draft.grams), food_id: $0.id,
                                      grams: draft.grams)
                    } ?? NewIngredient(name: draft.name, amount: draft.amount)
                }
            )).execute()
        }
    }

    // MARK: - Workouts

    /// Opens a Workout session, picking up an unfinished one instead if there is one.
    func openWorkout(quest: Quest?) -> ActiveWorkout {
        guard let workoutDraft else { return ActiveWorkout(quest: quest) }
        let saved = quests.values.first { $0.id == workoutDraft.questID }
        return ActiveWorkout(quest: saved, draft: workoutDraft)
    }

    /// Saves a set to the device the moment it's logged.
    func saveSet(_ set: LoggedSet, in session: WorkoutSession) {
        guard let userID else { return }
        saveLocally { try local.add(set, to: session, user: userID) }
        workoutDraft = local.draft(for: userID)
    }

    func removeSet(_ set: LoggedSet, in session: WorkoutSession) {
        saveLocally { try local.remove(set, from: session) }
        workoutDraft = userID.flatMap { local.draft(for: $0) }
    }

    func discardWorkout(_ session: WorkoutSession) {
        saveLocally { try local.deleteWorkout(id: session.id) }
        workoutDraft = nil
    }

    /// Queues a finished workout and tries to upload it. The server's payout comes back
    /// if it gets through quickly; otherwise `.pending`, and it uploads on a later sync.
    func finishWorkout(_ session: WorkoutSession) async -> WorkoutOutcome {
        guard client != nil else {
            discardWorkout(session)
            return .paid(WorkoutResult(xpGained: min(10 * session.sets.count, 300), sets: session.sets.count, itemIDs: []))
        }
        saveLocally { try local.finishWorkout(id: session.id) }
        workoutDraft = nil
        sync.queueChanged()
        await sync.sync(waitingUpTo: .seconds(8))
        return sync.takeReward(for: session.id).map(WorkoutOutcome.paid) ?? .pending
    }

    /// The server's rewards, ready for the loot reveal.
    func lootDrop(for result: WorkoutResult) -> LootDrop {
        let items = result.itemIDs.compactMap { catalog[$0] }
        return LootDrop(title: items.isEmpty ? "Workout saved" : "Quest complete",
                        chestRarity: items.map(\.rarity).max() ?? .common,
                        xp: result.xpGained,
                        items: items)
    }

    private func saveLocally(_ write: () throws -> Void) {
        do {
            try write()
        } catch {
            errorMessage = "Couldn't save that on this device. \(error.localizedDescription)"
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
            errorMessage = ServerError.message(for: error)
            return false
        }
    }

}

/// One set as entered in the Workout session.
struct LoggedSet: Identifiable, Hashable {
    var id = UUID()
    let exercise: String
    let weightLb: Double
    let reps: Int
    var performedAt = Date.now
}

extension LoggedSet {
    /// "1 set", "4 sets".
    static func countLabel(_ count: Int) -> String {
        "\(count) \(count == 1 ? "set" : "sets")"
    }
}

/// A workout saved on the device that was left unfinished.
struct WorkoutDraft {
    let id: UUID
    let questID: String?
    let workoutDate: String
    let startedAt: Date
    let sets: [LoggedSet]
}

/// What `submit_workout` paid out. XP includes any quest the workout completed.
nonisolated struct WorkoutResult: Decodable, Sendable {
    let xpGained: Int
    let sets: Int
    let itemIDs: [String]

    enum CodingKeys: String, CodingKey {
        case sets
        case xpGained = "xp_gained"
        case itemIDs = "item_ids"
    }
}

enum WorkoutOutcome {
    case paid(WorkoutResult)
    /// Saved on the device; the server hasn't seen it yet, so there are no rewards to show.
    case pending
}

/// A reward reveal for a workout that uploaded after the player moved on.
struct RewardReveal: Identifiable {
    let id: UUID
    let loot: LootDrop
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
