//
//  RecipeSheets.swift
//  Fantasy Fitness
//

import SwiftUI

/// Rate on separate axes. Macro profile is computed, so it isn't rated here.
struct RateRecipeSheet: View {
    let recipe: Recipe

    @Environment(GameStore.self) private var store
    @State private var taste = 4
    @State private var ease = 4
    @State private var cost = 4
    @State private var isSaving = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SheetScaffold(title: "Rate recipe", closeLabel: "Cancel") {
            Text(recipe.name)
                .font(.alegreya(20, weight: .heavy))
                .foregroundStyle(Theme.ink)

            VStack(alignment: .leading, spacing: 14) {
                axis("Taste", $taste)
                axis("Ease", $ease)
                axis("Cost", $cost)
            }
            .padding(.top, 16)

            Text("Macro profile (\(recipe.macros.profileLabel.lowercased())) is calculated from the ingredients.")
                .font(.alegreyaSans(14))
                .foregroundStyle(Theme.inkSecondary)
                .padding(.top, 16)

            Button("Submit rating") {
                Task {
                    isSaving = true
                    if await store.rate(recipe, taste: taste, ease: ease, cost: cost) { dismiss() }
                    isSaving = false
                }
            }
            .disabled(isSaving)
                .buttonStyle(.chunky(.wax))
                .padding(.top, 22)
        }
        .presentationDetents([.medium, .large])
    }

    private func axis(_ name: String, _ value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(.alegreyaSans(17, weight: .bold))
                .foregroundStyle(Theme.ink)
            StarRatingPicker(value: value)
                .accessibilityLabel(name)
        }
    }
}

/// New recipe. Ingredients picked from the food search count toward its macros, which the
/// server works out per serving; ingredients typed in as text are saved but not counted.
struct CreateRecipeSheet: View {
    @Environment(GameStore.self) private var store
    @State private var isSaving = false
    @State private var name = ""
    @State private var mealType: MealType = .dinner
    @State private var servings = 1
    @State private var ingredients: [RecipeIngredientDraft] = []
    @State private var isSearching = false
    @State private var isKeyboardUp = false
    @Environment(\.dismiss) private var dismiss

    private var countedCount: Int { ingredients.filter(\.isCounted).count }

    /// Preview only; the server's numbers replace these once the recipe is saved.
    private var perServing: Macros {
        FoodMath.perServing(ingredients.compactMap { draft in draft.food.map { ($0.per100g, draft.grams) } },
                            servings: servings)
    }

    var body: some View {
        SheetScaffold(title: "New recipe", closeLabel: "Cancel") {
            ParchmentField(title: "Name", text: $name, prompt: "Hearty stew")

            Text("Meal")
                .font(.alegreyaSans(15, weight: .bold))
                .foregroundStyle(Theme.inkSecondary)
                .padding(.top, 16)
            WoodSegmentedPicker(options: MealType.allCases, selection: $mealType, title: \.name)
                .padding(.top, 6)

            ServingsStepper(servings: $servings)
                .padding(.top, 16)

            Text("Ingredients")
                .font(.alegreya(18))
                .foregroundStyle(Theme.ink)
                .padding(.top, 20)
            VStack(spacing: 10) {
                ForEach($ingredients) { $ingredient in
                    IngredientDraftRow(ingredient: $ingredient) {
                        withAnimation(.snappy) { ingredients.removeAll { $0.id == ingredient.id } }
                    }
                }
            }
            .padding(.top, 8)

            Button {
                UIApplication.shared.endEditing()  // or the keyboard comes back when the search closes
                isSearching = true
            } label: {
                Label("Add ingredient", systemImage: "plus")
            }
            .buttonStyle(.chunky(.wood, minHeight: 48, fontSize: 17))
            .disabled(ingredients.count >= FoodLimits.recipeIngredients)
            .padding(.top, 12)

            if countedCount > 0 {
                Text("Per serving")
                    .font(.alegreya(18))
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 20)
                HStack(spacing: 8) {
                    MacroTile(value: perServing.calories.formatted(), label: "kcal")
                    MacroTile(value: "\(perServing.protein.formatted()) g", label: "protein")
                    MacroTile(value: "\(perServing.carbs.formatted()) g", label: "carbs")
                    MacroTile(value: "\(perServing.fat.formatted()) g", label: "fat")
                }
                .padding(.top, 8)
            }
            Text(macrosNote)
                .font(.alegreyaSans(14))
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            Button("Save recipe") {
                isSaving = true  // before the task starts, so a quick second tap can't save twice
                Task {
                    if await store.createRecipe(name: name, mealType: mealType, servings: servings,
                                                ingredients: ingredients) {
                        dismiss()
                    }
                    isSaving = false
                }
            }
                .buttonStyle(.chunky(.emerald))
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || ingredients.isEmpty || isSaving)
                .padding(.top, 18)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isKeyboardUp { KeyboardDoneBar() }
        }
        .tracksKeyboard($isKeyboardUp)
        // A swipe down shouldn't throw away a recipe in progress; Cancel still does.
        .interactiveDismissDisabled(!ingredients.isEmpty || !name.isEmpty)
        .sheet(isPresented: $isSearching) {
            FoodSearchSheet(allowsTextOnly: true) { pick in
                withAnimation(.snappy) {
                    switch pick {
                    case .food(let food):
                        ingredients.append(RecipeIngredientDraft(name: String(food.name.prefix(FoodLimits.nameLength)),
                                                                 amount: "", food: food,
                                                                 grams: food.defaultGrams(in: FoodLimits.recipeGrams)))
                    case .textOnly(let text):
                        ingredients.append(RecipeIngredientDraft(name: String(text.prefix(FoodLimits.nameLength)),
                                                                 amount: "", food: nil, grams: 0))
                    }
                }
            }
        }
    }

    private var macrosNote: String {
        if ingredients.isEmpty {
            return "Search for each ingredient and the Tavern works out the macros per serving."
        }
        if countedCount == ingredients.count {
            return countedCount == 1 ? "Counted from the ingredient above." : "Counted from all \(countedCount) ingredients."
        }
        return "Counted from \(countedCount) of \(ingredients.count) ingredients. Searched foods count; typed-in ones don't."
    }
}

/// "Serves 4" with − and +. Macros are per serving, so this divides the whole recipe.
private struct ServingsStepper: View {
    @Binding var servings: Int

    var body: some View {
        HStack(spacing: 10) {
            Text("Serves")
                .font(.alegreyaSans(17, weight: .bold))
                .foregroundStyle(Theme.ink)
            Spacer()
            step("minus", label: "Fewer servings") { servings -= 1 }
                .disabled(servings <= FoodLimits.recipeServings.lowerBound)
            Text("\(servings)")
                .font(.alegreyaSans(20, weight: .bold))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
                .contentTransition(.numericText())
                .frame(minWidth: 32)
            step("plus", label: "More servings") { servings += 1 }
                .disabled(servings >= FoodLimits.recipeServings.upperBound)
        }
        // One VoiceOver stop: "Serves, 4", swipe up or down to change.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Serves")
        .accessibilityValue("\(servings)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment where servings < FoodLimits.recipeServings.upperBound: servings += 1
            case .decrement where servings > FoodLimits.recipeServings.lowerBound: servings -= 1
            default: break
            }
        }
    }

    private func step(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button { withAnimation(.snappy) { action() } } label: {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .heavy))
                .frame(width: 20, height: 44)
        }
        .buttonStyle(.chunky(.wood, minHeight: 44, fullWidth: false, fontSize: 17))
        .accessibilityLabel(label)
    }
}

/// An ingredient being added: a searched food with its grams, or a typed-in name with a
/// free-text amount that isn't counted.
private struct IngredientDraftRow: View {
    @Binding var ingredient: RecipeIngredientDraft
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ingredient.name)
                        .font(.alegreyaSans(17, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                    if let food = ingredient.food {
                        let macros = FoodMath.total([(food.per100g, ingredient.grams)])
                        Text("\(macros.calories)\u{00A0}kcal · \(macros.protein)\u{00A0}g protein")
                            .font(.alegreyaSans(15, weight: .bold))
                            .foregroundStyle(Theme.kicker)
                    } else {
                        TagChip(label: "Not counted", fill: Theme.scrollRoll.opacity(0.35), fontSize: 13)
                    }
                }
                Spacer(minLength: 4)
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Theme.inkSecondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(ingredient.name)")
            }
            if let food = ingredient.food {
                GramsEditor(grams: $ingredient.grams, portions: food.portions, range: FoodLimits.recipeGrams)
            } else {
                ParchmentField(title: "Amount", text: $ingredient.amount, prompt: "a pinch")
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.checkboxFill))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.outline, lineWidth: 2))
    }
}

#Preview("Rate") {
    Text("Tavern").sheet(isPresented: .constant(true)) { RateRecipeSheet(recipe: Recipe.samples[0]).environment(GameStore.preview) }
}

#Preview("Create") {
    Text("Tavern").sheet(isPresented: .constant(true)) { CreateRecipeSheet().environment(GameStore.preview) }
}
