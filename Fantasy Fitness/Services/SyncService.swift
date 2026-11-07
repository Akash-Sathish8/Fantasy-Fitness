//
//  SyncService.swift
//  Fantasy Fitness
//
//  Keeps the device and Supabase in step. Each pass uploads whatever is queued on the
//  phone, then replaces the local copy of server-owned data. Runs when the app opens or
//  returns to the foreground, when the connection comes back, after a workout, meal or
//  sleep check-in is saved, and on pull to refresh. The server decides all rewards; this only reports them.
//

import Foundation
import Network
import Observation
import Supabase

/// A workout the server has accepted, and what it paid.
struct UploadedWorkout: Identifiable {
    let id: UUID
    let result: WorkoutResult
}

@Observable
final class SyncService {
    /// The last attempt couldn't reach the server, or the device has no connection.
    private(set) var isOffline = false
    /// The server answered with an error other than being unreachable.
    private(set) var refreshError: String?
    /// Why the server refused a queued log. It stays queued and retries next sync.
    private(set) var uploadError: String?
    private(set) var pendingWorkouts = 0
    private(set) var pendingMeals = 0
    private(set) var pendingSleeps = 0
    private(set) var lastSyncedAt: Date?
    /// Uploaded workouts whose rewards the player hasn't seen yet.
    private(set) var rewards: [UploadedWorkout] = []

    /// Receives each fresh snapshot, after it's saved locally.
    @ObservationIgnored var onSnapshot: ((ServerSnapshot) -> Void)?
    @ObservationIgnored private let client: SupabaseClient?
    @ObservationIgnored private let local: LocalStore
    @ObservationIgnored private var user: UUID?
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private var needsAnotherPass = false
    @ObservationIgnored private let monitor = NWPathMonitor()

    init(client: SupabaseClient?, local: LocalStore) {
        self.client = client
        self.local = local
        if client != nil { startMonitoring() }
    }

    var pendingCount: Int { pendingWorkouts + pendingMeals + pendingSleeps }

    /// "1 workout and 2 meals waiting to upload.", or nil when the queue is empty.
    var queueSummary: String? {
        let parts = [Self.count(pendingWorkouts, "workout"), Self.count(pendingMeals, "meal"),
                     Self.count(pendingSleeps, "sleep check-in")].compactMap { $0 }
        return parts.isEmpty ? nil : ListFormatter.localizedString(byJoining: parts) + " waiting to upload."
    }

    private static func count(_ number: Int, _ noun: String) -> String? {
        number > 0 ? "\(number) \(noun)\(number == 1 ? "" : "s")" : nil
    }

    /// Switches to a player's queue. Logs stay tied to the player who made them.
    func setUser(_ user: UUID?) {
        self.user = user
        rewards = []
        refreshError = nil
        uploadError = nil
        isOffline = false
        lastSyncedAt = user.flatMap { local.snapshotDate(for: $0) }
        queueChanged()
    }

    /// Call after adding to or removing from the local queue.
    func queueChanged() {
        guard let user else {
            pendingWorkouts = 0
            pendingMeals = 0
            pendingSleeps = 0
            return
        }
        pendingWorkouts = local.pendingWorkouts(for: user).count
        pendingMeals = local.meals(for: user).filter { $0.uploadedAt == nil }.count
        pendingSleeps = local.sleeps(for: user).filter { $0.uploadedAt == nil }.count
    }

    // MARK: - Running a sync

    /// Starts a sync without waiting. Requests during a pass are folded into one more pass.
    func requestSync() {
        if syncTask != nil {
            needsAnotherPass = true
            return
        }
        syncTask = Task {
            repeat {
                needsAnotherPass = false
                await pass()
            } while needsAnotherPass
            syncTask = nil
        }
    }

    func sync() async {
        requestSync()
        await syncTask?.value
    }

    /// Syncs, but gives up waiting after a while on a weak connection. The upload
    /// carries on in the background if it's still going.
    func sync(waitingUpTo limit: Duration) async {
        requestSync()
        let deadline = ContinuousClock.now + limit
        while syncTask != nil, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(150))
        }
    }

    /// Hands over a workout's rewards to show right away instead of in a later reveal.
    func takeReward(for workoutID: UUID) -> WorkoutResult? {
        guard let index = rewards.firstIndex(where: { $0.id == workoutID }) else { return nil }
        return rewards.remove(at: index).result
    }

    func dismissReward(_ id: UUID) {
        rewards.removeAll { $0.id == id }
    }

    private func pass() async {
        guard let client, let user else { return }
        do {
            let session = try await client.auth.session
            let today = LocalDate.string()
            // Starts the day on the server: tops Energy up to 4 and posts today's daily,
            // this week's weekly and an active story quest (once onboarding is done).
            // This comes first so a workout logged offline counts toward today's quests.
            try await client.rpc("generate_quests", params: ["p_today": today]).execute()
            try await uploadWorkouts(client, user: user)
            try await uploadMeals(client, user: user)
            try await uploadSleeps(client, user: user)
            let snapshot = try await fetchSnapshot(client, user: user, email: session.user.email, today: today)

            guard self.user == user else { return }  // logged out meanwhile
            try local.save(snapshot, for: user)
            try local.deleteUploadedMeals(for: user)
            try local.deleteUploadedSleeps(for: user)
            lastSyncedAt = snapshot.fetchedAt
            refreshError = nil
            isOffline = false
            onSnapshot?(snapshot)
        } catch {
            guard self.user == user else { return }
            if ServerError.isCancelled(error) { return }
            if ServerError.isUnreachable(error) {
                isOffline = true
                refreshError = nil
            } else {
                isOffline = false
                refreshError = ServerError.message(for: error)
            }
        }
        queueChanged()
    }

    // MARK: - Uploads

    /// Sends each finished workout. Losing the connection stops the pass; a server refusal
    /// only skips that workout, so one bad log can't hold up the rest.
    private func uploadWorkouts(_ client: SupabaseClient, user: UUID) async throws {
        uploadError = nil
        for workout in local.pendingWorkouts(for: user) {
            let id = workout.id
            let params = SubmitWorkoutParams(
                p_id: id,
                p_workout_date: workout.workoutDate,
                p_started_at: workout.startedAt.ISO8601Format(),
                p_is_exam: workout.isExam,
                p_sets: workout.orderedSets.map {
                    NewWorkoutSet(id: $0.id, exercise: $0.exercise, weight_lb: $0.weightLb, reps: $0.reps,
                                  performed_at: $0.performedAt.ISO8601Format())
                },
                p_quest_id: workout.questID.flatMap(UUID.init(uuidString:))
            )
            do {
                let result: WorkoutResult = try await client.rpc("submit_workout", params: params).execute().value
                // If this delete never happens, the next upload just gets the same result back.
                try local.deleteWorkout(id: id)
                rewards.append(UploadedWorkout(id: id, result: result))
            } catch let error where ServerError.isUnreachable(error) || ServerError.isCancelled(error) {
                throw error
            } catch {
                let message = ServerError.message(for: error)
                workout.lastError = message
                uploadError = message
                try local.save()
            }
            queueChanged()
        }
    }

    private func uploadMeals(_ client: SupabaseClient, user: UUID) async throws {
        for meal in local.meals(for: user) where meal.uploadedAt == nil {
            do {
                try await client.rpc("log_meal", params: LogMealParams(
                    p_id: meal.id, p_recipe_id: meal.recipeID, p_servings: meal.servings, p_eaten_on: meal.eatenOn
                )).execute()
                meal.uploadedAt = .now
                meal.lastError = nil
            } catch let error where ServerError.isUnreachable(error) || ServerError.isCancelled(error) {
                throw error
            } catch {
                let message = ServerError.message(for: error)
                meal.lastError = message
                uploadError = message
            }
            try local.save()
            queueChanged()
        }
    }

    private func uploadSleeps(_ client: SupabaseClient, user: UUID) async throws {
        for sleep in local.sleeps(for: user) where sleep.uploadedAt == nil {
            do {
                try await client.rpc("log_rested_night", params: ["p_night_of": sleep.nightOf]).execute()
                sleep.uploadedAt = .now
                sleep.lastError = nil
            } catch let error where ServerError.isUnreachable(error) || ServerError.isCancelled(error) {
                throw error
            } catch {
                let message = ServerError.message(for: error)
                sleep.lastError = message
                uploadError = message
            }
            try local.save()
            queueChanged()
        }
    }

    // MARK: - Refresh

    /// Fetches everything the screens show.
    private func fetchSnapshot(_ client: SupabaseClient, user: UUID, email: String?, today: String) async throws -> ServerSnapshot {
        async let profile: ProfileRow = client.from("profiles").select().eq("id", value: user).single().execute().value
        async let stats: [StatsRow] = client.from("stats").select().execute().value
        async let items: [ItemRow] = client.from("items").select().execute().value
        async let inventory: [InventoryRow] = client.from("inventory").select("item_id, equipped").execute().value
        async let quests: [QuestRow] = client.from("quests")
            .select("id, kind, arc, title, rewards, starts_on, ends_on, quest_objectives(id, position, name, detail, target, progress, is_complete, metric, exercise, min_reps, min_weight_lb)")
            .lte("starts_on", value: today)
            .gte("ends_on", value: today)
            .order("starts_on", ascending: false)
            .execute().value
        async let dungeons: [DungeonRow] = client.from("dungeons").select().order("sort_order").execute().value
        async let cleared: [DungeonRunRow] = client.from("dungeon_runs").select("dungeon_id")
            .eq("victory", value: true).execute().value
        async let exams: [RankExamRow] = client.rpc("unlocked_exams").execute().value
        async let recipes: [RecipeSummaryRow] = client.from("recipe_summaries").select()
            .order("created_at").execute().value
        async let ingredients: [IngredientRow] = client.from("recipe_ingredients").select().execute().value
        async let meals: [MealLogRow] = client.from("meal_logs").select("calories, protein_g, carbs_g, fat_g")
            .eq("eaten_on", value: today).execute().value
        async let sleep: [SleepLogRow] = client.from("sleep_logs").select("night_of, hours")
            .gte("night_of", value: LocalDate.yesterday()).order("night_of", ascending: false).limit(1).execute().value

        return ServerSnapshot(
            fetchedAt: .now,
            day: today,
            email: email,
            profile: try await profile,
            stats: try await stats.first,
            items: try await items,
            inventory: try await inventory,
            quests: try await quests,
            dungeons: try await dungeons,
            clearedDungeonIDs: try await cleared.map(\.dungeonID),
            exams: try await exams,
            recipes: try await recipes,
            ingredients: try await ingredients,
            meals: try await meals,
            lastSleep: try await sleep.first
        )
    }

    // MARK: - Connection

    private func startMonitoring() {
        monitor.pathUpdateHandler = { @Sendable [weak self] path in
            let isConnected = path.status == .satisfied
            Task { @MainActor in self?.connectionChanged(isConnected: isConnected) }
        }
        monitor.start(queue: DispatchQueue(label: "SyncService.connection"))
    }

    private func connectionChanged(isConnected: Bool) {
        if !isConnected {
            isOffline = true
        } else if isOffline {
            requestSync()  // the connection came back
        }
    }
}

/// How Supabase failures read to the player and to the sync logic.
nonisolated enum ServerError {
    static func isCancelled(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    /// The request never got an answer, as opposed to the server refusing it.
    static func isUnreachable(_ error: Error) -> Bool {
        error is URLError && !isCancelled(error)
    }

    static func message(for error: Error) -> String {
        if let error = error as? PostgrestError { return error.message }
        if let error = error as? AuthError { return error.message }
        if isUnreachable(error) { return "You're offline. This needs a connection." }
        return error.localizedDescription
    }
}
