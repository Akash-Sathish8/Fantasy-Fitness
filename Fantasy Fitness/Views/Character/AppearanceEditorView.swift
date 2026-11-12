//
//  AppearanceEditorView.swift
//  Fantasy Fitness
//

import SwiftUI

/// Character creator: frame, skin tone, hairstyle and hair color, with a live preview.
struct AppearanceEditorView: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft = Appearance()
    @State private var showsGear = true
    @State private var isSaving = false

    private var gear: [Item] { showsGear ? store.player.equipped : [] }

    var body: some View {
        SheetScaffold(title: "Customize", closeLabel: "Cancel") {
            preview

            section("Frame")
            WoodSegmentedPicker(options: BodyType.allCases, selection: $draft.bodyType) { $0.name }

            section("Skin tone")
            SwatchPicker(swatches: Appearance.skinTones, selection: $draft.skinTone)

            section("Hair")
            FlowLayout(spacing: 10) {
                ForEach(HairStyle.allCases) { style in
                    HairOption(appearance: Appearance(bodyType: draft.bodyType, skinTone: draft.skinTone,
                                                      hairStyle: style, hairColor: draft.hairColor),
                               isSelected: style == draft.hairStyle) {
                        withAnimation(.snappy) { draft.hairStyle = style }
                    }
                }
            }

            if draft.hairStyle != .shaved {
                section("Hair color")
                SwatchPicker(swatches: Appearance.hairColors, selection: $draft.hairColor)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { saveBar }
        .presentationDetents([.large])
        .onAppear { draft = store.player.appearance }
    }

    private var preview: some View {
        VStack(spacing: 8) {
            CharacterView(appearance: draft, equipped: gear)
                .frame(height: 230)
                .frame(maxWidth: .infinity)
                .background(alignment: .bottom) {
                    Ellipse().fill(Theme.outline.opacity(0.15)).frame(width: 120, height: 16).offset(y: -4)
                }
            Button {
                withAnimation(.snappy) { showsGear.toggle() }
            } label: {
                Label(showsGear ? "Hide gear" : "Show gear", systemImage: showsGear ? "eye.slash" : "eye")
            }
            .buttonStyle(.chunky(.wood, minHeight: 44, fullWidth: false, fontSize: 16))
            .disabled(store.player.equipped.isEmpty)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.noteParchment))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.outline, lineWidth: 2))
    }

    private func section(_ title: String) -> some View {
        KickerText(title)
            .padding(.top, 20)
            .padding(.bottom, 8)
    }

    private var saveBar: some View {
        Button {
            Task {
                isSaving = true
                if await store.saveAppearance(draft) { dismiss() }
                isSaving = false
            }
        } label: {
            Label("Save look", systemImage: "checkmark")
        }
        .buttonStyle(.chunky(.wax))
        .disabled(isSaving || draft == store.player.appearance)
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .background(
            Theme.noteParchment
                .overlay(alignment: .top) { Rectangle().fill(Theme.outline).frame(height: 2) }
                .ignoresSafeArea()
        )
    }
}

/// One row of round color swatches, spread across the width.
private struct SwatchPicker: View {
    let swatches: [Appearance.Swatch]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(swatches) { swatch in
                let isSelected = swatch.id == selection
                Button {
                    withAnimation(.snappy) { selection = swatch.id }
                } label: {
                    Circle()
                        .fill(swatch.color)
                        .overlay(Circle().strokeBorder(Theme.outline, lineWidth: isSelected ? 3 : 2))
                        .overlay(Circle().strokeBorder(Theme.cream, lineWidth: 2).padding(3).opacity(isSelected ? 1 : 0))
                        .frame(width: isSelected ? 40 : 34, height: isSelected ? 40 : 34)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(swatch.name)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

/// A hairstyle shown on the player's own head.
private struct HairOption: View {
    let appearance: Appearance
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                CharacterPortrait(appearance: appearance, equipped: [], size: 64,
                                  palette: isSelected ? .emerald : .wood, shadowOffset: isSelected ? 2 : 3)
                Text(appearance.hairStyle.name)
                    .font(.alegreyaSans(15, weight: .bold))
                    .foregroundStyle(isSelected ? Theme.positiveText : Theme.ink)
            }
            .frame(minWidth: 72)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(appearance.hairStyle.name)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) { AppearanceEditorView() }
        .environment(GameStore.preview)
}
