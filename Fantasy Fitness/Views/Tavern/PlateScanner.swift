//
//  PlateScanner.swift
//  Fantasy Fitness
//

import SwiftUI

/// Reads meal photos for `PlateSheet`: prepares each photo, sends it to the plate reader
/// (`FoodService.scan`) and keeps what the sheet shows meanwhile. The sheet adds the foods.
/// Errors show inside the sheet rather than in the global alert, which sits behind sheets.
@Observable
final class PlateScanner {
    enum Status: Equatable {
        case idle
        /// Opening or reading a photo; the preview appears once it's open.
        case reading(UIImage?)
        /// The plate reader found no food in the photo.
        case notFood(UIImage)
        /// Couldn't read it. `canRetry` when sending the same photo again could work.
        case failed(String, preview: UIImage?, canRetry: Bool)
        /// Today's scans are used up (the server's message says how many there are).
        case outOfScans(String)
    }

    private(set) var status: Status = .idle
    /// Photo scans left today, once the server has said.
    private(set) var scansLeft: Int?

    @ObservationIgnored private var photo: MealPhoto?
    @ObservationIgnored private var job: Task<Void, Never>?

    var isReading: Bool {
        if case .reading = status { return true }
        return false
    }

    func read(_ source: MealPhotoSource, with food: FoodService, onFound: @escaping (PlateScan) -> Void) {
        job?.cancel()
        photo = nil
        status = .reading(nil)
        job = Task {
            guard let photo = await MealPhoto.prepare(source) else {
                if !Task.isCancelled {
                    status = .failed("That photo couldn't be opened. Try another one.", preview: nil, canRetry: false)
                }
                return
            }
            guard !Task.isCancelled else { return }
            self.photo = photo
            await send(photo, with: food, onFound: onFound)
        }
    }

    /// Sends the last photo again, after a failure worth retrying.
    func retry(with food: FoodService, onFound: @escaping (PlateScan) -> Void) {
        guard let photo else { return }
        job?.cancel()
        job = Task { await send(photo, with: food, onFound: onFound) }
    }

    /// Stops a photo that's still being read (the sheet closing). A message stays put: a
    /// full-screen camera also hides the sheet for a while, and Try again should survive it.
    func stopReading() {
        if isReading { reset() }
    }

    /// Stops any scan and clears the message (the player dismissing it).
    func reset() {
        job?.cancel()
        job = nil
        photo = nil
        status = .idle
    }

    private func send(_ photo: MealPhoto, with food: FoodService, onFound: (PlateScan) -> Void) async {
        status = .reading(photo.preview)
        do {
            let scan = try await food.scan(jpeg: photo.jpeg)
            guard !Task.isCancelled else { return }
            scansLeft = scan.scansLeft
            if scan.items.isEmpty {
                status = .notFood(photo.preview)
            } else {
                status = .idle
                self.photo = nil
                onFound(scan)
            }
        } catch {
            guard !Task.isCancelled, !ServerError.isCancelled(error) else { return }
            let message = ServerError.message(for: error)
            if ScanProblem.isDailyLimit(error) {
                scansLeft = 0
                self.photo = nil
                status = .outOfScans(message)
            } else {
                status = .failed(message, preview: photo.preview, canRetry: ScanProblem.isWorthRetrying(error))
            }
        }
    }
}
