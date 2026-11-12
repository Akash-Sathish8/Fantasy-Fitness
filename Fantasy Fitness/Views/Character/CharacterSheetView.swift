//
//  CharacterSheetView.swift
//  Fantasy Fitness
//

import SwiftUI

/// Character sheet → Inventory → Item detail → Equip/compare.
struct CharacterSheetView: View {
    @Environment(GameStore.self) private var store
    @State private var isCustomizing = false

    private var profile: PlayerProfile { store.player }

    var body: some View {
        BoardScreen {
            BoardSign(title: "Character")

            ParchmentCard(padding: 16) {
                CharacterView(appearance: profile.appearance, equipped: profile.equipped)
                    .frame(height: 260)
                    .frame(maxWidth: .infinity)
                    .background(alignment: .bottom) {
                        Ellipse().fill(Theme.outline.opacity(0.15)).frame(width: 130, height: 18).offset(y: -4)
                    }
                Button { isCustomizing = true } label: {
                    Label("Customize", systemImage: "paintbrush.fill")
                }
                .buttonStyle(.chunky(.wood, minHeight: 44, fullWidth: false, fontSize: 17))
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
            }

            ParchmentScroll {
                HStack(spacing: 16) {
                    ClassEmblem(guildClass: profile.guildClass, size: 68)
                    VStack(alignment: .leading, spacing: 2) {
                        KickerText("\(profile.rank)-rank \(profile.guildClass.name) · Level \(profile.level)")
                        Text(profile.displayName)
                            .font(.alegreya(30, weight: .heavy))
                            .foregroundStyle(Theme.ink)
                    }
                }
                ParchmentProgressBar(progress: profile.levelProgress, tint: Theme.gold)
                    .padding(.top, 14)
                Text("Level comes from total XP. Stats rise only when your real performance does.")
                    .font(.alegreyaSans(15))
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(.top, 8)

                Text("Stats")
                    .font(.alegreya(19))
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 18)
                VStack(spacing: 0) {
                    ForEach(StatKind.allCases) { stat in
                        StatRow(stat: stat, value: profile.stats[stat] ?? 0)
                        DashedDivider()
                    }
                }
            }

            BoardSectionHeader(title: "Equipped") {
                NavigationLink(value: GearRoute.inventory) {
                    HeaderLinkLabel(title: "Inventory")
                }
                .buttonStyle(.plain)
            }
            ParchmentCard(padding: 16) {
                HStack(alignment: .top) {
                    ForEach(profile.equipped) { item in
                        NavigationLink(value: GearRoute.item(item)) {
                            ItemTile(item: item, size: 62)
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                    }
                }
                Text("Gear boosts dungeon combat and XP. It never counts toward rank exams.")
                    .font(.alegreyaSans(14))
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(.top, 10)
            }
        }
        .gearDestinations()
        .sheet(isPresented: $isCustomizing) { AppearanceEditorView() }
    }
}

private struct StatRow: View {
    let stat: StatKind
    let value: Int
    /// Display ceiling for the bar; stats have no hard cap.
    private let barMax = 100.0

    var body: some View {
        HStack(spacing: 12) {
            EmblemBadge(palette: stat.palette, size: 38, shadowOffset: 2) {
                Image(systemName: stat.systemImage)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(stat.name)
                        .font(.alegreyaSans(17, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Text("\(value)")
                        .font(.alegreyaSans(18, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .monospacedDigit()
                }
                ParchmentProgressBar(progress: Double(value) / barMax, height: 10, tint: stat.palette.fill)
                Text(stat.source)
                    .font(.alegreyaSans(13))
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(stat.name) \(value). From \(stat.source.lowercased())")
    }
}

#Preview {
    NavigationStack {
        CharacterSheetView()
    }
    .environment(GameStore.preview)
}
