//
//  Nutrition.swift
//  Fantasy Fitness
//

import Foundation

struct Macros: Hashable {
    let calories: Int
    let protein: Int
    let carbs: Int
    let fat: Int

    /// Auto macro-profile label; recipes are never rated on this by hand.
    var profileLabel: String {
        let proteinShare = Double(protein * 4) / Double(max(calories, 1))
        if proteinShare >= 0.3 { return "High protein" }
        if Double(carbs * 4) / Double(max(calories, 1)) >= 0.55 { return "Carb fuel" }
        return "Balanced"
    }
}

struct Ingredient: Hashable {
    let name: String
    let amount: String
    /// Set when the ingredient was picked from the food search; only those count toward
    /// the recipe's macros.
    var foodID: UUID? = nil
    var grams: Double? = nil

    var isCounted: Bool { foodID != nil }
}

/// Ratings are on separate axes; macro profile is computed, not rated.
struct RecipeRatings: Hashable {
    let taste: Double
    let ease: Double
    let cost: Double
    let count: Int
}

enum MealType: String, CaseIterable {
    case breakfast, lunch, dinner, snack

    var name: String { rawValue.capitalized }
}

struct Recipe: Identifiable, Hashable {
    let id: String
    let name: String
    let mealType: MealType
    let minutes: Int
    let servings: Int
    let macros: Macros
    let ingredients: [Ingredient]
    let ratings: RecipeRatings
    let isMine: Bool
}

/// Today's intake vs. targets. Calorie targets always have a floor; food is fuel.
struct DailyRations {
    let eaten: Macros
    let target: Macros

    /// 0…1 share of a target, safe when the target hasn't loaded yet.
    func progress(_ macro: KeyPath<Macros, Int>) -> Double {
        target[keyPath: macro] > 0 ? Double(eaten[keyPath: macro]) / Double(target[keyPath: macro]) : 0
    }
}

// MARK: - Sample data (previews and offline demo mode)

extension DailyRations {
    static let sample = DailyRations(
        eaten: Macros(calories: 1_640, protein: 92, carbs: 180, fat: 48),
        target: Macros(calories: 2_600, protein: 160, carbs: 280, fat: 80)
    )
}

extension Recipe {
    static let samples: [Recipe] = [
        Recipe(id: "iron-oats", name: "Iron Oats", mealType: .breakfast, minutes: 5, servings: 1,
               macros: Macros(calories: 520, protein: 38, carbs: 62, fat: 14),
               ingredients: [Ingredient(name: "Rolled oats", amount: "80 g"),
                             Ingredient(name: "Whey protein", amount: "1 scoop"),
                             Ingredient(name: "Banana", amount: "1"),
                             Ingredient(name: "Peanut butter", amount: "1 tbsp")],
               ratings: RecipeRatings(taste: 4.5, ease: 4.9, cost: 4.6, count: 212), isMine: false),
        Recipe(id: "ranger-bowl", name: "Ranger's Chicken Bowl", mealType: .lunch, minutes: 20, servings: 2,
               macros: Macros(calories: 640, protein: 52, carbs: 70, fat: 16),
               ingredients: [Ingredient(name: "Chicken thigh", amount: "300 g"),
                             Ingredient(name: "Jasmine rice", amount: "150 g dry"),
                             Ingredient(name: "Black beans", amount: "1 can"),
                             Ingredient(name: "Salsa", amount: "4 tbsp")],
               ratings: RecipeRatings(taste: 4.7, ease: 4.1, cost: 4.3, count: 158), isMine: false),
        Recipe(id: "smiths-chili", name: "Smith's Chili", mealType: .dinner, minutes: 45, servings: 4,
               macros: Macros(calories: 580, protein: 44, carbs: 48, fat: 22),
               ingredients: [Ingredient(name: "Lean ground beef", amount: "500 g"),
                             Ingredient(name: "Kidney beans", amount: "2 cans"),
                             Ingredient(name: "Crushed tomatoes", amount: "1 can"),
                             Ingredient(name: "Onion", amount: "1")],
               ratings: RecipeRatings(taste: 4.8, ease: 3.6, cost: 4.4, count: 301), isMine: false),
        Recipe(id: "monk-stirfry", name: "Monk's Tofu Stir-fry", mealType: .dinner, minutes: 25, servings: 2,
               macros: Macros(calories: 480, protein: 30, carbs: 50, fat: 18),
               ingredients: [Ingredient(name: "Firm tofu", amount: "400 g"),
                             Ingredient(name: "Broccoli", amount: "1 head"),
                             Ingredient(name: "Soy sauce", amount: "3 tbsp"),
                             Ingredient(name: "Brown rice", amount: "120 g dry")],
               ratings: RecipeRatings(taste: 4.2, ease: 4.0, cost: 4.7, count: 87), isMine: false),
        Recipe(id: "paladin-pancakes", name: "Paladin's Protein Pancakes", mealType: .breakfast, minutes: 15, servings: 1,
               macros: Macros(calories: 450, protein: 40, carbs: 45, fat: 10),
               ingredients: [Ingredient(name: "Oat flour", amount: "60 g"),
                             Ingredient(name: "Egg whites", amount: "150 ml"),
                             Ingredient(name: "Greek yogurt", amount: "100 g"),
                             Ingredient(name: "Blueberries", amount: "a handful")],
               ratings: RecipeRatings(taste: 4.4, ease: 4.3, cost: 4.2, count: 64), isMine: true),
    ]
}
