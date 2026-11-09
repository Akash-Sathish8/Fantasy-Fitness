//
//  FoodService.swift
//  Fantasy Fitness
//
//  The Tavern's food data, through two Edge Functions: food-search (USDA FoodData Central)
//  and scan-meal (the plate reader, which lists the foods in a meal photo). Network only.
//  Every food they return is already saved on the server, so its id can go straight into
//  a recipe or a logged plate. Demo mode searches a few sample foods and answers every
//  photo with the same sample plate.
//  Owned by GameStore and read as `store.food`, like `store.sleep`.
//

import Foundation
import Supabase

struct FoodService {
    let client: SupabaseClient?

    /// Foods matching the query, best match first. Throws when offline or the server
    /// refuses; `ServerError.message(for:)` turns that into something to show.
    func search(_ query: String) async throws -> [Food] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let client else { return Food.sampleSearch(query) }
        let response: FoodSearchResponse = try await client.functions.invoke(
            "food-search",
            options: FunctionInvokeOptions(body: FoodSearchBody(query: query, limit: 15))
        )
        return response.foods.map(\.food)
    }

    /// The foods in a meal photo (a JPEG from `MealPhoto`), with grams. Each photo counts
    /// toward the player's daily scans. Throws like `search`; the server's messages cover
    /// the daily limit and photos it can't read.
    func scan(jpeg: Data) async throws -> PlateScan {
        guard let client else {
            try await Task.sleep(for: .seconds(1.2))
            return .sample
        }
        do {
            let response: ScanResponseRow = try await client.functions.invoke(
                "scan-meal",
                options: FunctionInvokeOptions(
                    headers: ["Content-Type": "image/jpeg"],
                    body: jpeg,
                    // Longer than the shared session's 20 s: a slow scan is still working,
                    // not a dropped connection. The function's own budget stays under this.
                    timeoutInterval: 45
                )
            )
            return response.scan
        } catch FunctionsError.httpError(code: 404, data: _) {
            throw ScanProblem.notSetUp
        } catch let error as URLError where error.code == .timedOut {
            throw ScanProblem.tookTooLong
        }
    }
}

/// Scan failures the server can't describe itself.
enum ScanProblem: LocalizedError {
    case notSetUp, tookTooLong

    var errorDescription: String? {
        switch self {
        case .notSetUp: "Plate scans aren't set up on the server yet. Search for foods instead."
        case .tookTooLong: "The plate reader took too long. Try again, or search for foods."
        }
    }

    /// Whether sending the same photo again could work: after a dropped connection or a
    /// busy server, yes; after the daily limit, a refusal or a photo it can't take, no.
    static func isWorthRetrying(_ error: Error) -> Bool {
        if case .httpError(let code, let data)? = error as? FunctionsError {
            // "scan_resting": the game-wide daily budget is spent, so not until tomorrow.
            let reason = (try? JSONDecoder().decode(FunctionErrorBody.self, from: data))?.error.code
            return code >= 500 && reason != "scan_resting"
        }
        if case .notSetUp? = error as? ScanProblem { return false }
        return true
    }

    /// The player has used today's scans (scan-meal's 429).
    static func isDailyLimit(_ error: Error) -> Bool {
        if case .httpError(429, _)? = error as? FunctionsError { return true }
        return false
    }
}
