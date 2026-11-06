//
//  WorkoutSession.swift
//  Fantasy Fitness
//
//  State for one Workout session: the planned lifts, the sets logged so far, which
//  exercise is current, and the rest timer that starts after each set. The view saves
//  each set to the device as it's logged; finishing queues the workout for upload.
//

import Foundation
import Observation

@Observable
final class WorkoutSession {
    /// The server refuses longer names, which would leave the workout stuck in the queue.
    private static let maxExerciseNameLength = 80

    /// One exercise in the session, planned by a quest or added by the player.
    struct Exercise: Identifiable, Hashable {
        var id: String { name.lowercased() }
        let name: String
        var target: LiftTarget?
    }

    let id: UUID
    let questID: String?
    let startedAt: Date
    /// The day this workout counts for: the day it started, whenever it uploads.
    let workoutDate: String
    private(set) var exercises: [Exercise]
    private(set) var sets: [LoggedSet]
    var currentName = ""
    let restTimer = RestTimer()

    /// Starts fresh for `quest`, or picks up `draft` where it was left.
    init(quest: Quest?, draft: WorkoutDraft? = nil) {
        id = draft?.id ?? UUID()
        questID = draft?.questID ?? quest?.id
        startedAt = draft?.startedAt ?? .now
        workoutDate = draft?.workoutDate ?? LocalDate.string()
        let saved = draft?.sets ?? []
        sets = saved

        var planned = quest?.liftPlan.map { Exercise(name: $0.exercise, target: $0) } ?? []
        for set in saved where !planned.contains(where: { $0.id == set.exercise.lowercased() }) {
            planned.append(Exercise(name: set.exercise, target: nil))
        }
        exercises = planned

        // Start on the first lift the quest still needs.
        currentName = exercises.first { $0.target != nil && !isDone($0) }?.name
            ?? sets.last?.exercise ?? exercises.first?.name ?? ""
    }

    var current: Exercise? { exercises.first { $0.name == currentName } }
    var hasSets: Bool { !sets.isEmpty }

    func sets(for name: String) -> [LoggedSet] {
        sets.filter { $0.exercise.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Sets that meet the quest's minimums, including ones already logged earlier today.
    func countingSets(for exercise: Exercise) -> Int {
        guard let target = exercise.target else { return sets(for: exercise.name).count }
        return target.setsDone + sets(for: exercise.name).filter {
            target.counts(reps: $0.reps, weightLb: $0.weightLb)
        }.count
    }

    func isDone(_ exercise: Exercise) -> Bool {
        guard let target = exercise.target else { return false }
        return countingSets(for: exercise) >= target.sets
    }

    /// Weight to prefill: the last set of this exercise, else the quest's minimum.
    func suggestedWeight(for name: String) -> Double {
        sets(for: name).last?.weightLb ?? current?.target?.minWeightLb ?? 0
    }

    func suggestedReps(for name: String) -> Int {
        sets(for: name).last?.reps ?? current?.target?.minReps ?? 8
    }

    // MARK: - Actions

    func select(_ name: String) {
        currentName = name
    }

    /// Adds an exercise the quest didn't plan (or switches to it if it's already listed).
    func addExercise(named rawName: String) {
        let name = String(rawName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxExerciseNameLength))
        guard !name.isEmpty else { return }
        if let existing = exercises.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            currentName = existing.name
        } else {
            exercises.append(Exercise(name: name, target: nil))
            currentName = name
        }
    }

    /// Logs a set for the current exercise and starts the rest timer. When the quest's
    /// sets for this lift are done, moves on to the next unfinished lift.
    /// Returns the new set for the caller to save.
    func logSet(weightLb: Double, reps: Int) -> LoggedSet? {
        guard let exercise = current, reps > 0 else { return nil }
        let set = LoggedSet(exercise: exercise.name, weightLb: max(weightLb, 0), reps: reps)
        sets.append(set)
        restTimer.start()
        if isDone(exercise), let next = exercises.first(where: { !isDone($0) && $0.target != nil }) {
            currentName = next.name
        }
        return set
    }

    func removeSet(_ set: LoggedSet) {
        sets.removeAll { $0.id == set.id }
        if sets.isEmpty { restTimer.stop() }
    }
}

/// Countdown between sets. Stores an end time rather than ticking, so it stays right
/// while the app is in the background.
@Observable
final class RestTimer {
    static let presets: [TimeInterval] = [60, 90, 120, 180]

    /// Chosen rest length, used each time a set is logged.
    var duration: TimeInterval = 90
    /// Length of the rest in progress, including any +/- adjustments.
    private(set) var currentTotal: TimeInterval = 90
    private(set) var endDate: Date?
    /// Time left while paused.
    private(set) var pausedRemaining: TimeInterval?

    var isRunning: Bool { endDate != nil }
    var isPaused: Bool { pausedRemaining != nil }
    var isActive: Bool { isRunning || isPaused }

    func remaining(at now: Date) -> TimeInterval {
        if let pausedRemaining { return pausedRemaining }
        guard let endDate else { return 0 }
        return max(endDate.timeIntervalSince(now), 0)
    }

    /// 0…1 of the rest still to go.
    func fractionRemaining(at now: Date) -> Double {
        currentTotal > 0 ? min(remaining(at: now) / currentTotal, 1) : 0
    }

    func start() {
        pausedRemaining = nil
        currentTotal = duration
        endDate = Date.now.addingTimeInterval(duration)
    }

    func togglePause() {
        if let pausedRemaining {
            endDate = Date.now.addingTimeInterval(pausedRemaining)
            self.pausedRemaining = nil
        } else if let endDate {
            pausedRemaining = max(endDate.timeIntervalSinceNow, 0)
            self.endDate = nil
        }
    }

    /// Adds (or with a negative value, removes) time from the rest in progress.
    func adjust(by seconds: TimeInterval) {
        if let pausedRemaining {
            self.pausedRemaining = max(pausedRemaining + seconds, 0)
        } else if let endDate {
            self.endDate = max(endDate.addingTimeInterval(seconds), .now)
        }
        currentTotal = max(currentTotal + seconds, 1)
    }

    func stop() {
        endDate = nil
        pausedRemaining = nil
    }
}
