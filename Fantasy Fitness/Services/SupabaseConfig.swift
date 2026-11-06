//
//  SupabaseConfig.swift
//  Fantasy Fitness
//

import Foundation
import Supabase

/// Reads the project URL and anon key from `Config/Secrets.plist` (gitignored).
/// Copy `Secrets.example.plist` from the repo root to create it.
nonisolated struct SupabaseConfig {
    let url: URL
    let anonKey: String

    /// Nil when the file is missing or still holds the placeholder values;
    /// the app then runs in offline demo mode with sample data.
    static func load(from bundle: Bundle = .main) -> SupabaseConfig? {
        guard let fileURL = bundle.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: fileURL),
              let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let urlString = (values["SUPABASE_URL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let key = (values["SUPABASE_ANON_KEY"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !urlString.contains("YOUR-"), !key.contains("YOUR-"), !key.isEmpty,
              let parsed = URL(string: urlString), parsed.scheme == "https", let host = parsed.host(),
              // Keep only https://<project>.supabase.co; the SDK adds /auth/v1, /rest/v1 itself.
              let url = URL(string: "https://\(host)")
        else { return nil }
        return SupabaseConfig(url: url, anonKey: key)
    }
}

enum Backend {
    /// Where email confirmation links and Google sign-in return to. The app registers the
    /// `fantasyfitness` URL scheme (Fantasy-Fitness-Info.plist). Add this URL under
    /// Authentication → URL Configuration → Redirect URLs in the Supabase dashboard,
    /// otherwise Supabase falls back to the Site URL (localhost by default).
    static let authRedirectURL = URL(string: "fantasyfitness://login-callback")!

    /// Gyms have weak signal: fail a stuck request soon so its data waits in the queue.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        return URLSession(configuration: configuration)
    }()

    /// Shared client, or nil in offline demo mode.
    static let client: SupabaseClient? = SupabaseConfig.load().map {
        SupabaseClient(
            supabaseURL: $0.url,
            supabaseKey: $0.anonKey,
            options: SupabaseClientOptions(auth: .init(
                redirectToURL: authRedirectURL,
                // Opt in to the SDK's upcoming default. We never rely on the initial
                // auth event; `GameStore.resumeSession` validates the session itself.
                emitLocalSessionAsInitialSession: true
            ), global: .init(session: session))
        )
    }
}
