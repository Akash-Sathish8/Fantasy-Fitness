//
//  SettingsSheet.swift
//  Fantasy Fitness
//

import SwiftUI

/// Account and connection details. Reachable from Title and Guild Hall; editing
/// the profile is still to come.
struct SettingsSheet: View {
    /// Shown only once signed in (from the Guild Hall).
    var onLogOut: (() -> Void)? = nil

    @Environment(GameStore.self) private var store

    private var syncStatus: String {
        if store.isDemo { return "Demo mode" }
        if !store.isSignedIn { return "Not signed in" }
        if store.sync.isOffline { return "Offline" }
        return store.refreshError == nil ? "Connected" : "Couldn't refresh"
    }

    var body: some View {
        SheetScaffold(title: "Settings") {
            VStack(spacing: 0) {
                row("Profile", detail: store.isSignedIn ? store.player.displayName : "Not signed in",
                    systemImage: "person.fill")
                if let email = store.accountEmail {
                    row("Account", detail: email, systemImage: "envelope.fill")
                }
                row("Sync", detail: syncStatus, systemImage: "arrow.triangle.2.circlepath")
                if let summary = store.sync.queueSummary {
                    row("Queue", detail: summary, systemImage: "tray.and.arrow.up.fill")
                }
                if let lastSynced = store.sync.lastSyncedAt {
                    row("Last synced", detail: lastSynced.formatted(.relative(presentation: .named)),
                        systemImage: "clock.fill")
                }
                // All weights are stored in pounds (bodyweight_lb, weight_lb).
                row("Units", detail: "lb", systemImage: "scalemass.fill")
            }

            if let onLogOut {
                Button("Log out", action: onLogOut)
                    .buttonStyle(.chunky(.wood))
                    .padding(.top, 28)
            }
        }
        .presentationDetents([.medium])
    }

    private func row(_ title: String, detail: String, systemImage: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.cream)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Theme.kicker))
            Text(title)
                .font(.alegreyaSans(18, weight: .bold))
                .foregroundStyle(Theme.ink)
            Spacer()
            Text(detail)
                .font(.alegreyaSans(16))
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(minHeight: 56)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.inkSecondary.opacity(0.25)).frame(height: 1)
        }
    }
}

#Preview {
    Text("Title").sheet(isPresented: .constant(true)) { SettingsSheet(onLogOut: {}).environment(GameStore.preview) }
}
