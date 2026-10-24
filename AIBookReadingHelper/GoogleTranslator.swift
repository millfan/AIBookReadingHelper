import Foundation

/// Calls the Google Cloud Translation API (Basic, v2) with an API key.
enum GoogleTranslator {
    struct APIError: LocalizedError {
        let errorDescription: String?
    }

    private struct Request: Encodable {
        let q: String
        let target: String
        let format = "text"
    }

    private struct Response: Decodable {
        struct Payload: Decodable {
            struct Translation: Decodable {
                let translatedText: String
            }
            let translations: [Translation]
        }
        let data: Payload
    }

    private struct ErrorResponse: Decodable {
        struct Detail: Decodable {
            let message: String
        }
        let error: Detail
    }

    private static let endpoint = URL(string: "https://translation.googleapis.com/language/translate/v2")!

    /// Translates `text` into the language with the given Google code. The source language is detected by Google.
    static func translate(_ text: String, to target: String, apiKey: String) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // The key goes in a header rather than the URL so it doesn't end up in logs.
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.httpBody = try JSONEncoder().encode(Request(q: text, target: target))

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard statusCode == 200 else {
            let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error.message
            throw APIError(errorDescription: "Google Translation failed: \(message ?? "HTTP status \(statusCode)")")
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let translation = decoded.data.translations.first else {
            throw APIError(errorDescription: "Google Translation returned no result.")
        }
        return translation.translatedText
    }
}
