//
//  PlateSheet.swift
//  Fantasy Fitness
//

import SwiftUI

/// Build a meal from a photo or searched foods: the plate reader lists what's in a photo,
/// the player fixes the foods and amounts, adds any it missed, then logs it. The totals
/// are a preview; the server sums the real macros from its food data.
struct PlateSheet: View {
    /// A photo picked before the sheet opened (Log a meal's "Snap a photo"), read right away.
    var initialPhoto: MealPhotoSource? = nil
    /// Runs after the plate is logged, so the sheet that opened this can close too.
    var onLogged: () -> Void = {}

    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var items: [PlateItem] = []
    @State private var name = ""
    @State private var search: SearchRequest?
    @State private var isLogging = false
    @State private var isKeyboardUp = false
    @State private var scanner = PlateScanner()
    @State private var didReadInitialPhoto = false
    /// The plate reader's name for the meal ("Chicken, rice and broccoli"), suggested while
    /// the plate holds exactly the foods it found.
    @State private var photoMeal: (name: String, items: Set<PlateItem.ID>)?
    /// Foods a photo found that didn't fit on the plate.
    @State private var leftOff = 0

    /// Opening the food search, to add a food or to swap one already on the plate.
    private struct SearchRequest: Identifiable {
        let id = UUID()
        var replacing: PlateItem.ID?
        var query = ""
    }

    private var totals: Macros { FoodMath.plate(items) }

    /// The photo's meal name, or "Chicken breast and Rice, white", or "Chicken breast and 2 more".
    private var suggestedName: String {
        if let photoMeal, Set(items.map(\.id)) == photoMeal.items { return photoMeal.name }
        switch items.count {
        case 0: return "Plate"
        case 1: return items[0].title
        case 2: return "\(items[0].title) and \(items[1].title)"
        default: return "\(items[0].title) and \(items.count - 1) more"
        }
    }

    private var isFull: Bool { items.count >= FoodLimits.plateFoods }

    private var isOutOfScansCardShown: Bool {
        if case .outOfScans = scanner.status { return true }
        return false
    }

    var body: some View {
        SheetScaffold(title: "Build a plate", closeLabel: "Cancel") {
            if items.isEmpty && scanner.status == .idle {
                note("Snap your plate and the Tavern lists what's on it, or add each food from USDA's food database. Check the amounts before you log.")
            } else if items.contains(where: { $0.photoLabel != nil }) {
                note("Amounts from a photo are a best guess. Check each one, and swap any food that's wrong.")
            }
            VStack(spacing: 10) {
                ForEach($items) { $item in
                    PlateItemRow(item: $item) {
                        openSearch(SearchRequest(replacing: item.id, query: item.title))
                    } onRemove: {
                        withAnimation(.snappy) { items.removeAll { $0.id == item.id } }
                    }
                }
            }
            if leftOff > 0 {
                Text("\(leftOff) more \(leftOff == 1 ? "food" : "foods") from the photo didn't fit. A plate holds \(FoodLimits.plateFoods).")
                    .font(.alegreyaSans(15))
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(.top, 10)
            }
            if scanner.status != .idle {
                ScanStatusCard(status: scanner.status) {
                    scanner.retry(with: store.food, onFound: addScanned)
                } onDismiss: {
                    withAnimation(.snappy) { scanner.reset() }
                }
                .padding(.top, items.isEmpty ? 0 : 10)
            }
            addButtons
                .padding(.top, 12)
            if let scansLeft = scanner.scansLeft, scansLeft <= 5, !isOutOfScansCardShown {
                Text(scansLeft == 0 ? "No photo scans left today. They come back over the next day."
                                    : "\(scansLeft) photo \(scansLeft == 1 ? "scan" : "scans") left today")
                    .font(.alegreyaSans(15))
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(.top, 8)
            }

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
        // A swipe down shouldn't throw away a plate or a photo being read; Cancel still does.
        .interactiveDismissDisabled(!items.isEmpty || scanner.isReading)
        .task {
            guard !didReadInitialPhoto, let initialPhoto else { return }
            didReadInitialPhoto = true
            readPhoto(initialPhoto)
        }
        .onDisappear { scanner.stopReading() }
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
            .disabled(items.isEmpty || isLogging || scanner.isReading)
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

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.alegreyaSans(16))
            .foregroundStyle(Theme.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 12)
    }

    /// Photo and search side by side, stacked when they don't fit (large text, small phones).
    private var addButtons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { photoButton; searchButton }
            VStack(spacing: 10) { photoButton; searchButton }
        }
    }

    private var photoButton: some View {
        MealPhotoButton(onPick: readPhoto)
            .disabled(isFull || scanner.isReading || scanner.scansLeft == 0)
    }

    private var searchButton: some View {
        Button { openSearch(SearchRequest()) } label: {
            Label(items.isEmpty ? "Search foods" : "Add a food", systemImage: "magnifyingglass")
        }
        .buttonStyle(.chunky(.wood, minHeight: 48, fontSize: 17))
        .disabled(isFull)
    }

    private func readPhoto(_ source: MealPhotoSource) {
        leftOff = 0
        withAnimation(.snappy) { scanner.read(source, with: store.food, onFound: addScanned) }
    }

    /// Adds what the plate reader found, as many as fit on the plate.
    private func addScanned(_ scan: PlateScan) {
        let found = Array(scan.items.prefix(FoodLimits.plateFoods - items.count))
        leftOff = scan.items.count - found.count
        photoMeal = items.isEmpty ? (scan.mealName, Set(found.map(\.id))) : nil
        withAnimation(.snappy) { items.append(contentsOf: found) }
        AccessibilityNotification.Announcement(
            "Found \(found.count) \(found.count == 1 ? "food" : "foods"). Check the amounts."
        ).post()
    }

    private func openSearch(_ request: SearchRequest) {
        UIApplication.shared.endEditing()  // or the grams keyboard comes back when the search closes
        search = request
    }

    private func add(_ food: Food, replacing id: PlateItem.ID?) {
        if let id, let index = items.firstIndex(where: { $0.id == id }) {
            items[index].food = food  // keeps the amount already set
            items[index].photoLabel = nil  // the photo's name described the food swapped out
            photoMeal = nil  // and so may the photo's meal name
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
                    Text(item.title)
                        .font(.alegreyaSans(18, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    if item.food.source == .estimate {
                        EstimateTag()
                            .padding(.vertical, 2)
                    } else if item.title != item.food.name {
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
                .accessibilityLabel("Options for \(item.title)")
            }
            GramsEditor(grams: $item.grams, portions: item.food.portions, range: FoodLimits.plateGrams)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.checkboxFill))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.outline, lineWidth: 2))
    }
}

/// Marks a food the plate reader estimated itself, because USDA had no close match.
private struct EstimateTag: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TagChip(label: "Estimate", systemImage: "sparkles", fill: Theme.gold.opacity(0.45), fontSize: 13)
            Text("No close USDA match. Use Swap food to look it up.")
                .font(.alegreyaSans(14))
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// What's happening with the last photo: being read, no food found, or failed.
private struct ScanStatusCard: View {
    let status: PlateScanner.Status
    let onRetry: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.alegreyaSans(17, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(.alegreyaSans(15))
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if case .failed(_, _, canRetry: true) = status {
                    Button("Try again", systemImage: "arrow.clockwise", action: onRetry)
                        .font(.alegreyaSans(16, weight: .bold))
                        .foregroundStyle(Theme.waxRed)
                        .frame(minHeight: 44)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if case .reading = status {
                ProgressView()
                    .tint(Theme.kicker)
                    .frame(width: 44, height: 44)
            } else {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.inkSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.checkboxFill))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.outline, lineWidth: 2))
        .accessibilityElement(children: .contain)
    }

    private var title: String {
        switch status {
        case .idle, .reading: "Reading your plate…"
        case .notFood: "No food found"
        case .failed: "Couldn't scan that photo"
        case .outOfScans: "No photo scans left today"
        }
    }

    private var detail: String {
        switch status {
        case .idle, .reading: "This takes a few seconds."
        case .notFood: "Try another photo of your meal, or search for foods."
        case .failed(let message, _, _), .outOfScans(let message): message
        }
    }

    private var isOutOfScans: Bool {
        if case .outOfScans = status { return true }
        return false
    }

    @ViewBuilder private var thumbnail: some View {
        let preview: UIImage? = switch status {
        case .reading(let image): image
        case .notFood(let image): image
        case .failed(_, let image, _): image
        case .idle, .outOfScans: nil
        }
        Group {
            if let preview {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: isOutOfScans ? "hourglass" : "photo")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.progressTrack.opacity(0.5))
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.outline, lineWidth: 2))
        .accessibilityHidden(true)
    }
}

#Preview {
    Text("Tavern")
        .sheet(isPresented: .constant(true)) { PlateSheet() }
        .environment(GameStore.preview)
}
