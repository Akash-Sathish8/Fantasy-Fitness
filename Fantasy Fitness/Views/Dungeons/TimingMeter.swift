//
//  TimingMeter.swift
//  Fantasy Fitness
//
//  The aim step of an attack: a brass marker sweeps across a parchment bar and the player
//  taps to stop it. Inside the gold zone is a critical hit, inside the green zone a normal
//  hit, outside a glancing blow. The marker's position is worked out from the start time
//  (like RestTimer's stored end time), so the drawing and the score always agree.
//

import SwiftUI

struct TimingMeter: View {
    let zones: MeterZones
    let startedAt: Date
    let sweep: TimeInterval
    let actionTitle: String
    let systemImage: String
    var isPaused = false
    let onStop: (Date) -> Void

    private let barHeight: CGFloat = 34

    /// A still, hidden copy that reserves the meter's height while the buttons show.
    static var sizer: TimingMeter {
        TimingMeter(zones: MeterZones(hitStart: 0, hitWidth: 0, goldStart: 0, goldWidth: 0), startedAt: .distantPast,
                    sweep: 1, actionTitle: "Heavy Blow!", systemImage: "hammer.fill", isPaused: true, onStop: { _ in })
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                legend("Gold: critical", color: Theme.gold)
                legend("Green: hit", color: Theme.progressGreen)
            }
            .frame(maxWidth: .infinity)

            TimelineView(.animation(minimumInterval: nil, paused: isPaused)) { context in
                let position = MeterZones.markerPosition(after: context.date.timeIntervalSince(startedAt),
                                                         sweep: sweep)
                GeometryReader { proxy in
                    let width = proxy.size.width
                    ZStack(alignment: .leading) {
                        bar(width: width)
                        marker
                            .offset(x: width * position - 9)
                    }
                }
            }
            .frame(height: barHeight + 18)
            .contentShape(Rectangle())
            .onTapGesture { onStop(.now) }
            .accessibilityHidden(true)

            Button { onStop(.now) } label: {
                Label(actionTitle, systemImage: systemImage)
            }
            .buttonStyle(.chunky(.wax, minHeight: 58, fontSize: 21))
        }
    }

    private func bar(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Theme.progressTrack)
            Rectangle()
                .fill(Theme.progressGreen.opacity(0.75))
                .frame(width: width * zones.hitWidth)
                .offset(x: width * zones.hitStart)
            Rectangle()
                .fill(Theme.gold)
                .frame(width: width * zones.goldWidth)
                .offset(x: width * zones.goldStart)
        }
        .frame(height: barHeight)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Theme.outline, lineWidth: 3))
        .frame(maxHeight: .infinity)
    }

    /// Brass pointer that sticks out above and below the bar.
    private var marker: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Theme.brass)
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.outline, lineWidth: 2.5))
            .frame(width: 18, height: barHeight + 18)
    }

    private func legend(_ text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .overlay(Circle().strokeBorder(Theme.outline, lineWidth: 2))
                .frame(width: 14, height: 14)
            Text(text)
                .font(.alegreyaSans(15, weight: .bold))
                .foregroundStyle(Theme.cream)
        }
    }
}

#Preview {
    TimingMeter(zones: MeterZones(hitStart: 0.2, hitWidth: 0.5, goldStart: 0.4, goldWidth: 0.12),
                startedAt: .now, sweep: 1.6, actionTitle: "Strike!", systemImage: "bolt.fill", onStop: { _ in })
        .padding(16)
        .background(WoodBackground())
}
