//
//  ContentView.swift
//  Fantasy Fitness
//
//  Created by Ryan Ferguson on 9/30/26.
//

import SwiftUI

enum AppTab: Hashable {
    case guildHall, quests, character, dungeons, tavern
}

struct ContentView: View {
    let onLogOut: () -> Void

    @Environment(GameStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: AppTab = .guildHall

    var body: some View {
        Group {
            if store.hasData {
                tabs
            } else if case .failed(let message) = store.loadState {
                BoardStatusView(title: "Can't reach the guild", message: message, systemImage: "wifi.slash") {
                    Button("Try again") { Task { await store.load() } }
                        .buttonStyle(.chunky(.wax))
                    Button("Log out", action: onLogOut)
                        .buttonStyle(.chunky(.wood, minHeight: 48, fontSize: 17))
                }
            } else {
                BoardStatusView(loadingTitle: "Opening the guild hall…",
                                message: "Fetching your quests, gear and rations.")
            }
        }
        .task { if !store.hasData { await store.load() } }
        // Coming back to the app (often on a new day) uploads the queue and refreshes
        // Energy and quests.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.load() } }
        }
        // A workout that uploaded after the player moved on shows its rewards here.
        .fullScreenCover(item: Binding(
            get: { store.rewardReveal },
            set: { if $0 == nil, let id = store.rewardReveal?.id { store.sync.dismissReward(id) } }
        )) { reveal in
            LootRevealView(loot: reveal.loot) { store.sync.dismissReward(reveal.id) }
        }
        // Dark scheme keeps the glass tab bar and status bar dark over the wood board.
        .preferredColorScheme(.dark)
    }

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            Tab("Guild Hall", systemImage: "building.columns", value: .guildHall) {
                NavigationStack {
                    GuildHallView(onOpenQuests: { selectedTab = .quests }, onLogOut: onLogOut)
                }
            }
            Tab("Quests", systemImage: "scroll", value: .quests) {
                NavigationStack { QuestBoardView() }
            }
            Tab("Character", systemImage: "person.crop.square", value: .character) {
                NavigationStack { CharacterSheetView() }
            }
            Tab("Dungeons", systemImage: "map", value: .dungeons) {
                NavigationStack { DungeonMapView() }
            }
            Tab("Tavern", systemImage: "fork.knife", value: .tavern) {
                NavigationStack { TavernView() }
            }
        }
        .tint(Theme.gold)
    }
}

#Preview {
    ContentView(onLogOut: {})
        .environment(GameStore.preview)
}
