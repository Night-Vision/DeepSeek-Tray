import Foundation

protocol BalanceClient {
    func fetchBalance() async throws -> BalanceInfo
}

struct OfficialBalanceClient: BalanceClient {
    private let apiKey: String

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func fetchBalance() async throws -> BalanceInfo {
        var request = URLRequest(url: URL(string: "https://api.deepseek.com/user/balance")!)
        request.timeoutInterval = 10
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard http.statusCode == 200 else {
            throw HTTPError.status(code: http.statusCode, endpoint: "balance API")
        }

        let dto = try JSONDecoder().decode(BalanceResponse.self, from: data)
        guard let info = dto.balance_infos.first else {
            throw URLError(.cannotParseResponse)
        }
        return BalanceInfo(
            currency: info.currency,
            totalBalance: info.total_balance,
            grantedBalance: info.granted_balance,
            toppedUpBalance: info.topped_up_balance
        )
    }
}

private struct BalanceResponse: Decodable {
    let is_available: Bool?
    let balance_infos: [BalanceInfoDTO]
}

private struct BalanceInfoDTO: Decodable {
    let currency: String
    let total_balance: String
    let granted_balance: String
    let topped_up_balance: String
}
