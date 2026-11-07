//
//  RecipeDetailView.swift
//  Fantasy Fitness
//

import SwiftUI

struct RecipeDetailView: View {
    let recipe: Recipe

    @Environment(GameStore.self) private var store
    @State private var isLogged = false
    @State private var showingRating = false

    /// The store's copy, so new ratings show after a reload.
    private var latest: Recipe { store.recipes.first { $0.id == recipe.id } ?? recipe }


    var body: some View {
        BoardScreen(isRoot: false) {
            ParchmentScroll {
                KickerText("\(latest.mealType.name) · \(latest.minutes) min · serves \(latest.servings)")
                Text(latest.name)
                    .font(.alegreya(28, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 2)

                Text("Per serving")
                    .font(.alegreya(18))
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 16)
                HStack(spacing: 8) {
                    MacroTile(value: "\(latest.macros.calories)", label: "kcal")
                    MacroTile(value: "\(latest.macros.protein) g", label: "protein")
                    MacroTile(value: "\(latest.macros.carbs) g", label: "carbs")
                    MacroTile(value: "\(latest.macros.fat) g", label: "fat")
                }
                .padding(.top, 8)

                Text("Ingredients")
                    .font(.alegreya(18))
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 18)
                VStack(spacing: 0) {
                    ForEach(latest.ingredients, id: \.self) { ingredient in
                        HStack {
                            Text(ingredient.name)
                                .font(.alegreyaSans(17, weight: .medium))
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Text(ingredient.amount)
                                .font(.alegreyaSans(16))
                                .foregroundStyle(Theme.inkSecondary)
                        }
                        .padding(.vertical, 10)
                        DashedDivider()
                    }
                }

                Text("Ratings")
                    .font(.alegreya(18))
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 18)
                VStack(spacing: 8) {
                    ratingRow("Taste", latest.ratings.taste)
                    ratingRow("Ease", latest.ratings.ease)
                    ratingRow("Cost", latest.ratings.cost)
                    HStack {
                        Text("Macro profile")
                            .font(.alegreyaSans(16, weight: .bold))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        TagChip(label: "\(latest.macros.profileLabel) · auto",
                                fill: Theme.progressGreen.opacity(0.25), fontSize: 14)
                    }
                }
                .padding(.top, 8)

                Button {
                    let logged = store.logMeal(latest)
                    withAnimation(.snappy) { isLogged = logged }
                } label: {
                    Label(isLogged ? "Logged to today's rations" : "Log meal",
                          systemImage: isLogged ? "checkmark" : "fork.knife")
                }
                .buttonStyle(.chunky(isLogged ? .emerald : .wax))
                .disabled(isLogged)
                .padding(.top, 22)

                Button("Rate recipe") { showingRating = true }
                    .buttonStyle(.chunky(.wood))
                    .padding(.top, 12)
            }
        }
        .sheet(isPresented: $showingRating) {
            RateRecipeSheet(recipe: latest)
        }
    }

    private func ratingRow(_ axis: String, _ value: Double) -> some View {
        HStack {
            Text(axis)
                .font(.alegreyaSans(16, weight: .bold))
                .foregroundStyle(Theme.ink)
            Spacer()
            StarRating(value: value, size: 15)
            Text(value.formatted(.number.precision(.fractionLength(1))))
                .font(.alegreyaSans(15, weight: .bold))
                .foregroundStyle(Theme.inkSecondary)
                .monospacedDigit()
                .frame(width: 30, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

/// One macro value on a small parchment tile (recipe detail, Log a meal).
struct MacroTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 0) {
            Text(value)
                .font(.alegreyaSans(18, weight: .bold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.alegreyaSans(13))
                .foregroundStyle(Theme.inkSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.checkboxFill))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.outline, lineWidth: 2))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack {
        RecipeDetailView(recipe: Recipe.samples[1])
    }
    .environment(GameStore.preview)
}
