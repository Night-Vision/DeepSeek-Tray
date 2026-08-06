import Foundation
import Combine

// MARK: - Cost calculation

enum CostCalculator {
    static func cost(for usage: TurnUsage, pricing: PricingConfig) -> Double {
        return (Double(usage.cacheMissTokens) / 1_000_000) * pricing.input
            + (Double(usage.cacheHitTokens) / 1_000_000) * pricing.cacheHit
            + (Double(usage.completionTokens) / 1_000_000) * pricing.output
    }

    static func cost(for session: SessionStats, pricing: PricingConfig) -> Double {
        session.turns.reduce(0) { sum, turn in
            sum + cost(for: turn, pricing: pricing)
        }
    }
}

// MARK: - Chat completions (extracts usage like Reasonix does)

final class ChatCompletionService {
    private let apiKey: String
    private let baseURL: URL

    init(apiKey: String, baseURL: URL = URL(string: "https://api.deepseek.com")!) {
        self.apiKey = apiKey
        self.baseURL = baseURL
    }

    func send(messages: [ChatMessage], model: String) async throws -> ChatCompletionResponse {
        let url = baseURL.appendingPathComponent("/chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        request.httpBody = try JSONEncoder().encode(ChatCompletionRequest(model: model, messages: messages))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard http.statusCode == 200 else {
            throw HTTPError.status(code: http.statusCode, endpoint: "chat API")
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(ChatCompletionResponse.self, from: data)
    }
}

// MARK: - Session tracking

@MainActor
final class SessionUsageTracker: ObservableObject {
    static let shared = SessionUsageTracker()

    @Published var currentSession = SessionStats()
    @Published var currentModel: ModelProfile = .default

    private init() {}

    func recordTurn(from response: ChatCompletionResponse) {
        guard let usage = response.usage else { return }
        let turn = TurnUsage(
            timestamp: Date(),
            promptTokens: usage.promptTokens,
            completionTokens: usage.completionTokens,
            totalTokens: usage.totalTokens,
            cacheHitTokens: usage.promptCacheHitTokens ?? 0,
            cacheMissTokens: usage.promptCacheMissTokens ?? 0,
            model: response.model
        )
        currentSession.recordTurn(turn)
    }

    func resetSession() {
        currentSession = SessionStats()
    }

    func contextRatio() -> Double {
        currentSession.contextRatio(for: currentModel.contextWindow)
    }
}
