//
//  Appearance.swift
//  Fantasy Fitness
//
//  How the player's character looks. Purely cosmetic: it never affects stats or exams.
//  Saved on profiles (body_type, skin_tone, hair_style, hair_color). The app owns the
//  list of options; the server only checks values are well formed, so a new hairstyle
//  ships with its art and no migration. Unknown values fall back to the defaults.
//

import SwiftUI

enum BodyType: String, CaseIterable, Identifiable {
    case narrow, broad

    var id: Self { self }

    var name: String { rawValue.capitalized }
}

enum HairStyle: String, CaseIterable, Identifiable {
    case short, long, braid, topknot, shaved

    var id: Self { self }

    var name: String {
        switch self {
        case .topknot: "Top knot"
        default: rawValue.capitalized
        }
    }
}

struct Appearance: Hashable {
    var bodyType: BodyType = .narrow
    /// Index into `Appearance.skinTones`.
    var skinTone = 2
    var hairStyle: HairStyle = .short
    /// Index into `Appearance.hairColors`.
    var hairColor = 1

    var skinColor: Color { Self.skinTones[Self.clamped(skinTone, to: Self.skinTones)].color }
    var hairTint: Color { Self.hairColors[Self.clamped(hairColor, to: Self.hairColors)].color }

    struct Swatch: Identifiable {
        let id: Int
        let name: String
        let color: Color
    }

    static let skinTones: [Swatch] = [
        (0xFBE3CF, "Porcelain"), (0xF3CDA8, "Fair"), (0xE2B086, "Sand"), (0xC98E62, "Tan"),
        (0xA86F46, "Bronze"), (0x8A5434, "Umber"), (0x6B3E25, "Cocoa"), (0x4A2A18, "Ebony"),
    ].enumerated().map { Swatch(id: $0.offset, name: $0.element.1, color: Color(hex: $0.element.0)) }

    static let hairColors: [Swatch] = [
        (0x2A1E1A, "Black"), (0x4E3020, "Dark brown"), (0x7A4A28, "Brown"), (0x9C3E1E, "Auburn"),
        (0xD9AE5B, "Blond"), (0xB8B2AA, "Silver"), (0x4F7A3A, "Moss green"), (0x3A5A9E, "Sapphire"),
    ].enumerated().map { Swatch(id: $0.offset, name: $0.element.1, color: Color(hex: $0.element.0)) }

    private static func clamped(_ index: Int, to swatches: [Swatch]) -> Int {
        swatches.indices.contains(index) ? index : 0
    }
}

extension Appearance {
    /// Reads the profile columns, using the default for anything missing or unknown.
    init(bodyType: String?, skinTone: Int?, hairStyle: String?, hairColor: Int?) {
        let defaults = Appearance()
        self.bodyType = bodyType.flatMap(BodyType.init) ?? defaults.bodyType
        self.skinTone = skinTone.flatMap { Self.skinTones.indices.contains($0) ? $0 : nil } ?? defaults.skinTone
        self.hairStyle = hairStyle.flatMap(HairStyle.init) ?? defaults.hairStyle
        self.hairColor = hairColor.flatMap { Self.hairColors.indices.contains($0) ? $0 : nil } ?? defaults.hairColor
    }
}

extension [Item] {
    /// This gear with `item` swapped into its slot, for "try it on" previews.
    func wearing(_ item: Item) -> [Item] {
        filter { $0.slot != item.slot } + [item]
    }
}
