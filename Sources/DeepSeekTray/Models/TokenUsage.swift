import Foundation

// MARK: - Pricing (mirrors Reasonix `price` table, per 1M tokens)

struct PricingConfig: Codable, Equatable {
    var cacheHit: Double   // per 1M tokens
    var input: Double      // per 1M tokens
    var output: Double     // per 1M tokens
    var currency: String

    static let deepseekChat = PricingConfig(
        cacheHit: 0.014,
        input: 0.14,
        output: 0.28,
        currency: "USD"
    )
}

struct ModelProfile: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var modelId: String
    var baseURL: String
    var contextWindow: Int
    var pricing: PricingConfig

    static let `default` = ModelProfile(
        name: "deepseek-chat",
        modelId: "deepseek-chat",
        baseURL: "https://api.deepseek.com",
        contextWindow: 64_000,
        pricing: .deepseekChat
    )
}

// MARK: - Usage tracking

struct TurnUsage: Identifiable, Codable {
    var id = UUID()
    let timestamp: Date
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
    let cacheHitTokens: Int
    let cacheMissTokens: Int
    let model: String

    // ponytail: single pricing for all models; switch to per-model lookup when profiles vary
    var estimatedCost: Double {
        let pricing = PricingConfig.deepseekChat
        return (Double(cacheMissTokens) / 1_000_000) * pricing.input
            + (Double(cacheHitTokens) / 1_000_000) * pricing.cacheHit
            + (Double(completionTokens) / 1_000_000) * pricing.output
    }
}

struct SessionStats: Codable {
    var turns: [TurnUsage] = []
    var startDate: Date = Date()

    var totalPromptTokens: Int { turns.reduce(0) { $0 + $1.promptTokens } }
    var totalCompletionTokens: Int { turns.reduce(0) { $0 + $1.completionTokens } }
    var totalTokens: Int { turns.reduce(0) { $0 + $1.totalTokens } }
    var totalCost: Double { turns.reduce(0) { $0 + $1.estimatedCost } }
    var turnCount: Int { turns.count }

    mutating func recordTurn(_ usage: TurnUsage) {
        turns.append(usage)
    }

    func contextRatio(for contextWindow: Int) -> Double {
        guard contextWindow > 0 else { return 0 }
        return Double(totalPromptTokens) / Double(contextWindow)
    }
}

// MARK: - Chat completion DTOs (OpenAI-compatible)

struct ChatMessage: Codable {
    let role: String
    let content: String
}

struct ChatCompletionRequest: Codable {
    let model: String
    let messages: [ChatMessage]
    let stream: Bool

    init(model: String, messages: [ChatMessage], stream: Bool = false) {
        self.model = model
        self.messages = messages
        self.stream = stream
    }
}

struct ChatCompletionResponse: Decodable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [Choice]
    let usage: Usage?

    struct Choice: Decodable {
        let index: Int
        let message: ChatMessage
        let finishReason: String?
    }

    struct Usage: Decodable {
        let promptTokens: Int
        let completionTokens: Int
        let totalTokens: Int
        let promptCacheHitTokens: Int?
        let promptCacheMissTokens: Int?
    }
}
