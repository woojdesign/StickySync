// DashboardCaptureClient.swift (iOS)
//
// 0.12.17: POSTs a transcript to the wooj ops dashboard's
// /api/capture endpoint. Spec surface:
//   - `token` query param (auth + owner scope)
//   - JSON body { "text": "..." }
//   - 200 → { captured, did, items[] }
//   - 400/401 error shapes ignored beyond mapping to a message
//
// Timeout: 15s (endpoint runs a server-side LLM parse; spec
// says "budget a few seconds"). Idempotent-by-title per spec,
// so retry is safe.

import Foundation

struct DashboardCaptureResponse: Decodable {
    let captured: Int
    let did: String
    // items[] not surfaced in UI (v1); user reviews on dashboard.
}

enum DashboardCaptureError: Error, LocalizedError {
    case notConfigured
    case badEndpoint
    case network(String)
    case httpStatus(Int)
    case decode

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Dashboard not configured"
        case .badEndpoint:   return "Bad endpoint URL"
        case .network(let s): return "Network error: \(s)"
        case .httpStatus(let c): return "Server returned \(c)"
        case .decode:        return "Unexpected response"
        }
    }
}

enum DashboardCaptureClient {

    static func send(_ text: String, config: DashboardConfig) async throws -> DashboardCaptureResponse {
        guard config.isConfigured, let base = config.endpoint else {
            throw DashboardCaptureError.notConfigured
        }
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "token", value: config.token)]
        guard let url = components?.url else {
            throw DashboardCaptureError.badEndpoint
        }

        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["text": text])

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw DashboardCaptureError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw DashboardCaptureError.network("no HTTP response")
        }
        guard (200...299).contains(http.statusCode) else {
            throw DashboardCaptureError.httpStatus(http.statusCode)
        }

        do {
            return try JSONDecoder().decode(DashboardCaptureResponse.self, from: data)
        } catch {
            throw DashboardCaptureError.decode
        }
    }
}
