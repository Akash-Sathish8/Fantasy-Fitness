//
//  CharacterPlaceholder.swift
//  Fantasy Fitness
//
//  Stand-in drawings for character layers that don't have art yet. They're drawn on
//  a 100 × 100 grid in the same pose and position the real art must use, so the
//  placeholders double as the template (see the "Art template" preview).
//
//  Key points on the grid (x across, y down):
//    head: circle centered (50, 30), radius 13      neck: y 41–47
//    torso: y 45–72, x 37–63 (narrow) or 33–67 (broad)
//    hands: (32.5, 73) and (67.5, 73) narrow; (28.5, 73) and (71.5, 73) broad
//    feet: bottom at y 96. Weapons are held in the hand on the viewer's right.
//

import SwiftUI

enum CharacterPlaceholder {
    typealias Drawing = (inout GraphicsContext) -> Void

    static let canvasSize: CGFloat = 100

    private static let line: CGFloat = 1.2
    private static let steel = Color(hex: 0xD9D6CF)
    private static let leather = Color(hex: 0x8A5A32)
    private static let tunic = Color(hex: 0xE8D3A6)
    private static let trousers = Color(hex: 0x5A4632)

    // MARK: Body

    private struct Frame {
        let torsoLeft: CGFloat
        let torsoRight: CGFloat
        let leftArm: CGFloat   // arm's left edge
        let rightArm: CGFloat
        var leftHand: CGPoint { CGPoint(x: leftArm + 3.5, y: 73) }
        var rightHand: CGPoint { CGPoint(x: rightArm + 3.5, y: 73) }

        init(_ bodyType: BodyType) {
            switch bodyType {
            case .narrow: (torsoLeft, torsoRight, leftArm, rightArm) = (37, 63, 29, 64)
            case .broad: (torsoLeft, torsoRight, leftArm, rightArm) = (33, 67, 25, 68)
            }
        }

        var torso: Path {
            Path(roundedRect: CGRect(x: torsoLeft, y: 45, width: torsoRight - torsoLeft, height: 27), cornerRadius: 6)
        }
    }

    static func body(_ appearance: Appearance) -> Drawing {
        let frame = Frame(appearance.bodyType)
        let skin = appearance.skinColor
        return { context in
            for x in [40.0, 51.0] {
                context.cartoon(Path(roundedRect: CGRect(x: x, y: 68, width: 9, height: 26), cornerRadius: 3), skin)
            }
            for x in [frame.leftArm, frame.rightArm] {
                context.cartoon(Path(roundedRect: CGRect(x: x, y: 47, width: 7, height: 25), cornerRadius: 3.5), skin)
            }
            context.cartoon(frame.torso, skin)
            for hand in [frame.leftHand, frame.rightHand] {
                context.cartoon(Path(ellipseIn: CGRect(x: hand.x - 4, y: hand.y - 4, width: 8, height: 8)), skin)
            }
            context.cartoon(Path(CGRect(x: 46, y: 40, width: 8, height: 7)), skin)
            for x in [37.0, 63.0] {
                context.cartoon(Path(ellipseIn: CGRect(x: x - 3, y: 28, width: 6, height: 7)), skin)
            }
            context.cartoon(Path(ellipseIn: CGRect(x: 37, y: 17, width: 26, height: 26)), skin)
        }
    }

    /// The plain clothes everyone starts in: tunic, belt, trousers and boots.
    static func outfit(_ appearance: Appearance) -> Drawing {
        let frame = Frame(appearance.bodyType)
        return { context in
            for x in [39.5, 50.5] {
                context.cartoon(Path(roundedRect: CGRect(x: x, y: 66, width: 10, height: 22), cornerRadius: 3), trousers)
                context.cartoon(Path(roundedRect: CGRect(x: x - 1, y: 86, width: 12, height: 10), cornerRadius: 3),
                                Theme.darkWood)
            }
            for x in [frame.leftArm, frame.rightArm] {
                context.cartoon(Path(roundedRect: CGRect(x: x - 0.5, y: 46.5, width: 8, height: 9), cornerRadius: 3.5), tunic)
            }
            context.cartoon(frame.torso, tunic)
            context.cartoon(Path(CGRect(x: frame.torsoLeft, y: 63, width: frame.torsoRight - frame.torsoLeft, height: 3.5)),
                            leather)
            var neckline = Path()
            neckline.move(to: CGPoint(x: 45, y: 45.5))
            neckline.addQuadCurve(to: CGPoint(x: 55, y: 45.5), control: CGPoint(x: 50, y: 51))
            context.stroke(neckline, with: .color(Theme.outline), lineWidth: line)
        }
    }

    static let face: Drawing = { context in
        for x in [44.5, 55.5] {
            context.fill(Path(ellipseIn: CGRect(x: x - 1.3, y: 28.5, width: 2.6, height: 3.4)), with: .color(Theme.ink))
        }
        for x in [41.0, 59.0] {
            context.fill(Path(ellipseIn: CGRect(x: x - 2, y: 33, width: 4, height: 2.4)),
                         with: .color(Theme.waxRed.opacity(0.25)))
        }
        var mouth = Path()
        mouth.move(to: CGPoint(x: 47.5, y: 36.5))
        mouth.addQuadCurve(to: CGPoint(x: 52.5, y: 36.5), control: CGPoint(x: 50, y: 38.8))
        context.stroke(mouth, with: .color(Theme.ink), style: StrokeStyle(lineWidth: 1, lineCap: .round))
    }

    // MARK: Hair

    /// Hair behind the head and shoulders (long styles only).
    static func hairBack(_ appearance: Appearance) -> Drawing? {
        guard appearance.hairStyle == .long else { return nil }
        let color = appearance.hairTint
        return { context in
            context.cartoon(Path(roundedRect: CGRect(x: 34, y: 20, width: 32, height: 36), cornerRadius: 11), color)
        }
    }

    static func hairFront(_ appearance: Appearance) -> Drawing? {
        let color = appearance.hairTint
        switch appearance.hairStyle {
        case .shaved:
            return nil
        case .short:
            return { $0.cartoon(cap(), color) }
        case .long:
            return { context in
                var locks = Path()
                locks.move(to: CGPoint(x: 35.5, y: 46))
                locks.addLine(to: CGPoint(x: 35.5, y: 28))
                locks.addQuadCurve(to: CGPoint(x: 50, y: 14.5), control: CGPoint(x: 36, y: 14.5))
                locks.addQuadCurve(to: CGPoint(x: 64.5, y: 28), control: CGPoint(x: 64, y: 14.5))
                locks.addLine(to: CGPoint(x: 64.5, y: 46))
                locks.addLine(to: CGPoint(x: 60.5, y: 46))
                locks.addLine(to: CGPoint(x: 60.5, y: 27))
                locks.addQuadCurve(to: CGPoint(x: 39.5, y: 27), control: CGPoint(x: 50, y: 22))
                locks.addLine(to: CGPoint(x: 39.5, y: 46))
                locks.closeSubpath()
                context.cartoon(locks, color)
            }
        case .braid:
            return { context in
                context.cartoon(cap(), color)
                for (i, y) in [40.0, 46.0, 52.0, 58.0].enumerated() {
                    let x = 61.5 + Double(i) * 1.2
                    context.cartoon(Path(ellipseIn: CGRect(x: x - 3, y: y - 3.5, width: 6, height: 7)), color)
                }
                context.cartoon(Path(roundedRect: CGRect(x: 63, y: 61, width: 3, height: 3), cornerRadius: 1), Theme.waxRed)
            }
        case .topknot:
            return { context in
                context.cartoon(Path(ellipseIn: CGRect(x: 44.5, y: 8, width: 11, height: 10)), color)
                context.cartoon(cap(), color)
            }
        }
    }

    /// Hair covering the top of the head, with a fringe.
    private static func cap() -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 36.5, y: 31))
        path.addQuadCurve(to: CGPoint(x: 50, y: 14.5), control: CGPoint(x: 36, y: 14.5))
        path.addQuadCurve(to: CGPoint(x: 63.5, y: 31), control: CGPoint(x: 64, y: 14.5))
        path.addQuadCurve(to: CGPoint(x: 57, y: 24), control: CGPoint(x: 61, y: 24))
        path.addQuadCurve(to: CGPoint(x: 43, y: 24), control: CGPoint(x: 50, y: 27))
        path.addQuadCurve(to: CGPoint(x: 36.5, y: 31), control: CGPoint(x: 39, y: 24))
        path.closeSubpath()
        return path
    }

    // MARK: Gear

    static func head(_ item: Item) -> Drawing {
        let palette = item.rarity.palette
        return { context in
            if item.id.contains("crown") {
                var crown = Path()
                crown.addLines([CGPoint(x: 39, y: 22), CGPoint(x: 39, y: 13), CGPoint(x: 44.5, y: 18),
                                CGPoint(x: 50, y: 10), CGPoint(x: 55.5, y: 18), CGPoint(x: 61, y: 13),
                                CGPoint(x: 61, y: 22)])
                crown.closeSubpath()
                context.cartoon(crown, steel)
                context.cartoon(Path(ellipseIn: CGRect(x: 48.3, y: 16.5, width: 3.4, height: 3.4)), palette.fill)
            } else if item.id.contains("hood") || item.id.contains("cowl") {
                var hood = Path()
                hood.move(to: CGPoint(x: 33, y: 48))
                hood.addLine(to: CGPoint(x: 33.5, y: 28))
                hood.addQuadCurve(to: CGPoint(x: 50, y: 12), control: CGPoint(x: 34, y: 12))
                hood.addQuadCurve(to: CGPoint(x: 66.5, y: 28), control: CGPoint(x: 66, y: 12))
                hood.addLine(to: CGPoint(x: 67, y: 48))
                hood.closeSubpath()
                hood.addEllipse(in: CGRect(x: 39, y: 21, width: 22, height: 23))
                context.fill(hood, with: .color(palette.fill), style: FillStyle(eoFill: true))
                context.stroke(hood, with: .color(Theme.outline), style: StrokeStyle(lineWidth: line, lineJoin: .round))
            } else {
                var dome = Path()
                dome.move(to: CGPoint(x: 36, y: 27))
                dome.addQuadCurve(to: CGPoint(x: 50, y: 12), control: CGPoint(x: 35.5, y: 12))
                dome.addQuadCurve(to: CGPoint(x: 64, y: 27), control: CGPoint(x: 64.5, y: 12))
                dome.closeSubpath()
                context.cartoon(dome, steel)
                context.cartoon(Path(roundedRect: CGRect(x: 34.5, y: 23.5, width: 31, height: 4), cornerRadius: 1.5),
                                palette.fill)
                context.cartoon(Path(roundedRect: CGRect(x: 48.8, y: 25, width: 2.4, height: 8), cornerRadius: 1), steel)
            }
        }
    }

    static func chest(_ item: Item, _ appearance: Appearance) -> Drawing {
        let frame = Frame(appearance.bodyType)
        let palette = item.rarity.palette
        let isLight = item.id.contains("jerkin") || item.id.contains("vest")
        let glows = item.rarity == .legendary
        return { context in
            if glows { context.addFilter(.shadow(color: Theme.gold, radius: 3)) }
            let body = CGRect(x: frame.torsoLeft - 1, y: 44.5, width: frame.torsoRight - frame.torsoLeft + 2, height: 19)
            context.cartoon(Path(roundedRect: body, cornerRadius: 6), isLight ? leather : palette.fill)
            if !isLight {
                for x in [frame.leftArm + 3.5, frame.rightArm + 3.5] {
                    context.cartoon(Path(ellipseIn: CGRect(x: x - 5.5, y: 44, width: 11, height: 9)), palette.fill)
                }
            }
            var seam = Path()
            seam.move(to: CGPoint(x: 50, y: 48))
            seam.addLine(to: CGPoint(x: 50, y: 62))
            context.stroke(seam, with: .color(isLight ? palette.fill : palette.border), lineWidth: line)
        }
    }

    static func trinket(_ item: Item) -> Drawing {
        let palette = item.rarity.palette
        return { context in
            var cord = Path()
            cord.move(to: CGPoint(x: 45, y: 45))
            cord.addQuadCurve(to: CGPoint(x: 55, y: 45), control: CGPoint(x: 50, y: 58))
            context.stroke(cord, with: .color(Theme.outline), lineWidth: 0.8)
            context.cartoon(Path(ellipseIn: CGRect(x: 47.2, y: 49.5, width: 5.6, height: 5.6)), palette.fill)
        }
    }

    static func weapon(_ item: Item, _ appearance: Appearance) -> Drawing {
        let hand = Frame(appearance.bodyType).rightHand
        let (x, y) = (hand.x, hand.y)
        let accent = item.rarity.palette.fill
        return { context in
            func shaft(top: CGFloat) {
                context.cartoon(Path(roundedRect: CGRect(x: x - 1.2, y: top, width: 2.4, height: y + 8 - top),
                                     cornerRadius: 1), leather)
            }
            if item.id.contains("axe") {
                shaft(top: y - 32)
                var blade = Path()
                blade.move(to: CGPoint(x: x + 1, y: y - 31))
                blade.addLine(to: CGPoint(x: x + 9, y: y - 35))
                blade.addQuadCurve(to: CGPoint(x: x + 9, y: y - 18), control: CGPoint(x: x + 13, y: y - 26.5))
                blade.addLine(to: CGPoint(x: x + 1, y: y - 22))
                blade.closeSubpath()
                context.cartoon(blade, steel)
            } else if item.id.contains("hammer") {
                shaft(top: y - 30)
                context.cartoon(Path(roundedRect: CGRect(x: x - 6, y: y - 35, width: 12, height: 8), cornerRadius: 1.5), steel)
            } else if item.id.contains("spear") {
                shaft(top: y - 46)
                var tip = Path()
                tip.addLines([CGPoint(x: x - 3, y: y - 44), CGPoint(x: x, y: y - 53), CGPoint(x: x + 3, y: y - 44)])
                tip.closeSubpath()
                context.cartoon(tip, steel)
            } else {
                var blade = Path()
                blade.addLines([CGPoint(x: x - 2, y: y - 6), CGPoint(x: x - 2, y: y - 36), CGPoint(x: x, y: y - 40),
                                CGPoint(x: x + 2, y: y - 36), CGPoint(x: x + 2, y: y - 6)])
                blade.closeSubpath()
                context.cartoon(blade, steel)
                context.cartoon(Path(roundedRect: CGRect(x: x - 1.3, y: y - 5, width: 2.6, height: 10), cornerRadius: 1),
                                leather)
                context.cartoon(Path(roundedRect: CGRect(x: x - 5, y: y - 7, width: 10, height: 2.6), cornerRadius: 1),
                                Theme.brass)
            }
            context.cartoon(Path(roundedRect: CGRect(x: x - 1.8, y: y + 4, width: 3.6, height: 2.2), cornerRadius: 0.8),
                            accent)
        }
    }
}

private extension GraphicsContext {
    /// Flat fill with the app's dark brown outline.
    func cartoon(_ path: Path, _ fill: Color) {
        self.fill(path, with: .color(fill))
        stroke(path, with: .color(Theme.outline), style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
    }
}
