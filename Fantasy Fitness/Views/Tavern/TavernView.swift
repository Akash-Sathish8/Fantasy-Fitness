//
//  TavernView.swift
//  Fantasy Fitness
//

import SwiftUI

/// Meal library → Recipe detail → Log meal → Rate recipe. Log a meal and Create recipe
/// are sheets.
struct TavernView: View {
    private enum Shelf: Hashable, CaseIterable {
        case library, mine

        var title: String {
            switch self {
            case .library: "Meal library"
            case .mine: "My recipes"
            }
        }
    }

    @Environment(GameStore.self) private var store

    @State private var shelf: Shelf = .library
    @State private var showingCreate = false
    @State private var showingLogMeal = false

    private var visibleRecipes: [Recipe] {
        shelf == .mine ? store.recipes.filter(\.isMine) : store.recipes
    }

    var body: some View {
        BoardScreen {
            BoardSign(title: "Tavern")

            RationsCard(rations: store.rations)

            Button { showingLogMeal = true } label: {
                Label("Log a meal", systemImage: "fork.knife")
            }
            .buttonStyle(.chunky(.wax))

            WoodSegmentedPicker(options: Shelf.allCases, selection: $shelf, title: \.title)
                .padding(.top, 4)

            BoardSectionHeader(title: shelf.title) {
                Button { showingCreate = true } label: {
                    HeaderLinkLabel(title: "New recipe", systemImage: "plus")
                }
                .buttonStyle(.plain)
            }

            ForEach(visibleRecipes) { recipe in
                NavigationLink(value: recipe) {
                    RecipeCard(recipe: recipe)
                }
                .buttonStyle(.plain)
            }
        }
        .navigationDestination(for: Recipe.self) { recipe in
            RecipeDetailView(recipe: recipe)
        }
        .sheet(isPresented: $showingCreate) {
            CreateRecipeSheet()
        }
        .sheet(isPresented: $showingLogMeal) {
            LogMealSheet()
        }
    }
}

/// Today's macros against targets, framed as fuel.
private struct RationsCard: View {
    let rations: DailyRations

    var body: some View {
        ParchmentCard {
            NoteHeading(title: "Today's rations", subtitle: "Fuel for training and recovery")
            VStack(spacing: 12) {
                MacroBar(name: "Energy", eaten: rations.eaten.calories, target: rations.target.calories,
                         unit: "kcal", tint: Theme.vitality)
                MacroBar(name: "Protein", eaten: rations.eaten.protein, target: rations.target.protein,
                         unit: "g", tint: Theme.progressGreen)
                MacroBar(name: "Carbs", eaten: rations.eaten.carbs, target: rations.target.carbs,
                         unit: "g", tint: Theme.gold)
                MacroBar(name: "Fat", eaten: rations.eaten.fat, target: rations.target.fat,
                         unit: "g", tint: Theme.sapphire)
            }
            .padding(.top, 14)
        }
    }
}

private struct MacroBar: View {
    let name: String
    let eaten: Int
    let target: Int
    let unit: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name)
                    .font(.alegreyaSans(16, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text("\(eaten.formatted()) / \(target.formatted()) \(unit)")
                    .font(.alegreyaSans(15, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .monospacedDigit()
            }
            ParchmentProgressBar(progress: Double(eaten) / Double(target), height: 10, tint: tint)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(eaten) of \(target) \(unit)")
    }
}

private struct RecipeCard: View {
    let recipe: Recipe

    var body: some View {
        ParchmentCard(padding: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    KickerText("\(recipe.mealType.name) · \(recipe.minutes) min")
                    Text(recipe.name)
                        .font(.alegreya(21, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(.top, 6)
            }

            FlowLayout(spacing: 8) {
                if recipe.macros.calories > 0 {
                    TagChip(label: recipe.macros.profileLabel, fill: Theme.progressGreen.opacity(0.25), fontSize: 14)
                    TagChip(label: "\(recipe.macros.protein) g protein", fontSize: 14)
                    TagChip(label: "\(recipe.macros.calories) kcal", fontSize: 14)
                } else {
                    TagChip(label: "Macros pending", fontSize: 14)
                }
            }
            .padding(.top, 10)

            HStack(spacing: 6) {
                StarRating(value: recipe.ratings.taste)
                Text("Taste \(recipe.ratings.taste.formatted(.number.precision(.fractionLength(1)))) · \(recipe.ratings.count) ratings")
                    .font(.alegreyaSans(14, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
            }
            .padding(.top, 10)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack {
        TavernView()
    }
    .environment(GameStore.preview)
}
