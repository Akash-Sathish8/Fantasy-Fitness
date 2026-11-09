//
//  FoodSearchSheet.swift
//  Fantasy Fitness
//

import SwiftUI

/// What the player picked in the food search.
enum FoodPick {
    case food(Food)
    /// A name typed in without nutrition (recipes only); it isn't counted toward macros.
    case textOnly(String)
}

/// Searches USDA's food database (through `store.food`) and returns one pick.
/// Used by Build a plate and the recipe creator.
struct FoodSearchSheet: View {
    var initialQuery = ""
    /// Offers adding the typed name without nutrition.
    var allowsTextOnly = false
    let onPick: (FoodPick) -> Void

    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [Food] = []
    /// The query `results` answer. While the player types something new they're dimmed.
    @State private var resultsQuery = ""
    @State private var phase = Phase.idle
    @State private var attempt = 0
    @FocusState private var isFieldFocused: Bool

    private enum Phase: Equatable {
        case idle, searching, done
        case failed(String)
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var resultsAreStale: Bool { resultsQuery != trimmedQuery }

    var body: some View {
        SheetScaffold(title: "Find a food", closeLabel: "Cancel") {
            searchField
            status
                .padding(.top, 14)
            VStack(spacing: 8) {
                ForEach(results) { food in
                    FoodResultRow(food: food) { pick(.food(food)) }
                        .opacity(resultsAreStale ? 0.45 : 1)
                        .disabled(resultsAreStale)
                }
                if allowsTextOnly, !trimmedQuery.isEmpty {
                    textOnlyRow
                }
            }
            .padding(.top, 10)
        }
        .presentationDetents([.large])
        .scrollDismissesKeyboard(.immediately)  // dragging the results shows more of them
        .onAppear {
            query = initialQuery
            isFieldFocused = initialQuery.isEmpty
        }
        // Waits for a pause in typing, and cancels a search the next keystroke replaces.
        .task(id: "\(attempt)|\(trimmedQuery)") { await search() }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.inkSecondary)
            TextField("Food", text: $query, prompt: Text("Chicken breast, rice, banana…"))
                .font(.alegreyaSans(18, weight: .medium))
                .foregroundStyle(Theme.ink)
                .tint(Theme.waxRed)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .focused($isFieldFocused)
            if phase == .searching {
                ProgressView().tint(Theme.inkSecondary)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 50)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.checkboxFill))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.outline, lineWidth: 2.5))
    }

    @ViewBuilder private var status: some View {
        switch phase {
        case .idle:
            note("Search USDA's food database. Values are per 100 g; you set the amount next.")
        case .searching where results.isEmpty:
            note("Searching…")
        case .done where results.isEmpty:
            note("No matches. Try a simpler word, like \"rice\" or \"chicken\".")
        case .failed(let message):
            VStack(alignment: .leading, spacing: 10) {
                note(message)
                Button("Try again") { attempt += 1 }
                    .buttonStyle(.chunky(.wood, minHeight: 44, fullWidth: false, fontSize: 17))
            }
        default:
            EmptyView()
        }
    }

    private var textOnlyRow: some View {
        Button { pick(.textOnly(trimmedQuery)) } label: {
            HStack(spacing: 12) {
                Image(systemName: "text.badge.plus")
                    .font(.system(size: 18, weight: .bold))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add \"\(trimmedQuery)\" without nutrition")
                        .font(.alegreyaSans(17, weight: .bold))
                        .multilineTextAlignment(.leading)
                    Text("Saved in the recipe, but not counted in its macros.")
                        .font(.alegreyaSans(14))
                        .foregroundStyle(Theme.inkSecondary)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.outline.opacity(0.6),
                                                                        style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.alegreyaSans(16))
            .foregroundStyle(Theme.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func search() async {
        let query = trimmedQuery
        guard query.count >= 2 else {
            results = []
            resultsQuery = query
            phase = .idle
            return
        }
        do {
            try await Task.sleep(for: .milliseconds(350))
            phase = .searching
            results = try await store.food.search(query)
            resultsQuery = query
            phase = .done
        } catch where error is CancellationError || ServerError.isCancelled(error) {
            // Replaced by a newer search.
        } catch {
            results = []
            resultsQuery = query
            phase = .failed(ServerError.message(for: error))
        }
    }

    private func pick(_ choice: FoodPick) {
        onPick(choice)
        dismiss()
    }
}

/// One search result: name, energy and protein per 100 g, and where the data comes from.
private struct FoodResultRow: View {
    let food: Food
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(food.name)
                        .font(.alegreyaSans(17, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                    Text("\(Int(food.per100g.kcal.rounded()))\u{00A0}kcal · \(food.per100g.protein.formatted(.number.precision(.fractionLength(0...1))))\u{00A0}g protein per 100\u{00A0}g")
                        .font(.alegreyaSans(15))
                        .foregroundStyle(Theme.inkSecondary)
                    Text(food.detail)
                        .font(.alegreyaSans(13, weight: .bold))
                        .foregroundStyle(Theme.kicker)
                }
                Spacer(minLength: 8)
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.progressGreen)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.checkboxFill))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.outline, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Picks this food")
    }
}

/// How much of a food: type grams, step them with − and +, or tap one of USDA's
/// household portions ("1 medium breast · 120 g").
///
/// The field always shows the amount that will be saved: typing past a limit snaps to it,
/// and − / + / portions update the field even while it's being edited.
struct GramsEditor: View {
    @Binding var grams: Double
    let portions: [Portion]
    let range: ClosedRange<Double>

    /// Typed text, applied as the player types (the decimal pad has no return key).
    @State private var text = ""
    @State private var selection: TextSelection?
    @FocusState private var isTyping: Bool
    @ScaledMetric(relativeTo: .title3) private var fieldWidth: CGFloat = 70

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                stepButton("minus", label: "Fewer grams") { grams = max(range.lowerBound, stepped(down: true)) }
                    .disabled(grams <= range.lowerBound)
                HStack(spacing: 4) {
                    TextField("Grams", text: $text, selection: $selection)
                        .keyboardType(.decimalPad)
                        .focused($isTyping)
                        .multilineTextAlignment(.trailing)
                        .font(.alegreyaSans(20, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .tint(Theme.waxRed)
                        .frame(width: min(fieldWidth, 120))
                        .accessibilityLabel("Grams")
                    Text("g")
                        .font(.alegreyaSans(18, weight: .bold))
                        .foregroundStyle(Theme.inkSecondary)
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.parchment))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.outline, lineWidth: 2))
                .contentShape(Rectangle())
                .onTapGesture { isTyping = true }
                stepButton("plus", label: "More grams") { grams = min(range.upperBound, stepped(down: false)) }
                    .disabled(grams >= range.upperBound)
            }
            if !portions.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(portions, id: \.self) { portion in
                            let isChosen = portion.grams == grams
                            Button { grams = clamped(portion.grams) } label: {
                                TagChip(label: "\(portion.label) · \(FoodMath.gramsText(portion.grams))",
                                        fill: isChosen ? Theme.gold : Theme.scrollRoll.opacity(0.35),
                                        fontSize: 14)
                                    .lineLimit(1)
                                    .frame(minHeight: 44)  // the chip is drawn smaller; the tap area isn't
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(isChosen ? .isSelected : [])
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .onAppear { text = Self.format(grams) }
        .onChange(of: text) { _, typed in
            let cleaned = Self.sanitized(typed)
            guard cleaned == typed else { text = cleaned; return }  // runs again with the clean text
            guard let value = Self.value(of: cleaned) else { return }  // empty or "12.": keep the last amount
            let allowed = clamped(value)
            if allowed != value { text = Self.format(allowed) }  // typed past a limit: show the limit
            if allowed != grams { grams = allowed }
        }
        .onChange(of: grams) { _, value in
            if Self.value(of: text) != value { text = Self.format(value) }
        }
        .onChange(of: isTyping) { _, typing in
            if typing {
                // Select the amount, so typing replaces it instead of adding digits to it.
                selection = TextSelection(range: text.startIndex..<text.endIndex)
            } else {
                text = Self.format(grams)
            }
        }
    }

    /// Digits and one decimal separator, at most 4 digits before it and 1 after. Pasted text
    /// ("nan", "1e9", "½ cup") never gets through, and other numeral systems become 0–9.
    private static func sanitized(_ typed: String) -> String {
        var whole = "", fraction = "", hasSeparator = false
        for character in typed {
            if let digit = character.wholeNumberValue, (0...9).contains(digit) {
                if hasSeparator {
                    if fraction.isEmpty { fraction.append(String(digit)) }
                } else if whole.count < 4 {
                    whole.append(String(digit))
                }
            } else if !hasSeparator, [".", ",", "٫"].contains(character) {
                hasSeparator = true
            }
        }
        return hasSeparator ? whole + decimalSeparator + fraction : whole
    }

    private static func value(of text: String) -> Double? {
        guard text.contains(where: \.isNumber) else { return nil }
        return Double(text.replacingOccurrences(of: decimalSeparator, with: "."))
    }

    /// "120" or "13.5" (with the region's separator), always with the digits 0–9.
    private static func format(_ grams: Double) -> String {
        let tenths = Int((grams * 10).rounded())
        return tenths % 10 == 0 ? "\(tenths / 10)" : "\(tenths / 10)\(decimalSeparator)\(tenths % 10)"
    }

    private static var decimalSeparator: String {
        Locale.current.decimalSeparator == "," ? "," : "."
    }

    private func stepButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .heavy))
                .frame(width: 20, height: 44)
        }
        .buttonStyle(.chunky(.wood, minHeight: 44, fullWidth: false, fontSize: 17))
        .accessibilityLabel(label)
    }

    /// 1 g steps for small amounts (oil, butter), 10 g steps otherwise, landing on round numbers.
    private func stepped(down: Bool) -> Double {
        let step: Double = (down ? grams <= 30 : grams < 30) ? 1 : 10
        return down ? ((grams / step).rounded(.up) - 1) * step : ((grams / step).rounded(.down) + 1) * step
    }

    private func clamped(_ value: Double) -> Double {
        let rounded = (value * 10).rounded() / 10
        return min(max(rounded, range.lowerBound), range.upperBound)
    }
}

#Preview("Search") {
    Text("Tavern")
        .sheet(isPresented: .constant(true)) {
            FoodSearchSheet(initialQuery: "chicken", allowsTextOnly: true) { _ in }
                .environment(GameStore.preview)
        }
}
