//
//  LogMealSheet.swift
//  Fantasy Fitness
//

import SwiftUI

/// Pick the meal you ate; its nutrition fills in from the recipe (one serving).
/// The meal counts toward today's rations right away and uploads with the next sync.
struct LogMealSheet: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: Recipe.ID?

    private var selected: Recipe? { store.recipes.first { $0.id == selectedID } }

    var body: some View {
        SheetScaffold(title: "Log a meal", closeLabel: "Cancel") {
            if store.recipes.isEmpty {
                Text("No meals in the library yet. Create a recipe in the Tavern first.")
                    .font(.alegreyaSans(16))
                    .foregroundStyle(Theme.inkSecondary)
            }
            ForEach(MealType.allCases, id: \.self) { mealType in
                let recipes = store.recipes.filter { $0.mealType == mealType }
                if !recipes.isEmpty {
                    KickerText(mealType.name)
                        .padding(.top, 14)
                        .padding(.bottom, 6)
                    VStack(spacing: 8) {
                        ForEach(recipes) { recipe in
                            MealOption(recipe: recipe, isSelected: recipe.id == selectedID) {
                                withAnimation(.snappy) { selectedID = recipe.id }
                            }
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            summary
        }
        .presentationDetents([.large])
    }

    /// The chosen meal's nutrition and the Log button, pinned below the list.
    private var summary: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let selected {
                Text("\(selected.name) · 1 serving")
                    .font(.alegreya(17, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    MacroTile(value: "\(selected.macros.calories)", label: "kcal")
                    MacroTile(value: "\(selected.macros.protein) g", label: "protein")
                    MacroTile(value: "\(selected.macros.carbs) g", label: "carbs")
                    MacroTile(value: "\(selected.macros.fat) g", label: "fat")
                }
            } else {
                Text("Pick what you ate. Its nutrition fills in for you.")
                    .font(.alegreyaSans(16))
                    .foregroundStyle(Theme.inkSecondary)
            }
            Button {
                if let selected, store.logMeal(selected) { dismiss() }
            } label: {
                Label("Log meal", systemImage: "fork.knife")
            }
            .buttonStyle(.chunky(.wax))
            .disabled(selected == nil)
        }
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

private struct MealOption: View {
    let recipe: Recipe
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(recipe.name)
                        .font(.alegreyaSans(17, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.leading)
                    Text(recipe.macros.calories > 0
                         ? "\(recipe.macros.calories) kcal · \(recipe.macros.protein) g protein"
                         : "Macros pending")
                        .font(.alegreyaSans(15))
                        .foregroundStyle(Theme.inkSecondary)
                }
                Spacer(minLength: 8)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(isSelected ? Theme.progressGreen : Theme.outline.opacity(0.5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 56)
            .background(RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Theme.progressGreen.opacity(0.18) : Theme.checkboxFill))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isSelected ? Theme.progressGreen : Theme.outline, lineWidth: isSelected ? 3 : 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) { LogMealSheet() }
        .environment(GameStore.preview)
}
