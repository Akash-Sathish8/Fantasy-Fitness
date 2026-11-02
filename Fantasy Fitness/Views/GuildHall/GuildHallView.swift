//
//  GuildHallView.swift
//  Fantasy Fitness
//

import SwiftUI

/// Home hub: who you are, today's quests, Energy and unlocked exams.
struct GuildHallView: View {
    let onOpenQuests: () -> Void
    let onLogOut: () -> Void

    @Environment(GameStore.self) private var store
    @State private var showingSettings = false
    @State private var activeWorkout: ActiveWorkout?

    private var profile: PlayerProfile { store.player }
    private var rations: DailyRations { store.rations }

    var body: some View {
        BoardScreen {
            PlayerStatusBar(profile: profile)
            BoardSign(title: "Guild Hall")

            heroCard

            BoardSectionHeader(title: "Today's quests") {
                Button(action: onOpenQuests) { HeaderLinkLabel(title: "Quest board") }
                    .buttonStyle(.plain)
            }
            ParchmentCard(padding: 16) {
                if let todaysQuest = store.quests[.daily] {
                    TodayRow(palette: .wax, systemImage: "dumbbell.fill",
                             title: todaysQuest.title,
                             detail: "Daily · \(todaysQuest.completedCount) of \(todaysQuest.objectives.count) done",
                             progress: todaysQuest.progress)
                    DashedDivider()
                }
                TodayRow(palette: .emerald, systemImage: "fork.knife",
                         title: "Ration duty",
                         detail: "Protein \(rations.eaten.protein) / \(rations.target.protein) g",
                         progress: rations.progress(\.protein))
                DashedDivider()
                TodayRow(palette: .sapphire, systemImage: "moon.zzz.fill",
                         title: "Rest at the inn",
                         detail: Recovery.summary(lastNight: store.lastNightSleepHours),
                         progress: store.lastNightSleepHours.map { $0 / Recovery.wellRestedHours })
            }

            Button {
                activeWorkout = ActiveWorkout(quest: store.quests[.daily].flatMap { $0.liftPlan.isEmpty ? nil : $0 })
            } label: {
                Label("Log a workout", systemImage: "dumbbell.fill")
            }
            .buttonStyle(.chunky(.wax))

            BoardSectionHeader(title: "Energy")
            EnergyCard(energy: profile.energy, maxEnergy: profile.maxEnergy)

            BoardSectionHeader(title: "Notices")
            if let exam = store.unlockedExam {
                ExamNoticeCard(exam: exam, rotation: 0.8) {
                    // TODO: launch Workout session in exam mode
                }
                .padding(.top, 8)
            } else {
                ParchmentCard(padding: 16) {
                    NoteHeading(title: "No notices", subtitle: "Keep training to unlock your next rank exam.")
                }
            }

            Button { showingSettings = true } label: {
                Label("Settings", systemImage: "gearshape.fill")
            }
            .buttonStyle(.chunky(.wood, fontSize: 18))
            .padding(.top, 12)
        }
        .workoutSessionCover($activeWorkout)
        .sheet(isPresented: $showingSettings) {
            SettingsSheet(onLogOut: {
                showingSettings = false
                onLogOut()
            })
        }
    }

    private var heroCard: some View {
        ParchmentCard {
            HStack(spacing: 16) {
                ClassEmblem(guildClass: profile.guildClass, size: 64)
                VStack(alignment: .leading, spacing: 2) {
                    KickerText("\(profile.rank)-rank \(profile.guildClass.name)")
                    Text("Welcome back, \(profile.displayName)")
                        .font(.alegreya(24, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
            }
            ParchmentProgressBar(progress: profile.levelProgress, tint: Theme.gold)
                .padding(.top, 14)
            Text("\(profile.xp.formatted()) / \(profile.nextLevelXP.formatted()) XP to level \(profile.level + 1)")
                .font(.alegreyaSans(15, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
                .padding(.top, 6)
        }
    }
}

/// One of today's quests: emblem, title, detail and optional progress.
private struct TodayRow: View {
    let palette: CartoonPalette
    let systemImage: String
    let title: String
    let detail: String
    let progress: Double?

    var body: some View {
        HStack(spacing: 14) {
            EmblemBadge(palette: palette, size: 42) {
                Image(systemName: systemImage)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.alegreyaSans(18, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(.alegreyaSans(15))
                    .foregroundStyle(Theme.inkSecondary)
                if let progress {
                    ParchmentProgressBar(progress: progress, height: 10)
                        .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

/// Energy pips plus how to refill them (real activity and sleep only).
private struct EnergyCard: View {
    let energy: Int
    let maxEnergy: Int

    var body: some View {
        ParchmentCard(padding: 16) {
            HStack(spacing: 8) {
                ForEach(0..<maxEnergy, id: \.self) { index in
                    let isFull = index < energy
                    Image(systemName: isFull ? "bolt.fill" : "bolt")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(isFull ? Theme.ink : Theme.outline.opacity(0.5))
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(isFull ? Theme.gold : Theme.checkboxFill))
                        .overlay(Circle().strokeBorder(Theme.outline, lineWidth: 2.5))
                }
                Spacer(minLength: 0)
            }
            Text("You start each day with \(EnergyRules.dailyStart) Energy. Each dungeon run uses 1. "
                 + "Logging a workout, cardio or \(Recovery.wellRestedHours.formatted())+ hours of sleep adds 1.")
                .font(.alegreyaSans(15))
                .foregroundStyle(Theme.inkSecondary)
                .padding(.top, 10)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Energy \(energy) of \(maxEnergy). Refill by logging a workout or sleeping 7 or more hours.")
    }
}

#Preview {
    NavigationStack {
        GuildHallView(onOpenQuests: {}, onLogOut: {})
    }
    .environment(GameStore.preview)
}
