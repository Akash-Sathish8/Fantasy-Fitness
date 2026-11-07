//
//  SleepService.swift
//  Fantasy Fitness
//
//  The "Rest at the inn" check-in. Until HealthKit is connected, the player ticks a
//  box when they believe they slept 7+ hours last night. The check is saved on the
//  device and uploaded by SyncService; the server records the night and decides the
//  Energy, Vitality and quest progress it earns.
//

import Foundation
import Observation

@Observable
final class SleepService {
    /// Hours slept last night, from the server or a check-in waiting to upload.
    private(set) var lastNightHours: Double?

    @ObservationIgnored private let local: LocalStore
    @ObservationIgnored private let sync: SyncService
    @ObservationIgnored private var userID: UUID?
    @ObservationIgnored private var isDemo = false
    @ObservationIgnored private var serverLastSleep: SleepLogRow?

    init(local: LocalStore, sync: SyncService) {
        self.local = local
        self.sync = sync
    }

    var isWellRested: Bool { (lastNightHours ?? 0) >= Recovery.wellRestedHours }

    /// Switches to a player, or to demo mode (in memory only, starts unchecked).
    func setUser(_ user: UUID?, isDemo: Bool = false) {
        userID = isDemo ? nil : user
        self.isDemo = isDemo
        serverLastSleep = nil
        recompute()
    }

    /// Call with each fresh snapshot.
    func apply(_ lastSleep: SleepLogRow?) {
        serverLastSleep = lastSleep
        recompute()
    }

    /// Records "slept 7+ hours last night". It can't be taken back; the server pays
    /// out Energy for it once it arrives.
    func checkIn() throws {
        guard !isWellRested else { return }
        if isDemo {
            lastNightHours = Recovery.wellRestedHours
            return
        }
        guard let userID else { return }
        try local.addSleep(LocalSleep(userID: userID, nightOf: LocalDate.yesterday()))
        sync.queueChanged()
        recompute()
        sync.requestSync()
    }

    private func recompute() {
        let lastNight = LocalDate.yesterday()
        let server = serverLastSleep.flatMap { $0.nightOf >= lastNight ? $0.hours : nil }
        let checkedIn = userID.map { local.sleeps(for: $0) }?.contains { $0.nightOf >= lastNight } ?? false
        let pending = checkedIn ? Recovery.wellRestedHours : nil
        lastNightHours = [server, pending].compactMap { $0 }.max()
    }
}
