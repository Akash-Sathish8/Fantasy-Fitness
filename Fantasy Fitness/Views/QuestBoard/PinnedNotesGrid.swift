//
//  PinnedNotesGrid.swift
//  Fantasy Fitness
//

import SwiftUI

/// Side notes pinned below the featured quest: nutrition, sleep and guild notices.
struct PinnedNotesGrid: View {
    @Environment(GameStore.self) private var store

    private var rations: DailyRations { store.rations }

    var body: some View {
        VStack(spacing: 26) {
            HStack(alignment: .top, spacing: 14) {
                PinnedNote(rotation: -1.5) {
                    NoteHeading(title: "Ration duty", subtitle: "Protein today")
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(rations.eaten.protein)")
                            .font(.alegreyaSans(22, weight: .bold))
                            .foregroundStyle(Theme.ink)
                        Text("/ \(rations.target.protein) g")
                            .font(.alegreyaSans(16))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    .padding(.top, 6)
                    ParchmentProgressBar(progress: rations.progress(\.protein))
                        .padding(.top, 8)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Ration duty. Protein today, \(rations.eaten.protein) of \(rations.target.protein) grams")

                PinnedNote(rotation: 1.2) {
                    NoteHeading(title: "Rest at the inn", subtitle: "Sleep goal each night")
                    Text("\(Recovery.wellRestedHours.formatted())+ hours")
                        .font(.alegreyaSans(22, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .padding(.top, 6)
                    Text(store.sleep.isWellRested ? "Well-Rested today" : "Earns Well-Rested buff")
                        .font(.alegreyaSans(15, weight: .bold))
                        .foregroundStyle(Theme.positiveText)
                        .padding(.top, 4)
                    SleepCheckButton(label: "Slept 7+ h last night")
                        .padding(.top, 6)
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            if let exam = store.unlockedExam {
                ExamNoticeCard(exam: exam) {
                    // TODO: launch Workout session in exam mode
                }
            }
        }
    }
}

#Preview {
    PinnedNotesGrid()
        .padding()
        .background(WoodBackground())
        .environment(GameStore.preview)
}
