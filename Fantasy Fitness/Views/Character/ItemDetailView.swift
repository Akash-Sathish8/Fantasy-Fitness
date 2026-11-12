//
//  ItemDetailView.swift
//  Fantasy Fitness
//

import SwiftUI

/// Item detail with an equip / compare against what's in the same slot.
struct ItemDetailView: View {
    let item: Item

    @Environment(GameStore.self) private var store
    @State private var isSaving = false

    private var isEquipped: Bool { store.equippedIDs.contains(item.id) }

    private var currentInSlot: Item? {
        store.player.equipped.first { $0.slot == item.slot && $0 != item }
    }

    var body: some View {
        BoardScreen(isRoot: false) {
            ParchmentCard {
                HStack(alignment: .top, spacing: 16) {
                    ItemTile(item: item, size: 92, showsName: false)
                    VStack(alignment: .leading, spacing: 6) {
                        KickerText("\(item.slot.name) slot")
                        Text(item.name)
                            .font(.alegreya(26, weight: .heavy))
                            .foregroundStyle(Theme.ink)
                        RarityChip(rarity: item.rarity)
                    }
                }

                Text("“\(item.flavor)”")
                    .font(.alegreyaSans(17).italic())
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(.top, 16)

                DashedDivider().padding(.vertical, 16)

                Text("Effect")
                    .font(.alegreya(18))
                    .foregroundStyle(Theme.ink)
                TagChip(label: item.effect, systemImage: "sparkles")
                    .padding(.top, 8)

                Text(isEquipped ? "On your character" : "Try it on")
                    .font(.alegreya(18))
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 18)
                CharacterView(appearance: store.player.appearance, equipped: store.player.equipped.wearing(item))
                    .frame(height: 190)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.noteParchment))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.outline, lineWidth: 2))
                    .padding(.top, 8)

                if let current = currentInSlot, !isEquipped {
                    Text("Compared with equipped")
                        .font(.alegreya(18))
                        .foregroundStyle(Theme.ink)
                        .padding(.top, 18)
                    HStack(spacing: 12) {
                        ItemTile(item: current, size: 48, showsName: false)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(current.name)
                                .font(.alegreyaSans(17, weight: .bold))
                                .foregroundStyle(Theme.ink)
                            Text(current.effect)
                                .font(.alegreyaSans(15))
                                .foregroundStyle(Theme.inkSecondary)
                        }
                    }
                    .padding(.top, 8)
                }

                Button {
                    Task {
                        isSaving = true
                        if isEquipped { await store.unequip(item) } else { await store.equip(item) }
                        isSaving = false
                    }
                } label: {
                    Label(isEquipped ? "Unequip" : "Equip", systemImage: isEquipped ? "xmark" : "shield.lefthalf.filled")
                }
                .buttonStyle(.chunky(isEquipped ? .wood : .emerald))
                .disabled(isSaving)
                .padding(.top, 22)

                Text("Gear never counts toward rank exams. Exams use your real lifts.")
                    .font(.alegreyaSans(14))
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(.top, 12)
            }
        }
    }
}

#Preview {
    NavigationStack {
        ItemDetailView(item: .runeAxe)
    }
    .environment(GameStore.preview)
}
