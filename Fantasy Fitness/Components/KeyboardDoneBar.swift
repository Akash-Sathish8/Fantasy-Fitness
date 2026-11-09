//
//  KeyboardDoneBar.swift
//  Fantasy Fitness
//

import SwiftUI

/// A Done button that sits on top of the keyboard while it's up. The number pad has no
/// return key, and SwiftUI's keyboard toolbar doesn't appear in sheets without a
/// navigation stack, so sheets with number fields show this instead.
struct KeyboardDoneBar: View {
    var body: some View {
        HStack {
            Spacer()
            Button { UIApplication.shared.endEditing() } label: {
                Text("Done")
                    .font(.alegreya(17, weight: .heavy))
                    .foregroundStyle(Theme.waxRed)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .background(
            Theme.noteParchment
                .overlay(alignment: .top) { Rectangle().fill(Theme.outline).frame(height: 2) }
                .ignoresSafeArea()
        )
    }
}

extension View {
    /// Keeps `isUp` in step with the keyboard.
    func tracksKeyboard(_ isUp: Binding<Bool>) -> some View {
        onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isUp.wrappedValue = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isUp.wrappedValue = false
        }
    }
}

extension UIApplication {
    /// Closes the keyboard, whichever field has it.
    func endEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
