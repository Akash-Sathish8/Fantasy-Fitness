//
//  Fantasy_FitnessApp.swift
//  Fantasy Fitness
//
//  Created by Ryan Ferguson on 9/30/26.
//

import SwiftUI

@main
struct Fantasy_FitnessApp: App {
    @State private var store = GameStore()

    init() {
        Theme.registerFonts()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .background(TextSizeCap())
        }
    }
}

/// Text grows up to the largest standard size, not the accessibility sizes above it, which
/// break the board-and-parchment layouts. It's applied to the whole window scene, so sheets
/// and full-screen covers get it too (SwiftUI's `.dynamicTypeSize` doesn't reach into
/// sheets), and it follows the player's setting below the limit.
private struct TextSizeCap: UIViewRepresentable {
    static let largest = UIContentSizeCategory.extraExtraExtraLarge

    func makeUIView(context: Context) -> CappingView { CappingView() }
    func updateUIView(_ uiView: CappingView, context: Context) {}

    final class CappingView: UIView {
        private var observer: NSObjectProtocol?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            applyCap()
            guard observer == nil, window != nil else { return }
            observer = NotificationCenter.default.addObserver(
                forName: UIContentSizeCategory.didChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.applyCap() }
            }
        }

        private func applyCap() {
            guard let scene = window?.windowScene else { return }
            // The app's setting is the player's choice; the scene's traits are what we override.
            if UIApplication.shared.preferredContentSizeCategory > TextSizeCap.largest {
                scene.traitOverrides.preferredContentSizeCategory = TextSizeCap.largest
            } else {
                scene.traitOverrides.remove(UITraitPreferredContentSizeCategory.self)
            }
        }
    }
}
