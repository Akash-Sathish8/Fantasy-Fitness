//
//  LootRevealView.swift
//  Fantasy Fitness
//

import SwiftUI

/// Rewards granted by the server for a cleared quest or dungeon.
/// The client only displays these; it never decides them.
struct LootDrop {
    let title: String
    let chestRarity: Rarity
    let xp: Int
    let items: [Item]
}

extension LootDrop {
    static let sampleDungeon = LootDrop(title: "Dungeon cleared", chestRarity: .rare, xp: 80,
                                        items: [.mossHood, .restfulAmulet])
}

/// Shared loot reveal, presented after Quest complete and after a Battle.
struct LootRevealView: View {
    let loot: LootDrop
    let onCollect: () -> Void

    @State private var isOpen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text(loot.title)
                .font(.pirata(46))
                .foregroundStyle(Theme.gold)
                .shadow(color: Theme.darkestWood, radius: 0, x: 0, y: 3)
                .accessibilityAddTraits(.isHeader)

            chest

            if isOpen {
                ParchmentCard {
                    HStack {
                        NoteHeading(title: "Spoils")
                        Spacer()
                        TagChip(label: "+\(loot.xp) XP", systemImage: "star.fill")
                    }
                    HStack(spacing: 18) {
                        ForEach(loot.items) { item in
                            VStack(spacing: 6) {
                                ItemTile(item: item, size: 70)
                                RarityChip(rarity: item.rarity)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 16)
                }
                .transition(.scale(scale: 0.8).combined(with: .opacity))

                Button("Collect", action: onCollect)
                    .buttonStyle(.chunky(.emerald))
            } else {
                Button("Open chest") {
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.5, bounce: 0.35)) { isOpen = true }
                }
                .buttonStyle(.chunky(.gold))
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WoodBackground())
    }

    private var chest: some View {
        let palette = loot.chestRarity.palette
        return ZStack {
            Circle()
                .fill(RadialGradient(colors: [palette.fill.opacity(0.7), .clear],
                                     center: .center, startRadius: 10, endRadius: 120))
                .frame(width: 240, height: 240)
                .scaleEffect(isOpen ? 1.15 : 0.9)
            EmblemBadge(palette: palette, size: 110, shadowOffset: 6) {
                Image(systemName: isOpen ? "shippingbox.and.arrow.backward.fill" : "shippingbox.fill")
            }
            .rotationEffect(.degrees(isOpen ? 0 : -4))
        }
        .frame(height: isOpen ? 170 : 240)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(loot.chestRarity.name) chest, \(isOpen ? "opened" : "closed")")
    }
}

extension View {
    /// Marks a full-screen flow, which SwiftUI can't present a reward reveal on top of.
    func holdsRewardReveals() -> some View {
        modifier(HoldsRewardReveals())
    }
}

private struct HoldsRewardReveals: ViewModifier {
    @Environment(GameStore.self) private var store

    func body(content: Content) -> some View {
        content
            .onAppear { store.isInFullScreenFlow = true }
            .onDisappear { store.isInFullScreenFlow = false }
    }
}

#Preview {
    LootRevealView(loot: .sampleDungeon, onCollect: {})
}
