//
//  Item.swift
//  Fantasy Fitness
//

import Foundation

enum Rarity: Int, CaseIterable, Comparable {
    case common, uncommon, rare, epic, legendary

    var name: String { String(describing: self).capitalized }

    static func < (lhs: Rarity, rhs: Rarity) -> Bool { lhs.rawValue < rhs.rawValue }
}

enum ItemSlot: String, CaseIterable {
    case head, chest, weapon, trinket

    var name: String { rawValue.capitalized }
}

/// Gear boosts in-game combat, XP multipliers or looks only. It never counts toward exams.
struct Item: Identifiable, Hashable {
    let id: String
    let name: String
    let slot: ItemSlot
    let rarity: Rarity
    /// In-game effect, e.g. "+4 dungeon attack". Never a real-world performance claim.
    let effect: String
    let flavor: String
    /// Dungeon combat bonuses, matching `effect` (items.attack_bonus / defense_bonus).
    var attackBonus = 0
    var defenseBonus = 0
}

// MARK: - Sample data (previews and offline demo mode)

extension Item {
    static let ironHelm = Item(id: "iron-helm", name: "Iron Helm", slot: .head, rarity: .common,
                               effect: "+2 dungeon defense", flavor: "Dented, but honest.", defenseBonus: 2)
    static let leatherJerkin = Item(id: "leather-jerkin", name: "Leather Jerkin", slot: .chest, rarity: .uncommon,
                                    effect: "+3 dungeon defense", flavor: "Smells faintly of the forge.",
                                    defenseBonus: 3)
    static let oakLongsword = Item(id: "oak-longsword", name: "Oak Longsword", slot: .weapon, rarity: .rare,
                                   effect: "+5 dungeon attack", flavor: "Earned on bench day.", attackBonus: 5)
    static let emberCharm = Item(id: "ember-charm", name: "Ember Charm", slot: .trinket, rarity: .epic,
                                 effect: "+5% XP from Strength quests", flavor: "Warm to the touch after a PR.")
    static let mossHood = Item(id: "moss-hood", name: "Moss Hood", slot: .head, rarity: .uncommon,
                               effect: "+3 dungeon defense", flavor: "Dropped in the Mossy Crypt.", defenseBonus: 3)
    static let gildedPlate = Item(id: "gilded-plate", name: "Gilded Plate", slot: .chest, rarity: .legendary,
                                  effect: "Cosmetic: golden armor glow", flavor: "Worn by S-rank legends.")
    static let runeAxe = Item(id: "rune-axe", name: "Rune Axe", slot: .weapon, rarity: .epic,
                              effect: "+8 dungeon attack", flavor: "Hums before a heavy set.", attackBonus: 8)
    static let restfulAmulet = Item(id: "restful-amulet", name: "Restful Amulet", slot: .trinket, rarity: .rare,
                                    effect: "+10% XP from Well-Rested days", flavor: "Glows after 8 hours of sleep.")

    static let sampleInventory: [Item] = [
        .ironHelm, .leatherJerkin, .oakLongsword, .emberCharm,
        .mossHood, .gildedPlate, .runeAxe, .restfulAmulet,
    ]
}
