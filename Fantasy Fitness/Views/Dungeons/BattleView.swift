//
//  BattleView.swift
//  Fantasy Fitness
//
//  A dungeon fight, one turn at a time: the boss shows its next move, you choose Strike,
//  Heavy Blow, Guard or your class skill, aim attacks on the timing meter, then the boss
//  acts. Numbers and rules live in Services/BattleRules.swift, fight state in
//  BattleSession. The outcome goes to the server, which decides XP and loot.
//

import SwiftUI

struct BattleView: View {
    let dungeon: Dungeon
    let runID: UUID
    let onFinish: () -> Void

    private enum Claim: Equatable {
        case idle, claiming
        case failed(String)
    }

    @Environment(GameStore.self) private var store
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var session: BattleSession?
    @State private var claim = Claim.idle
    @State private var loot: LootDrop?
    @State private var confirmingFlee = false

    /// `session` is for previews; the fight normally starts from the player's current stats.
    init(dungeon: Dungeon, runID: UUID, session: BattleSession? = nil, onFinish: @escaping () -> Void) {
        self.dungeon = dungeon
        self.runID = runID
        self.onFinish = onFinish
        _session = State(initialValue: session)
    }

    var body: some View {
        Group {
            if let loot {
                LootRevealView(loot: loot, onCollect: onFinish)
            } else if let session {
                arena(session)
            } else {
                WoodBackground().ignoresSafeArea()
            }
        }
        .onAppear {
            if session == nil {
                session = BattleSession(profile: store.player, dungeon: dungeon, runID: runID)
            }
        }
    }

    // MARK: - Arena

    private func arena(_ session: BattleSession) -> some View {
        // Fills the screen and pins the controls to the bottom. Scrolls only when large text
        // makes it taller than the screen, starting at the bottom so the actions stay in reach.
        GeometryReader { proxy in
            ScrollView {
                arenaStack(session)
                    .padding(16)
                    .frame(minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .defaultScrollAnchor(.bottom)
            // Nothing scrolls under the status bar, which has no bar behind it here.
            .clipped()
        }
        .background(WoodBackground().ignoresSafeArea())
        .task(id: session.phase) {
            // Pause so the player sees their hit land before the boss answers.
            guard session.phase == .bossTurn else { return }
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { session.finishBossTurn() }
        }
        .onChange(of: session.phase, initial: true) { _, phase in
            // Unstructured so the report still goes out if the screen closes first.
            switch phase {
            case .won: Task { await claimVictory(holdingWin: true) }
            case .lost: Task { _ = await store.finishRun(runID, victory: false) }
            default: break
            }
        }
        .sensoryFeedback(trigger: session.hitOnBoss) { _, hit in
            hit?.kind == .critical ? .impact(weight: .heavy, intensity: 1) : nil
        }
        .sensoryFeedback(trigger: session.hitOnPlayer) { _, hit in
            switch hit?.kind {
            case .damage: .impact(weight: .medium)
            case .blocked: .impact(weight: .light)
            default: nil
            }
        }
        .sensoryFeedback(.success, trigger: session.phase == .won) { _, won in won }
        .confirmationDialog("Flee the dungeon?", isPresented: $confirmingFlee, titleVisibility: .visible) {
            Button("Flee", role: .destructive) {
                Task { _ = await store.finishRun(runID, victory: false) }
                onFinish()
            }
        } message: {
            Text("Your Energy is already spent, and fleeing counts as a loss.")
        }
    }

    private func arenaStack(_ session: BattleSession) -> some View {
        VStack(spacing: 0) {
            header(session)
            Spacer(minLength: 12)
            fighters(session)
            Spacer(minLength: 12)
            controls(session)
        }
    }

    /// Both cards and the log line.
    private func fighters(_ session: BattleSession) -> some View {
        VStack(spacing: 12) {
            combatant(name: session.boss.name, health: session.state.bossHealth, maxHealth: session.boss.maxHealth,
                      tint: Theme.waxRed, hit: session.hitOnBoss, shakes: session.bossShakes) {
                EmblemBadge(palette: .wax, size: 72, shadowOffset: 5) {
                    Image(systemName: dungeon.systemImage)
                }
            } footer: {
                // Kept in the layout when the fight ends, so the arena doesn't jump as the boss falls.
                bossIntent(session)
                    .opacity(session.isOver ? 0 : 1)
                    .accessibilityHidden(session.isOver)
            }

            Text("VS")
                .font(.pirata(26))
                .foregroundStyle(Theme.cream)
                .accessibilityHidden(true)

            combatant(name: session.player.name, health: session.state.playerHealth,
                      maxHealth: session.player.maxHealth, tint: Theme.progressGreen,
                      hit: session.hitOnPlayer, shakes: session.playerShakes) {
                ClassEmblem(guildClass: store.player.guildClass, size: 56)
            } footer: {
                FlowLayout(spacing: 8) {
                    TagChip(label: "\(session.player.attack) attack", systemImage: "bolt.fill", fontSize: 14)
                    TagChip(label: "\(session.player.defense) defense", systemImage: "shield.fill", fontSize: 14)
                }
            }

            // The old line fades out before the new one fades in, so two sentences never overlap.
            ZStack {
                Text(session.log)
                    .font(.alegreyaSans(17, weight: .medium))
                    .foregroundStyle(Theme.cream)
                    .multilineTextAlignment(.center)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                    .minimumScaleFactor(0.85)
                    .id(session.log)
                    .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.18).delay(0.1)),
                                            removal: .opacity.animation(.easeIn(duration: 0.1))))
            }
            .frame(maxWidth: .infinity, minHeight: 46)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.updatesFrequently)
        }
    }

    private func header(_ session: BattleSession) -> some View {
        HStack {
            WoodIconButton(systemImage: "xmark", accessibilityLabel: session.isOver ? "Close" : "Flee") {
                if session.isOver { onFinish() } else { confirmingFlee = true }
            }
            .disabled(claim == .claiming)
            Spacer()
            VStack(spacing: 0) {
                Text(dungeon.name)
                    .font(.pirata(30))
                    .foregroundStyle(Theme.gold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)
                Text("Turn \(session.state.turn)")
                    .font(.alegreyaSans(14, weight: .bold))
                    .foregroundStyle(Theme.cream.opacity(0.85))
                    .contentTransition(.numericText(value: Double(session.state.turn)))
            }
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
    }

    /// The boss's next move, so the player can answer it (guard a heavy swing, and so on).
    private func bossIntent(_ session: BattleSession) -> some View {
        FlowLayout(spacing: 8) {
            // Swapped like the log line: the old move fades out before the new one fades in.
            ZStack {
                TagChip(label: session.intentText, systemImage: session.state.intent.systemImage,
                        fill: session.state.intent == .heavySwing ? Theme.waxRed.opacity(0.22)
                            : Theme.scrollRoll.opacity(0.35),
                        fontSize: 15)
                    .id(session.intentText)
                    .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.18).delay(0.1)),
                                            removal: .opacity.animation(.easeIn(duration: 0.1))))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Next move: \(session.intentText)")
            if session.state.isEnraged {
                TagChip(label: "Enraged", systemImage: "flame.fill", fill: Theme.flameOuter.opacity(0.3), fontSize: 15)
            }
        }
    }

    private func combatant<Portrait: View, Footer: View>(
        name: String, health: Int, maxHealth: Int, tint: Color, hit: BattleSession.Hit?, shakes: Int,
        @ViewBuilder portrait: () -> Portrait, @ViewBuilder footer: () -> Footer
    ) -> some View {
        ParchmentCard(padding: 14) {
            HStack(spacing: 14) {
                portrait()
                VStack(alignment: .leading, spacing: 6) {
                    Text(name)
                        .font(.alegreya(20, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    ParchmentProgressBar(progress: Double(health) / Double(maxHealth), height: 14, tint: tint)
                    Text("\(health) / \(maxHealth) HP")
                        .font(.alegreyaSans(14, weight: .bold))
                        .foregroundStyle(Theme.inkSecondary)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(health)))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(name), \(health) of \(maxHealth) health")
            footer()
                .padding(.top, 10)
        }
        .overlay(alignment: .topTrailing) {
            if let hit {
                FloatingHit(hit: hit)
                    .id(hit.id)
                    .padding(.top, 8)
                    .padding(.trailing, 14)
            }
        }
        .keyframeAnimator(initialValue: 0.0, trigger: reduceMotion ? 0 : shakes) { content, offset in
            content.offset(x: offset)
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(-9, duration: 0.05)
                LinearKeyframe(8, duration: 0.07)
                LinearKeyframe(-5, duration: 0.07)
                LinearKeyframe(3, duration: 0.06)
                LinearKeyframe(0, duration: 0.06)
            }
        }
    }

    // MARK: - Controls

    /// The action buttons and the timing meter are both laid out, hidden, under the visible
    /// controls, so the area keeps one height and the cards don't bob when the meter appears.
    private func controls(_ session: BattleSession) -> some View {
        ZStack(alignment: .bottom) {
            actionGrid(session).hidden()
            TimingMeter.sizer.hidden()
            activeControls(session)
        }
    }

    @ViewBuilder
    private func activeControls(_ session: BattleSession) -> some View {
        switch session.phase {
        case .aiming(let action, let zones, let startedAt):
            TimingMeter(zones: zones, startedAt: startedAt, sweep: session.player.sweepDuration,
                        actionTitle: "\(action.title(for: session.player.skill))!",
                        systemImage: action.systemImage(for: session.player.skill)) { date in
                withAnimation(.snappy) { session.stopMeter(at: date) }
            }
        case .won:
            claimControls
        case .lost:
            Button("Return to the inn", action: onFinish)
                .buttonStyle(.chunky(.wood))
        case .choosing, .bossTurn:
            actionGrid(session)
                .disabled(session.phase != .choosing)
        }
    }

    @ViewBuilder
    private func actionGrid(_ session: BattleSession) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            // One column, so large labels get the full width.
            VStack(spacing: 12) {
                ForEach([PlayerAction.strike, .heavyBlow, .defend, .skill], id: \.self) { action in
                    actionButton(action, session: session)
                }
            }
        } else {
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    actionButton(.strike, session: session)
                    actionButton(.heavyBlow, session: session)
                }
                GridRow {
                    actionButton(.defend, session: session)
                    actionButton(.skill, session: session)
                }
            }
        }
    }

    private func actionButton(_ action: PlayerAction, session: BattleSession) -> some View {
        let skillReady = session.state.isSkillReady
        let detail = switch action {
        case .strike: "Steady hit"
        case .heavyBlow: "Big hit, can miss"
        case .defend: "Blocks most damage"
        case .skill: skillReady ? "Ready" : "Ready in \(session.skillStatus)"
        }
        let palette: CartoonPalette = switch action {
        case .strike, .heavyBlow: .wax
        case .defend: .wood
        case .skill: skillReady ? .gold : .wood
        }
        return Button {
            withAnimation(.snappy) { session.choose(action, usingMeter: !voiceOverEnabled) }
        } label: {
            VStack(spacing: 1) {
                Label(action.title(for: session.player.skill), systemImage: action.systemImage(for: session.player.skill))
                    .font(.alegreya(18, weight: .heavy))
                Text(detail)
                    .font(.alegreyaSans(13, weight: .bold))
                    .opacity(0.85)
                    .contentTransition(.numericText(countsDown: true))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.vertical, 6)
        }
        .buttonStyle(.chunky(palette, minHeight: 60))
        .disabled(action == .skill && !skillReady)
        .accessibilityHint(action == .skill ? session.player.skill.summary : detail)
    }

    @ViewBuilder
    private var claimControls: some View {
        if case .failed(let message) = claim {
            VStack(spacing: 10) {
                Text("Couldn't claim your spoils. \(message) If it went through, the loot is already in your inventory.")
                    .font(.alegreyaSans(16, weight: .medium))
                    .foregroundStyle(Theme.cream)
                    .multilineTextAlignment(.center)
                Button("Try again") { Task { await claimVictory() } }
                    .buttonStyle(.chunky(.wax))
                Button("Leave", action: onFinish)
                    .buttonStyle(.chunky(.wood, minHeight: 48, fontSize: 17))
            }
        } else {
            ProgressView("Claiming spoils…")
                .tint(Theme.gold)
                .foregroundStyle(Theme.cream)
                .frame(minHeight: 54)
        }
    }

    /// `holdingWin` keeps the winning blow on screen for a moment, even when the server
    /// answers instantly, so the chest doesn't replace the arena before the boss falls.
    private func claimVictory(holdingWin: Bool = false) async {
        guard claim != .claiming else { return }
        claim = .claiming
        let revealAt = ContinuousClock.now + .seconds(holdingWin ? 1.4 : 0)
        if let drop = await store.finishRun(runID, victory: true) {
            try? await Task.sleep(until: revealAt, clock: .continuous)
            withAnimation(.snappy) { loot = drop }
        } else {
            // Shown here, so RootView doesn't repeat it as an alert once the battle closes.
            let message = store.errorMessage ?? "Check your connection."
            store.errorMessage = nil
            claim = .failed(message)
        }
    }
}

/// A damage or heal number that floats up from a card and fades.
private struct FloatingHit: View {
    let hit: BattleSession.Hit

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isRising = false

    var body: some View {
        Text(hit.text)
            .font(.alegreya(hit.kind == .critical ? 30 : 24, weight: .heavy))
            .foregroundStyle(color)
            // Criticals get the cartoon outline so the gold reads on parchment.
            .shadow(color: hit.kind == .critical ? Theme.outline : Theme.cream, radius: 0, x: 1.5, y: 2)
            .scaleEffect(hit.kind == .critical && !isRising ? 1.25 : 1)
            .offset(y: isRising && !reduceMotion ? -30 : 0)
            .opacity(isRising ? 0 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: 0.9).delay(0.25)) { isRising = true }
            }
            .accessibilityHidden(true)
    }

    private var color: Color {
        switch hit.kind {
        case .critical: Theme.rarityLegendary
        case .damage, .glancing: Theme.waxRed
        case .blocked: Theme.sapphire
        case .heal: Theme.positiveText
        case .miss, .dodge: Theme.inkSecondary
        }
    }
}

// MARK: - Labels

extension PlayerAction {
    func title(for skill: ClassSkill) -> String {
        switch self {
        case .strike: "Strike"
        case .heavyBlow: "Heavy Blow"
        case .defend: "Guard"
        case .skill: skill.name
        }
    }

    func systemImage(for skill: ClassSkill) -> String {
        switch self {
        case .strike: "bolt.fill"
        case .heavyBlow: "hammer.fill"
        case .defend: "shield.fill"
        case .skill: skill.systemImage
        }
    }
}

extension ClassSkill {
    var systemImage: String {
        switch self {
        case .cleave: "burst.fill"
        case .volley: "scope"
        case .flurry: "wind"
        case .smite: "sun.max.fill"
        }
    }
}

extension BossMove {
    var systemImage: String {
        switch self {
        case .swipe: "arrow.right"
        case .heavySwing: "exclamationmark.triangle.fill"
        case .brace: "shield.lefthalf.filled"
        }
    }
}

#Preview("Start") {
    BattleView(dungeon: Dungeon.sampleMap[1], runID: UUID(), session: .preview(), onFinish: {})
        .environment(GameStore.preview)
}

#Preview("Three turns in") {
    BattleView(dungeon: Dungeon.sampleMap[1], runID: UUID(), session: .preview(turns: 3), onFinish: {})
        .environment(GameStore.preview)
}
