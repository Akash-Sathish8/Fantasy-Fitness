//
//  SleepCheckButton.swift
//  Fantasy Fitness
//

import SwiftUI

/// Checkbox for "I slept 7+ hours last night". Asks once before checking, because a
/// check-in can't be taken back (it earns Energy on the server).
struct SleepCheckButton: View {
    var label = "Slept \(Recovery.wellRestedHours.formatted())+ h"

    @Environment(GameStore.self) private var store
    @State private var isConfirming = false

    private var isChecked: Bool { store.sleep.isWellRested }

    var body: some View {
        Button { if !isChecked { isConfirming = true } } label: {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isChecked ? Theme.progressGreen : Theme.checkboxFill)
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(Theme.outline, lineWidth: 3)
                    if isChecked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(Theme.cream)
                    }
                }
                .frame(width: 28, height: 28)
                Text(label)
                    .font(.alegreyaSans(15, weight: .bold))
                    .foregroundStyle(isChecked ? Theme.positiveText : Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Slept \(Recovery.wellRestedHours.formatted()) or more hours last night")
        .accessibilityValue(isChecked ? "Checked" : "Not checked")
        .confirmationDialog("Did you sleep \(Recovery.wellRestedHours.formatted())+ hours last night?",
                            isPresented: $isConfirming, titleVisibility: .visible) {
            Button("Yes, I slept \(Recovery.wellRestedHours.formatted())+ hours") {
                do {
                    try withAnimation(.snappy) { try store.sleep.checkIn() }
                } catch {
                    store.errorMessage = "Couldn't save that on this device. \(error.localizedDescription)"
                }
            }
            Button("Not yet", role: .cancel) {}
        } message: {
            Text("Checking in earns Well-Rested and 1 Energy. It can't be undone.")
        }
    }
}

#Preview {
    SleepCheckButton()
        .padding()
        .background(Theme.parchment)
        .environment(GameStore(client: nil))
}
