//
//  CharacterView.swift
//  Fantasy Fitness
//
//  The player's character, drawn as a stack of same-size transparent layers (a
//  "paper doll"): body, outfit, face, hair and one layer per equipped item. Each
//  layer uses the artists' image from Assets.xcassets/Character when it exists and a
//  placeholder drawing when it doesn't, so art can be added one file at a time.
//  Art rules and file names: docs/character-art.md.
//

import SwiftUI
import UIKit

/// The full character on a square canvas. Transparent; put it on whatever backdrop.
struct CharacterView: View {
    let appearance: Appearance
    let equipped: [Item]

    var body: some View {
        ZStack {
            ForEach(CharacterArt.layers(for: appearance, equipped: equipped)) { layer in
                CharacterLayerView(layer: layer)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(CharacterArt.description(of: appearance, equipped: equipped))
    }
}

/// Head and shoulders in a round badge, for small spots like the battle card.
struct CharacterPortrait: View {
    let appearance: Appearance
    let equipped: [Item]
    var size: CGFloat = 72
    var palette: CartoonPalette = .wood
    var shadowOffset: CGFloat = 4

    var body: some View {
        CharacterView(appearance: appearance, equipped: equipped)
            .frame(width: size * 1.9, height: size * 1.9)
            .offset(y: size * 0.32)
            .frame(width: size, height: size)
            .clipShape(Circle())
            .background(CartoonSurface(shape: Circle(), fill: palette.fill, outline: palette.border,
                                       lineWidth: 3, shadowOffset: shadowOffset))
            .overlay(Circle().strokeBorder(palette.border, lineWidth: 3))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(CharacterArt.description(of: appearance, equipped: equipped))
    }
}

/// One layer of the character.
struct CharacterLayer: Identifiable {
    /// Stable per role ("body", "item.head"), so changing a look redraws a layer in
    /// place instead of fading one layer out and another in.
    let id: String
    /// Asset names to try, most specific first (e.g. a per-body-type version of an item).
    let assetNames: [String]
    /// Multiplied over the art, which is drawn in light grays (skin and hair).
    var tint: Color? = nil
    /// Drawn on the 100 × 100 template canvas when there's no art yet.
    var placeholder: CharacterPlaceholder.Drawing? = nil
}

private struct CharacterLayerView: View {
    let layer: CharacterLayer

    var body: some View {
        if let name = CharacterArt.firstAvailable(layer.assetNames) {
            Image(name)
                .resizable()
                .interpolation(CharacterArt.isPixelArt ? .none : .high)
                .scaledToFit()
                .colorMultiply(layer.tint ?? .white)
        } else if let placeholder = layer.placeholder {
            Canvas { context, size in
                let scale = min(size.width, size.height) / CharacterPlaceholder.canvasSize
                context.translateBy(x: (size.width - scale * CharacterPlaceholder.canvasSize) / 2,
                                    y: (size.height - scale * CharacterPlaceholder.canvasSize) / 2)
                context.scaleBy(x: scale, y: scale)
                placeholder(&context)
            }
        }
    }
}

// MARK: - Layer manifest

/// Which layers make up a character, in what order, and what each one is called.
enum CharacterArt {
    /// Set to true if the art is pixel art, so it scales without blurring.
    static let isPixelArt = false

    /// Head items that leave the hair visible (crowns, circlets). Every other head item
    /// covers it, so hairstyles don't poke through helmets and hoods.
    static let headItemsShowingHair: Set<String> = ["crown-of-iron"]

    /// Back to front. Every layer is the full canvas, so they line up with no offsets.
    static func layers(for appearance: Appearance, equipped: [Item]) -> [CharacterLayer] {
        let build = appearance.bodyType.rawValue
        let hair = appearance.hairStyle.rawValue
        let item = { (slot: ItemSlot) in equipped.first { $0.slot == slot } }
        let head = item(.head), chest = item(.chest), weapon = item(.weapon), trinket = item(.trinket)
        let showsHair = head.map { headItemsShowingHair.contains($0.id) } ?? true

        func itemNames(_ item: Item, suffix: String = "") -> [String] {
            ["item_\(item.id)_\(build)\(suffix)", "item_\(item.id)\(suffix)"]
        }

        var layers: [CharacterLayer] = []
        if showsHair {
            layers.append(CharacterLayer(id: "hair.back", assetNames: ["hair_\(hair)_back"], tint: appearance.hairTint,
                                         placeholder: CharacterPlaceholder.hairBack(appearance)))
        }
        // Parts of gear that sit behind the body: a cape, a sheathed blade, the back of a hood.
        for gear in [weapon, chest, head].compactMap({ $0 }) {
            layers.append(CharacterLayer(id: "item.\(gear.slot.rawValue).back",
                                         assetNames: itemNames(gear, suffix: "_back")))
        }
        layers.append(CharacterLayer(id: "body", assetNames: ["body_\(build)"], tint: appearance.skinColor,
                                     placeholder: CharacterPlaceholder.body(appearance)))
        layers.append(CharacterLayer(id: "outfit", assetNames: ["outfit_\(build)"],
                                     placeholder: CharacterPlaceholder.outfit(appearance)))
        layers.append(CharacterLayer(id: "face", assetNames: ["face"], placeholder: CharacterPlaceholder.face))
        if let chest {
            layers.append(CharacterLayer(id: "item.chest", assetNames: itemNames(chest),
                                         placeholder: CharacterPlaceholder.chest(chest, appearance)))
        }
        if let trinket {
            layers.append(CharacterLayer(id: "item.trinket", assetNames: itemNames(trinket),
                                         placeholder: CharacterPlaceholder.trinket(trinket)))
        }
        if showsHair {
            layers.append(CharacterLayer(id: "hair", assetNames: ["hair_\(hair)"], tint: appearance.hairTint,
                                         placeholder: CharacterPlaceholder.hairFront(appearance)))
        }
        if let head {
            layers.append(CharacterLayer(id: "item.head", assetNames: itemNames(head),
                                         placeholder: CharacterPlaceholder.head(head)))
        }
        if let weapon {
            layers.append(CharacterLayer(id: "item.weapon", assetNames: itemNames(weapon),
                                         placeholder: CharacterPlaceholder.weapon(weapon, appearance)))
        }
        return layers
    }

    /// "Your character: broad frame, short brown hair, wearing Iron Helm and Oak Longsword."
    static func description(of appearance: Appearance, equipped: [Item]) -> String {
        let hairColor = Appearance.hairColors.first { $0.id == appearance.hairColor }?.name.lowercased() ?? ""
        let hair = appearance.hairStyle == .shaved
            ? "shaved head"
            : "\(appearance.hairStyle.name.lowercased()) \(hairColor) hair"
        var text = "Your character: \(appearance.bodyType.name.lowercased()) frame, \(hair)"
        if !equipped.isEmpty {
            text += ", wearing " + equipped.map(\.name).formatted(.list(type: .and))
        }
        return text
    }

    /// The first of these names that's in the asset catalog.
    static func firstAvailable(_ names: [String]) -> String? {
        names.first { name in
            if let known = availability[name] { return known }
            let exists = UIImage(named: name) != nil
            availability[name] = exists
            return exists
        }
    }

    private static var availability: [String: Bool] = [:]
}

// MARK: - Previews

#Preview("Character") {
    ScrollView {
        VStack(spacing: 24) {
            CharacterView(appearance: Appearance(), equipped: PlayerProfile.sample.equipped)
                .frame(height: 300)
            HStack {
                CharacterView(appearance: Appearance(bodyType: .broad, skinTone: 5, hairStyle: .long, hairColor: 4),
                              equipped: [.gildedPlate, .runeAxe, .restfulAmulet])
                CharacterView(appearance: Appearance(skinTone: 0, hairStyle: .topknot, hairColor: 7), equipped: [])
            }
            .frame(height: 180)
            CharacterPortrait(appearance: Appearance(hairStyle: .braid, hairColor: 3),
                              equipped: [.mossHood, .leatherJerkin])
        }
        .padding()
    }
    .background(Theme.parchment)
}

/// The template artists draw over: the base character on the 100 × 100 grid.
#Preview("Art template") {
    ZStack {
        Canvas { context, size in
            let step = size.width / 10
            for i in 0...10 {
                let p = CGFloat(i) * step
                var line = Path()
                line.move(to: CGPoint(x: p, y: 0)); line.addLine(to: CGPoint(x: p, y: size.height))
                line.move(to: CGPoint(x: 0, y: p)); line.addLine(to: CGPoint(x: size.width, y: p))
                context.stroke(line, with: .color(.blue.opacity(i == 5 ? 0.5 : 0.18)), lineWidth: 1)
            }
        }
        CharacterView(appearance: Appearance(hairStyle: .shaved), equipped: [])
    }
    .aspectRatio(1, contentMode: .fit)
    .background(.white)
    .padding()
}
