//
//  Food.swift
//  Fantasy Fitness
//
//  Foods from the Tavern's food search (USDA FoodData Central, through the food-search
//  Edge Function). The server keeps every food the app can pick and works out meal and
//  recipe macros from it; the app does the same math only to show numbers before the
//  server's arrive.
//

import Foundation

struct Food: Identifiable, Hashable {
    enum Source: String {
        case usda, estimate
    }

    let id: UUID
    let source: Source
    let name: String
    /// "USDA, as eaten", "USDA, ingredient" or "Estimated from your photo".
    let detail: String
    let per100g: Per100g
    /// Household measures from USDA, like "1 medium breast" = 120 g.
    let portions: [Portion]

    /// Grams to start from when this food is picked: its first portion, or 100 g.
    var defaultGrams: Double { portions.first?.grams ?? 100 }

    /// USDA names run long ("Chicken breast, grilled without sauce, skin not eaten"). The
    /// first part names the food, unless it's a one-word category ("Oil, olive", "Rice, white").
    var shortName: String {
        let parts = name.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let first = parts.first, !first.isEmpty else { return name }
        if !first.contains(" "), parts.count > 1 { return "\(first), \(parts[1])" }
        return first
    }
}

struct Per100g: Hashable {
    let kcal: Double
    let protein: Double
    let carbs: Double
    let fat: Double
}

struct Portion: Hashable {
    let label: String
    let grams: Double
}

/// One food on a plate being logged.
struct PlateItem: Identifiable, Hashable {
    let id = UUID()
    var food: Food
    var grams: Double

    var macros: Macros { FoodMath.total([(food.per100g, grams)]) }
}

/// An ingredient while a recipe is being written: picked from the food search (counted
/// toward the recipe's macros) or typed in as text (not counted).
struct RecipeIngredientDraft: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var amount: String
    var food: Food?
    var grams: Double

    var isCounted: Bool { food != nil }

    /// As the recipe will show it once saved.
    var ingredient: Ingredient {
        guard let food else { return Ingredient(name: name, amount: amount) }
        return Ingredient(name: name, amount: FoodMath.gramsText(grams), foodID: food.id, grams: grams)
    }
}

/// Limits the server checks. Keep these in step with 20261108000000_food_data.sql, or a
/// log is refused forever.
enum FoodLimits {
    static let plateFoods = 30
    static let plateGrams: ClosedRange<Double> = 1...2_000
    static let recipeIngredients = 40
    static let recipeGrams: ClosedRange<Double> = 1...5_000
    static let recipeServings: ClosedRange<Int> = 1...50
    static let nameLength = 80
}

/// Macros from per-100 g values and grams, rounded the way the server rounds (halves away
/// from zero). The server's numbers replace these after the next refresh.
enum FoodMath {
    static func total(_ parts: [(Per100g, Double)]) -> Macros {
        perServing(parts, servings: 1)
    }

    static func perServing(_ parts: [(Per100g, Double)], servings: Int) -> Macros {
        func sum(_ value: KeyPath<Per100g, Double>) -> Int {
            let total = parts.reduce(0) { $0 + $1.0[keyPath: value] * $1.1 / 100 }
            return Int((total / Double(max(servings, 1))).rounded())
        }
        return Macros(calories: sum(\.kcal), protein: sum(\.protein), carbs: sum(\.carbs), fat: sum(\.fat))
    }

    static func plate(_ items: [PlateItem]) -> Macros {
        total(items.map { ($0.food.per100g, $0.grams) })
    }

    /// "150 g", "13.5 g".
    static func gramsText(_ grams: Double) -> String {
        "\(grams.formatted(.number.precision(.fractionLength(0...1)).grouping(.never))) g"
    }
}

// MARK: - Sample data (previews and offline demo mode)

extension Food {
    /// A few common foods with USDA's values, for searching in demo mode.
    static let samples: [Food] = [
        sample(1, "Chicken breast, grilled without sauce, skin not eaten", "USDA, as eaten", 176, 29.62, 0, 5.45,
               [Portion(label: "1 medium breast", grams: 120), Portion(label: "1 small breast", grams: 105),
                Portion(label: "1 cup, cooked, diced", grams: 135)]),
        sample(2, "Rice, white, cooked, no added fat", "USDA, as eaten", 129, 2.67, 27.99, 0.28,
               [Portion(label: "1 cup, cooked", grams: 158)]),
        sample(3, "Broccoli, cooked, boiled, drained, without salt", "USDA, ingredient", 35, 2.38, 7.18, 0.41,
               [Portion(label: "1 cup, chopped", grams: 156)]),
        sample(4, "Bananas, raw", "USDA, ingredient", 89, 1.09, 22.84, 0.33,
               [Portion(label: "1 medium", grams: 118)]),
        sample(5, "Egg, whole, cooked, hard-boiled", "USDA, ingredient", 155, 12.58, 1.12, 10.61,
               [Portion(label: "1 large", grams: 50)]),
        sample(6, "Oats, rolled, dry", "USDA, ingredient", 379, 13.15, 67.7, 6.52,
               [Portion(label: "1/2 cup", grams: 40)]),
        sample(7, "Yogurt, Greek, plain, nonfat", "USDA, ingredient", 59, 10.19, 3.6, 0.39,
               [Portion(label: "1 container (6 oz)", grams: 170)]),
        sample(8, "Salmon, Atlantic, farmed, cooked, dry heat", "USDA, ingredient", 206, 22.1, 0, 12.35,
               [Portion(label: "1/2 fillet", grams: 154)]),
        sample(9, "Oil, olive, extra virgin", "USDA, ingredient", 884, 0, 0, 100,
               [Portion(label: "1 tbsp", grams: 13.5)]),
        sample(10, "Peanut butter, smooth style, without salt", "USDA, ingredient", 588, 25.09, 19.56, 50.39,
               [Portion(label: "1 tbsp", grams: 16)]),
        sample(11, "Milk, reduced fat, fluid, 2% milkfat", "USDA, ingredient", 50, 3.3, 4.8, 1.98,
               [Portion(label: "1 cup", grams: 244)]),
        sample(12, "Apples, raw, with skin", "USDA, ingredient", 52, 0.26, 13.81, 0.17,
               [Portion(label: "1 medium", grams: 182)]),
    ]

    /// Demo search: foods whose name contains every word typed.
    static func sampleSearch(_ query: String) -> [Food] {
        let words = query.lowercased().split(separator: " ")
        return samples.filter { food in words.allSatisfy { food.name.lowercased().contains($0) } }
    }

    private static func sample(_ number: Int, _ name: String, _ detail: String, _ kcal: Double, _ protein: Double,
                               _ carbs: Double, _ fat: Double, _ portions: [Portion]) -> Food {
        Food(id: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", number))!,
             source: .usda, name: name, detail: detail,
             per100g: Per100g(kcal: kcal, protein: protein, carbs: carbs, fat: fat), portions: portions)
    }
}
