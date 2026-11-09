//
//  FoodService.swift
//  Fantasy Fitness
//
//  The Tavern's food search: USDA FoodData Central through the food-search Edge Function.
//  Network only. Every food it returns is already saved on the server, so its id can go
//  straight into a recipe or a logged plate. Demo mode searches a few sample foods.
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
}
