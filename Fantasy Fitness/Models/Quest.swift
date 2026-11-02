//
//  Quest.swift
//  Fantasy Fitness
//

import Foundation

enum QuestKind: String, CaseIterable, Identifiable {
    case daily, weekly, story

    var id: Self { self }

    var title: String {
        switch self {
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .story: "Story"
        }
    }

    var actionLabel: String {
        switch self {
        case .daily: "Begin quest"
        // Weekly and story progress already shows on the scroll; their button logs a workout.
        case .weekly, .story: "Log a workout"
        }
    }
}

/// Objectives complete automatically from logged data; the UI never toggles them.
struct QuestObjective: Identifiable {
    var id = UUID().uuidString
    let name: String
    let detail: String
    let isComplete: Bool
    /// Set for lifting objectives; drives the Workout session plan.
    var lift: LiftTarget? = nil
}

/// What a lifting objective asks for. A set counts when it meets both minimums.
struct LiftTarget: Hashable {
    /// Must match the logged exercise name (the server compares case-insensitively).
    let exercise: String
    let sets: Int
    let minReps: Int
    var minWeightLb: Double = 0
    var setsDone = 0

    func counts(reps: Int, weightLb: Double) -> Bool {
        reps >= minReps && weightLb >= minWeightLb
    }
}

struct Quest: Identifiable {
    var id = UUID().uuidString
    let kind: QuestKind
    let arc: String
    let title: String
    let objectives: [QuestObjective]
    let rewards: [String]

    var completedCount: Int { objectives.filter(\.isComplete).count }

    var progress: Double {
        objectives.isEmpty ? 0 : Double(completedCount) / Double(objectives.count)
    }

    var kicker: String { "\(kind.title) quest · \(arc)" }

    /// Lifts this quest asks for, in order; empty for cardio, rest and nutrition quests.
    var liftPlan: [LiftTarget] { objectives.compactMap(\.lift) }
}

// MARK: - Sample data (previews and offline demo mode)

extension Quest {
    static let sampleDaily = Quest(
        kind: .daily,
        arc: "Iron Trial, week 3",
        title: "Push Day",
        objectives: [
            QuestObjective(name: "Bench press", detail: "4 × 6 @ 155 lb", isComplete: true,
                           lift: LiftTarget(exercise: "Bench press", sets: 4, minReps: 6, minWeightLb: 155, setsDone: 4)),
            QuestObjective(name: "Overhead press", detail: "3 × 8 @ 95 lb", isComplete: false,
                           lift: LiftTarget(exercise: "Overhead press", sets: 3, minReps: 8, minWeightLb: 95)),
            QuestObjective(name: "Incline dumbbell press", detail: "3 × 10 @ 50 lb", isComplete: false,
                           lift: LiftTarget(exercise: "Incline dumbbell press", sets: 3, minReps: 10, minWeightLb: 50)),
            QuestObjective(name: "Triceps dips", detail: "3 × 12", isComplete: false,
                           lift: LiftTarget(exercise: "Triceps dips", sets: 3, minReps: 12)),
        ],
        rewards: ["+120 XP", "+ Strength", "Common chest"]
    )

    static let sampleWeekly = Quest(
        kind: .weekly,
        arc: "Iron Trial, week 3",
        title: "Forge Week",
        objectives: [
            QuestObjective(name: "Complete 4 workouts", detail: "2 of 4 logged", isComplete: false),
            QuestObjective(name: "Hit protein goal", detail: "5 days · 3 of 5", isComplete: false),
            QuestObjective(name: "Sleep 7+ hours", detail: "4 nights · 4 of 4", isComplete: true),
            QuestObjective(name: "Walk or jog 10 km", detail: "6.2 of 10 km", isComplete: false),
        ],
        rewards: ["+400 XP", "+ Vitality", "Uncommon chest"]
    )

    static let sampleStory = Quest(
        kind: .story,
        arc: "Iron Trial, chapter 1",
        title: "The Iron Trial",
        objectives: [
            QuestObjective(name: "Week 1: Foundations", detail: "Learn the main lifts", isComplete: true),
            QuestObjective(name: "Week 2: Building heat", detail: "Add volume", isComplete: true),
            QuestObjective(name: "Week 3: The forge", detail: "Heavier top sets", isComplete: false),
            QuestObjective(name: "Week 4: Deload", detail: "Lighter week to recover", isComplete: false),
        ],
        rewards: ["+800 XP", "Rare chest", "Title: Ironbound"]
    )

    static func sample(for kind: QuestKind) -> Quest {
        switch kind {
        case .daily: sampleDaily
        case .weekly: sampleWeekly
        case .story: sampleStory
        }
    }
}
