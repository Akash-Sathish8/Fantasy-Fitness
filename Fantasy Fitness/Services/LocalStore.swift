//
//  LocalStore.swift
//  Fantasy Fitness
//
//  The on-device SwiftData store. Player-created logs (workouts, sets, meals) are saved
//  here first and stay until the server has them. Server-owned data is kept as one
//  snapshot per player, replaced whole on every refresh because the server always wins.
//

import Foundation
import SwiftData

/// A workout on this device: in progress until `finishedAt` is set, then waiting to
/// upload. Deleted once the server has it. `id` is the id the server sees, so a
/// retried upload can't count twice.
@Model
final class LocalWorkout {
    @Attribute(.unique) var id: UUID
    var userID: UUID
    var questID: String?
    var workoutDate: String
    var startedAt: Date
    var finishedAt: Date?
    var isExam: Bool
    /// Why the server last refused this upload.
    var lastError: String?
    @Relationship(deleteRule: .cascade, inverse: \LocalSet.workout) var sets: [LocalSet] = []

    init(id: UUID, userID: UUID, questID: String?, workoutDate: String, startedAt: Date, isExam: Bool = false) {
        self.id = id
        self.userID = userID
        self.questID = questID
        self.workoutDate = workoutDate
        self.startedAt = startedAt
        self.isExam = isExam
    }

    var orderedSets: [LocalSet] { sets.sorted { $0.performedAt < $1.performedAt } }
}

@Model
final class LocalSet {
    @Attribute(.unique) var id: UUID
    var exercise: String
    var weightLb: Double
    var reps: Int
    var performedAt: Date
    var workout: LocalWorkout?

    init(_ set: LoggedSet) {
        id = set.id
        exercise = set.exercise
        weightLb = set.weightLb
        reps = set.reps
        performedAt = set.performedAt
    }
}

/// A logged meal. Its macros are a display copy for today's rations; the server fills
/// in the real ones. Kept after upload until a refresh includes it, so rations don't dip.
@Model
final class LocalMeal {
    @Attribute(.unique) var id: UUID
    var userID: UUID
    var recipeID: UUID
    var servings: Double
    var eatenOn: String
    var calories: Int
    var protein: Int
    var carbs: Int
    var fat: Int
    var uploadedAt: Date?
    var lastError: String?

    init(userID: UUID, recipeID: UUID, servings: Double, eatenOn: String, macros: Macros) {
        id = UUID()
        self.userID = userID
        self.recipeID = recipeID
        self.servings = servings
        self.eatenOn = eatenOn
        calories = macros.calories
        protein = macros.protein
        carbs = macros.carbs
        fat = macros.fat
    }

    var macros: Macros { Macros(calories: calories, protein: protein, carbs: carbs, fat: fat) }
}

/// The last `ServerSnapshot` for a player, as JSON. If a future version can't decode
/// it, that just counts as an empty cache and the next refresh replaces it.
@Model
final class CachedSnapshot {
    @Attribute(.unique) var userID: UUID
    var data: Data
    var fetchedAt: Date

    init(userID: UUID, data: Data, fetchedAt: Date) {
        self.userID = userID
        self.data = data
        self.fetchedAt = fetchedAt
    }
}

final class LocalStore {
    private let context: ModelContext

    init(inMemory: Bool = false) {
        let schema = Schema([LocalWorkout.self, LocalSet.self, LocalMeal.self, CachedSnapshot.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            context = ModelContext(try ModelContainer(for: schema, configurations: configuration))
        } catch {
            // Without a disk store the app still runs, it just can't keep anything.
            assertionFailure("Couldn't open the local store: \(error)")
            let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            context = ModelContext(try! ModelContainer(for: schema, configurations: memory))
        }
        context.autosaveEnabled = false
    }

    // MARK: - Server snapshot

    func snapshot(for user: UUID) -> ServerSnapshot? {
        guard let row = cachedRow(for: user) else { return nil }
        return try? JSONDecoder().decode(ServerSnapshot.self, from: row.data)
    }

    func snapshotDate(for user: UUID) -> Date? {
        cachedRow(for: user)?.fetchedAt
    }

    func save(_ snapshot: ServerSnapshot, for user: UUID) throws {
        let data = try JSONEncoder().encode(snapshot)
        if let row = cachedRow(for: user) {
            row.data = data
            row.fetchedAt = snapshot.fetchedAt
        } else {
            context.insert(CachedSnapshot(userID: user, data: data, fetchedAt: snapshot.fetchedAt))
        }
        try context.save()
    }

    func deleteSnapshot(for user: UUID) throws {
        if let row = cachedRow(for: user) {
            context.delete(row)
            try context.save()
        }
    }

    private func cachedRow(for user: UUID) -> CachedSnapshot? {
        try? context.fetch(FetchDescriptor(predicate: #Predicate<CachedSnapshot> { $0.userID == user })).first
    }

    // MARK: - Workouts

    /// The unfinished workout to resume, if any.
    func draft(for user: UUID) -> WorkoutDraft? {
        let descriptor = FetchDescriptor(predicate: #Predicate<LocalWorkout> { $0.userID == user && $0.finishedAt == nil })
        return (try? context.fetch(descriptor))?.first.map { workout in
            WorkoutDraft(id: workout.id, questID: workout.questID, workoutDate: workout.workoutDate,
                         startedAt: workout.startedAt,
                         sets: workout.orderedSets.map {
                             LoggedSet(id: $0.id, exercise: $0.exercise, weightLb: $0.weightLb, reps: $0.reps,
                                       performedAt: $0.performedAt)
                         })
        }
    }

    /// Saves one set the moment it's logged, creating the workout with its first set.
    func add(_ set: LoggedSet, to session: WorkoutSession, user: UUID) throws {
        let workout = workout(id: session.id) ?? {
            let new = LocalWorkout(id: session.id, userID: user, questID: session.questID,
                                   workoutDate: session.workoutDate, startedAt: session.startedAt)
            context.insert(new)
            return new
        }()
        let local = LocalSet(set)
        context.insert(local)
        local.workout = workout
        try context.save()
    }

    /// Removes a set. A workout with no sets left isn't worth resuming, so it goes too.
    func remove(_ set: LoggedSet, from session: WorkoutSession) throws {
        guard let workout = workout(id: session.id) else { return }
        if let local = workout.sets.first(where: { $0.id == set.id }) {
            workout.sets.removeAll { $0.id == set.id }
            context.delete(local)
        }
        if workout.sets.isEmpty { context.delete(workout) }
        try context.save()
    }

    /// Moves a workout from in progress to the upload queue.
    func finishWorkout(id: UUID) throws {
        workout(id: id)?.finishedAt = .now
        try context.save()
    }

    func deleteWorkout(id: UUID) throws {
        if let workout = workout(id: id) {
            context.delete(workout)
            try context.save()
        }
    }

    func pendingWorkouts(for user: UUID) -> [LocalWorkout] {
        let descriptor = FetchDescriptor(predicate: #Predicate<LocalWorkout> { $0.userID == user && $0.finishedAt != nil },
                                         sortBy: [SortDescriptor(\.startedAt)])
        return (try? context.fetch(descriptor)) ?? []
    }

    private func workout(id: UUID) -> LocalWorkout? {
        try? context.fetch(FetchDescriptor(predicate: #Predicate<LocalWorkout> { $0.id == id })).first
    }

    // MARK: - Meals

    func addMeal(_ meal: LocalMeal) throws {
        context.insert(meal)
        try context.save()
    }

    /// Every meal not yet part of a refresh, uploaded or not.
    func meals(for user: UUID) -> [LocalMeal] {
        (try? context.fetch(FetchDescriptor(predicate: #Predicate<LocalMeal> { $0.userID == user }))) ?? []
    }

    /// Forgets uploaded meals once the refreshed snapshot includes them.
    func deleteUploadedMeals(for user: UUID) throws {
        for meal in meals(for: user) where meal.uploadedAt != nil { context.delete(meal) }
        try context.save()
    }

    /// Commits changes made directly to a model (upload status, last error).
    func save() throws {
        try context.save()
    }
}
