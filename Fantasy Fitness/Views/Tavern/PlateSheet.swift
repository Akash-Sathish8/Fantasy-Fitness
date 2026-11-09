//
//  PlateSheet.swift
//  Fantasy Fitness
//

import SwiftUI

/// Build a meal from searched foods: add each food, set how much, then log it. The
/// totals are a preview; the server sums the real macros from its food data.
struct PlateSheet: View {
    /// Runs after the plate is logged, so the sheet that opened this can close too.
    var onLogged: () -> Void = {}

    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var items: [PlateItem] = []
    @State private var name = ""
    @State private var search: SearchRequest?
    @State private var isLogging = false
    @State private var isKeyboardUp = false

    /// Opening the food search, to add a food or to swap one already on the plate.
    private struct SearchRequest: Identifiable {
        let id = UUID()
        var replacing: PlateItem.ID?
        var query = ""
    }

    private var totals: Macros { FoodMath.plate(items) }

    /// "Chicken breast and Rice, white", or "Chicken breast and 2 more".
    private var suggestedName: String {
        switch items.count {
        case 0: return "Plate"
        case 1: return items[0].food.shortName
        case 2: return "\(items[0].food.shortName) and \(items[1].food.shortName)"
        default: return "\(items[0].food.shortName) and \(items.count - 1) more"
        }
    }

    var body: some View {
        SheetScaffold(title: "Build a plate", closeLabel: "Cancel") {
            if items.isEmpty {
                Text("Add each food you ate and set how much. Nutrition comes from USDA's food database.")
                    .font(.alegreyaSans(16))
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 12)
            }
            VStack(spacing: 10) {
                ForEach($items) { $item in
                    PlateItemRow(item: $item) {
                        openSearch(SearchRequest(replacing: item.id, query: item.food.shortName))
                    } onRemove: {
                        withAnimation(.snappy) { items.removeAll { $0.id == item.id } }
                    }
                }
            }
            Button { openSearch(SearchRequest()) } label: {
                Label(items.isEmpty ? "Search foods" : "Add a food", systemImage: "magnifyingglass")
            }
            .buttonStyle(.chunky(.wood, minHeight: 48, fontSize: 17))
            .disabled(items.count >= FoodLimits.plateFoods)
            .padding(.top, 12)

            if !items.isEmpty {
                ParchmentField(title: "Meal name", text: $name, prompt: suggestedName)
                    .padding(.top, 18)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // While typing, a slim Done bar takes the summary's place, so more of the list
            // shows above the keyboard and nothing is logged mid-edit.
            if isKeyboardUp { KeyboardDoneBar() } else { summary }
        }
        .tracksKeyboard($isKeyboardUp)
        .presentationDetents([.large])
        // A swipe down shouldn't throw away a plate; Cancel still does.
        .interactiveDismissDisabled(!items.isEmpty)
        .sheet(item: $search) { request in
            FoodSearchSheet(initialQuery: request.query) { pick in
                guard case .food(let food) = pick else { return }
                withAnimation(.snappy) { add(food, replacing: request.replacing) }
            }
        }
    }

    /// Plate totals and the Log button, pinned below the list like Log a meal's.
    private var summary: some View {
        VStack(alignment: .leading, spacing: 10) {
            totalsRow
            Button {
                guard !isLogging else { return }
                isLogging = true  // a second tap during the dismiss would log a second plate
                let mealName = name.trimmingCharacters(in: .whitespaces).isEmpty ? suggestedName : name
                if store.logPlate(name: mealName, items: items) {
                    dismiss()
                    onLogged()
                } else {
                    isLogging = false
                }
            } label: {
                Label("Log meal", systemImage: "fork.knife")
            }
            .buttonStyle(.chunky(.wax))
            .disabled(items.isEmpty || isLogging)
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

    private var totalsRow: some View {
        HStack(spacing: 8) {
            MacroTile(value: totals.calories.formatted(), label: "kcal")
            MacroTile(value: "\(totals.protein.formatted()) g", label: "protein")
            MacroTile(value: "\(totals.carbs.formatted()) g", label: "carbs")
            MacroTile(value: "\(totals.fat.formatted()) g", label: "fat")
        }
    }

    private func openSearch(_ request: SearchRequest) {
        UIApplication.shared.endEditing()  // or the grams keyboard comes back when the search closes
        search = request
    }

    private func add(_ food: Food, replacing id: PlateItem.ID?) {
        if let id, let index = items.firstIndex(where: { $0.id == id }) {
            items[index].food = food  // keeps the amount already set
        } else {
            items.append(PlateItem(food: food, grams: food.defaultGrams(in: FoodLimits.plateGrams)))
        }
    }
}

/// One food on the plate: what it is, what this amount adds, and how much.
private struct PlateItemRow: View {
    @Binding var item: PlateItem
    let onSwap: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.food.shortName)
                        .font(.alegreyaSans(18, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    if item.food.shortName != item.food.name {
                        Text(item.food.name)
                            .font(.alegreyaSans(14))
                            .foregroundStyle(Theme.inkSecondary)
                            .lineLimit(2)
                    }
                    Text("\(item.macros.calories)\u{00A0}kcal · \(item.macros.protein)\u{00A0}g protein")
                        .font(.alegreyaSans(15, weight: .bold))
                        .foregroundStyle(Theme.kicker)
                        .contentTransition(.numericText())
                }
                Spacer(minLength: 4)
                Menu {
                    Button("Swap food", systemImage: "arrow.triangle.2.circlepath", action: onSwap)
                    Button("Remove", systemImage: "trash", role: .destructive, action: onRemove)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Theme.inkSecondary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Options for \(item.food.shortName)")
            }
            GramsEditor(grams: $item.grams, portions: item.food.portions, range: FoodLimits.plateGrams)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.checkboxFill))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.outline, lineWidth: 2))
    }
}

#Preview {
    Text("Tavern")
        .sheet(isPresented: .constant(true)) { PlateSheet() }
        .environment(GameStore.preview)
}
