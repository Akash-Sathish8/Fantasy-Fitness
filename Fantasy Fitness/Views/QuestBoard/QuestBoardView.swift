//
//  QuestBoardView.swift
//  Fantasy Fitness
//

import SwiftUI

struct QuestBoardView: View {
    @State private var selectedKind: QuestKind = .daily
    @State private var activeWorkout: ActiveWorkout?

    @Environment(GameStore.self) private var store

    var body: some View {
        BoardScreen {
            PlayerStatusBar(profile: store.player)
            BoardSign(title: "Quest Board")
            WoodSegmentedPicker(options: QuestKind.allCases, selection: $selectedKind, title: \.title)
            if let quest = store.quests[selectedKind] {
                QuestScroll(quest: quest, actionLabel: store.workoutDraft == nil ? quest.kind.actionLabel : "Resume workout") {
                    // Daily quests open the logger with their lifts; weekly / story progress
                    // comes from any logged workout, so those open a free session.
                    activeWorkout = store.openWorkout(quest: quest.kind == .daily ? quest : nil)
                }
                .padding(.top, 4)
            } else {
                ParchmentCard {
                    NoteHeading(title: "No \(selectedKind.title.lowercased()) quest posted",
                                subtitle: store.sync.isOffline ? "New quests arrive when you're back online."
                                    : "New quests are posted each day and week.")
                }
            }
            PinnedNotesGrid()
                .padding(.top, 8)
        }
        .workoutSessionCover($activeWorkout)
    }
}

// MARK: - Featured quest scroll

private struct QuestScroll: View {
    let quest: Quest
    let actionLabel: String
    let action: () -> Void

    var body: some View {
        ParchmentScroll {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    KickerText(quest.kicker)
                    Text(quest.title)
                        .font(.alegreya(30, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                }
                Spacer(minLength: 8)
                WaxSeal(kind: quest.kind)
            }

            HStack(spacing: 10) {
                ParchmentProgressBar(progress: quest.progress, height: 14)
                Text("\(quest.completedCount) of \(quest.objectives.count)")
                    .font(.alegreyaSans(15, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .monospacedDigit()
            }
            .padding(.top, 10)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(quest.completedCount) of \(quest.objectives.count) objectives complete")

            VStack(spacing: 0) {
                ForEach(quest.objectives) { objective in
                    ObjectiveRow(objective: objective)
                    DashedDivider()
                }
            }
            .padding(.top, 14)

            Text("Rewards")
                .font(.alegreya(17))
                .foregroundStyle(Theme.ink)
                .padding(.top, 14)

            FlowLayout(spacing: 10) {
                ForEach(quest.rewards, id: \.self) { reward in
                    TagChip(label: reward)
                }
            }
            .padding(.top, 10)

            Button(actionLabel, action: action)
                .buttonStyle(.chunky(.wax, fontSize: 21))
                .padding(.top, 22)
        }
    }
}

private struct WaxSeal: View {
    let kind: QuestKind

    var body: some View {
        EmblemBadge(palette: .wax, size: 50) {
            switch kind {
            case .daily:
                SwordShape()
                    .stroke(Theme.cream, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                    .frame(width: 18, height: 30)
                    .rotationEffect(.degrees(-45))
            case .weekly:
                Image(systemName: "calendar")
            case .story:
                Image(systemName: "book.closed")
            }
        }
        .accessibilityHidden(true)
    }
}

/// Read-only: objectives complete from logged data, never by tapping.
private struct ObjectiveRow: View {
    let objective: QuestObjective

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(objective.isComplete ? Theme.progressGreen : Theme.checkboxFill)
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(Theme.outline, lineWidth: 3)
                if objective.isComplete {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(Theme.cream)
                }
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(objective.name)
                    .font(.alegreyaSans(19, weight: .bold))
                    .foregroundStyle(objective.isComplete ? Theme.inkSecondary.opacity(0.7) : Theme.ink)
                    .strikethrough(objective.isComplete, color: Theme.inkSecondary)
                Text(objective.detail)
                    .font(.alegreyaSans(15))
                    .foregroundStyle(Theme.inkSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityValue(objective.isComplete ? "Complete" : "Not complete")
    }
}

#Preview {
    NavigationStack {
        QuestBoardView()
    }
    .environment(GameStore.preview)
}
