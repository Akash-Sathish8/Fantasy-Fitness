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
                // Combat stats come from real training; gear only adds in-game bonuses.
                ForEach([StatKind.strength, .endurance, .agility]) { stat in
                    HStack(spacing: 10) {
                        Image(systemName: stat.systemImage)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(stat.palette.fill)
                            .frame(width: 26)
                        Text(stat.name)
                            .font(.alegreyaSans(17, weight: .bold))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Text("\(profile.stats[stat] ?? 0)")
                            .font(.alegreyaSans(18, weight: .bold))
                            .foregroundStyle(Theme.ink)
                    }
                    .padding(.vertical, 6)
                }
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
