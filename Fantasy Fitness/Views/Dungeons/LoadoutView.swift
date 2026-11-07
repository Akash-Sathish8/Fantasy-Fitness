//
//  LoadoutView.swift
//  Fantasy Fitness
//

import SwiftUI

/// Review the dungeon and your gear before spending Energy.
struct LoadoutView: View {
    let dungeon: Dungeon

    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var activeRun: ActiveRun?
    @State private var isStarting = false

    private var profile: PlayerProfile { store.player }

    private var canEnter: Bool { profile.energy >= dungeon.energyCost }

    var body: some View {
        BoardScreen(isRoot: false) {
            BoardSign(title: "Loadout")

            ParchmentCard {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        KickerText(dungeon.tier)
                        Text(dungeon.name)
                            .font(.alegreya(28, weight: .heavy))
                            .foregroundStyle(Theme.ink)
                    }
                    Spacer()
                    EmblemBadge(palette: .wax, size: 52) {
                        Image(systemName: dungeon.systemImage)
                    }
                }
                FlowLayout(spacing: 10) {
                    TagChip(label: "Boss: \(dungeon.boss)", systemImage: "crown.fill")
                    TagChip(label: "\(dungeon.energyCost) Energy", systemImage: "bolt.fill")
                }
                .padding(.top, 14)
            }

            BoardSectionHeader(title: "Your power")
            ParchmentCard(padding: 16) {
                // Combat numbers come from real training; gear only adds in-game bonuses.
                let fighter = Fighter(profile: profile)
                powerRow("Health", value: "\(fighter.maxHealth)", systemImage: "heart.fill",
                         tint: StatKind.vitality.palette.fill,
                         detail: "\(BattleRules.baseHealth) base + \(fighter.healthFromVitality) Vitality + \(fighter.healthFromEndurance) Endurance")
                powerRow("Attack", value: "\(fighter.attack)", systemImage: "bolt.fill",
                         tint: StatKind.strength.palette.fill,
                         detail: "\(BattleRules.baseAttack) base + \(fighter.attackFromStrength) Strength + \(fighter.attackFromGear) gear")
                powerRow("Defense", value: "\(fighter.defense)", systemImage: "shield.fill",
                         tint: Theme.sapphire, detail: "From equipped armor")
                powerRow("Critical zone", value: "\(Int((fighter.goldZone * 100).rounded()))%", systemImage: "scope",
                         tint: StatKind.agility.palette.fill, detail: "Gold on the timing meter, wider with Agility")
                powerRow(fighter.skill.name, value: "", systemImage: fighter.skill.systemImage,
                         tint: profile.guildClass.palette.fill,
                         detail: "\(profile.guildClass.name) skill: \(fighter.skill.summary.lowercased()), every \(BattleRules.skillCooldown) turns")
                Text("Health and Attack grow with your real training. Gear adds in\u{2011}game bonuses only.")
                    .font(.alegreyaSans(14))
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(.top, 8)
            }

            BoardSectionHeader(title: "Equipped") {
                NavigationLink(value: GearRoute.inventory) {
                    HeaderLinkLabel(title: "Change gear")
                }
                .buttonStyle(.plain)
            }
            ParchmentCard(padding: 16) {
                HStack(alignment: .top) {
                    ForEach(profile.equipped) { item in
                        ItemTile(item: item, size: 58)
                            .frame(maxWidth: .infinity)
                    }
                }
            }

            Button {
                Task {
                    isStarting = true
                    // The server checks rank and Energy and spends it before the fight starts.
                    if let runID = await store.startRun(in: dungeon) {
                        activeRun = ActiveRun(id: runID)
                    }
                    isStarting = false
                }
            } label: {
                Label("Enter dungeon", systemImage: "door.left.hand.open")
            }
            .buttonStyle(.chunky(.wax, minHeight: 58, fontSize: 21))
            .disabled(!canEnter || isStarting)
            .padding(.top, 8)

            if !canEnter {
                Text("Not enough Energy. Log a workout or get a good night's sleep to refill.")
                    .font(.alegreyaSans(15, weight: .medium))
                    .foregroundStyle(Theme.cream)
                    .multilineTextAlignment(.center)
            }
        }
        .fullScreenCover(item: $activeRun) { run in
            BattleView(dungeon: dungeon, runID: run.id) {
                activeRun = nil
                dismiss()
            }
            .holdsRewardReveals()
        }
    }

    /// One combat number with where it comes from, e.g. "Attack 25 · 10 base + 10 Strength + 5 gear".
    private func powerRow(_ title: String, value: String, systemImage: String, tint: Color,
                          detail: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.alegreyaSans(17, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(.alegreyaSans(13))
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Text(value)
                .font(.alegreyaSans(18, weight: .bold))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

private struct ActiveRun: Identifiable {
    let id: UUID
}

#Preview {
    NavigationStack {
        LoadoutView(dungeon: Dungeon.sampleMap[1])
    }
    .environment(GameStore.preview)
}
