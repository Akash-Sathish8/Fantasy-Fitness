//
//  BoardStatus.swift
//  Fantasy Fitness
//
//  Full-screen loading / error boards and a slim banner, used while player data is
//  loading, when it can't be reached, or when the app is running on demo data.
//

import SwiftUI

/// Wood board with a parchment note in the middle: a spinner while loading, or a
/// message and actions when something went wrong.
struct BoardStatusView<Actions: View>: View {
    let title: String
    let message: String
    var systemImage = "hourglass"
    var isLoading = false
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack {
            Spacer()
            PinnedNote {
                VStack(spacing: 14) {
                    if isLoading {
                        ProgressView()
                            .controlSize(.large)
                            .tint(Theme.kicker)
                    } else {
                        EmblemBadge(palette: .wax, size: 56) {
                            Image(systemName: systemImage)
                        }
                    }
                    Text(title)
                        .font(.alegreya(24, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.center)
                    Text(message)
                        .font(.alegreyaSans(16))
                        .foregroundStyle(Theme.inkSecondary)
                        .multilineTextAlignment(.center)
                    actions
                }
                .frame(maxWidth: .infinity)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WoodBackground())
        .accessibilityElement(children: .contain)
    }
}

extension BoardStatusView where Actions == EmptyView {
    /// Loading board with no actions.
    init(loadingTitle: String, message: String) {
        self.init(title: loadingTitle, message: message, isLoading: true) { EmptyView() }
    }
}

/// Slim notice pinned to the top of the board (stale data, demo mode).
struct StatusBanner: View {
    let message: String
    var systemImage = "exclamationmark.triangle.fill"
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.gold)
            Text(message)
                .font(.alegreyaSans(15, weight: .bold))
                .foregroundStyle(Theme.cream)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.alegreyaSans(15, weight: .bold))
                    .foregroundStyle(Theme.gold)
                    .frame(minHeight: 44)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .cartoonBackground(RoundedRectangle(cornerRadius: 12), fill: Theme.darkerWood,
                           outline: Theme.darkestWood, shadowOffset: 3)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Loading") {
    BoardStatusView(loadingTitle: "Opening the guild hall…", message: "Fetching your quests and gear.")
}

#Preview("Error") {
    BoardStatusView(title: "Can't reach the guild", message: "The Internet connection appears to be offline.",
                    systemImage: "wifi.slash") {
        Button("Try again") {}.buttonStyle(.chunky(.wax))
    }
}
