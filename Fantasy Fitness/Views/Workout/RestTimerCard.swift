//
//  RestTimerCard.swift
//  Fantasy Fitness
//

import SwiftUI

/// Interactive rest countdown shown after a set is logged: ring, time left,
/// −15 s / pause / +30 s / skip, and a buzz when rest is over.
struct RestTimerCard: View {
    let timer: RestTimer

    /// Bumped when a rest finishes, to play the haptic.
    @State private var finishedCount = 0

    var body: some View {
        ParchmentCard(padding: 16) {
            if timer.isActive {
                activeTimer
            } else {
                presets
            }
        }
        // Wakes once at the end of the rest rather than polling.
        .task(id: timer.endDate) {
            guard let endDate = timer.endDate else { return }
            try? await Task.sleep(for: .seconds(max(endDate.timeIntervalSinceNow, 0)))
            guard !Task.isCancelled, timer.endDate == endDate else { return }
            finishedCount += 1
        }
        .sensoryFeedback(.warning, trigger: finishedCount)
    }

    private var activeTimer: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let remaining = timer.remaining(at: context.date)
            let isOver = remaining <= 0 && !timer.isPaused
            HStack(spacing: 18) {
                ZStack {
                    Circle()
                        .stroke(Theme.progressTrack, lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: timer.fractionRemaining(at: context.date))
                        .stroke(isOver ? Theme.progressGreen : Theme.waxRed,
                                style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.25), value: remaining)
                    Circle()
                        .strokeBorder(Theme.outline, lineWidth: 2.5)
                        .padding(-6)
                    Text(isOver ? "Go!" : Self.clock(remaining))
                        .font(.alegreyaSans(26, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                }
                .frame(width: 104, height: 104)
                .padding(6)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(isOver ? "Rest over" : "Rest, \(Int(remaining.rounded(.up))) seconds left")

                VStack(alignment: .leading, spacing: 10) {
                    KickerText(isOver ? "Rest over" : timer.isPaused ? "Paused" : "Resting")
                    Text(isOver ? "Time for your next set." : "Catch your breath.")
                        .font(.alegreyaSans(16, weight: .medium))
                        .foregroundStyle(Theme.inkSecondary)
                    HStack(spacing: 8) {
                        timerButton("−15", label: "Remove 15 seconds") { timer.adjust(by: -15) }
                            .disabled(isOver)
                        timerButton(timer.isPaused ? "play.fill" : "pause.fill",
                                    label: timer.isPaused ? "Resume" : "Pause", isSymbol: true) { timer.togglePause() }
                            .disabled(isOver)
                        timerButton("+30", label: "Add 30 seconds") { timer.adjust(by: 30) }
                            .disabled(isOver)
                        timerButton("xmark", label: isOver ? "Dismiss timer" : "Skip rest", isSymbol: true) { timer.stop() }
                    }
                }
            }
        }
    }

    /// Rest length picker, shown before the first set and between rests.
    private var presets: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "timer")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.kicker)
                Text("Rest between sets")
                    .font(.alegreyaSans(16, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text("Starts when you log a set")
                    .font(.alegreyaSans(13))
                    .foregroundStyle(Theme.inkSecondary)
            }
            HStack(spacing: 8) {
                ForEach(RestTimer.presets, id: \.self) { seconds in
                    let isSelected = timer.duration == seconds
                    Button(Self.clock(seconds)) { timer.duration = seconds }
                        .font(.alegreyaSans(16, weight: .bold))
                        .foregroundStyle(isSelected ? Theme.ink : Theme.inkSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Capsule().fill(isSelected ? Theme.gold : Theme.checkboxFill))
                        .overlay(Capsule().strokeBorder(Theme.outline, lineWidth: isSelected ? 2.5 : 1.5))
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }

    private func timerButton(_ title: String, label: String, isSymbol: Bool = false,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if isSymbol {
                    Image(systemName: title).font(.system(size: 14, weight: .heavy))
                } else {
                    Text(title).font(.alegreyaSans(15, weight: .bold))
                }
            }
            .foregroundStyle(Theme.cream)
            .frame(width: 44, height: 44)
            .cartoonBackground(Circle(), fill: Theme.darkWood, outline: Theme.darkestWood, shadowOffset: 2)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Sinks a little when pressed; for small icon buttons that bring their own surface.
private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(y: configuration.isPressed ? 2 : 0)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
