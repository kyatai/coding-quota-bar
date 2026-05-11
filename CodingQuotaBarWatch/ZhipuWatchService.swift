import Foundation

// MARK: - Watch Quota Model

struct WatchQuota: Identifiable {
    let id = UUID()
    let label: String
    let usageRate: Double   // already used %
    let resetAt: String
    let limitType: String?

    var remainingPercent: Double { max(0, 100 - usageRate) }
}

// MARK: - API Response Types

private struct LimitResponse: Codable {
    let code: Int?
    let data: LimitData?
}

private struct LimitData: Codable {
    let limits: [LimitItem]?
    let level: String?
}

private struct LimitItem: Codable {
    let type: String?
    let unit: Int?
    let number: Double?
    let remaining: Double?
    let percentage: Double?
    let nextResetTime: Double?
}

// MARK: - Service

enum ZhipuWatchService {
    static func fetchQuotas(apiKey: String) async throws -> [WatchQuota] {
        guard let url = URL(string: "https://api.z.ai/api/monitor/usage/quota/limit") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let resp = try JSONDecoder().decode(LimitResponse.self, from: data)
        let items = resp.data?.limits ?? []

        return items.compactMap { parse($0) }
            .sorted { ($0.limitType == "tokens" ? 0 : 1) < ($1.limitType == "tokens" ? 0 : 1) }
    }

    private static func parse(_ item: LimitItem) -> WatchQuota? {
        guard let type = item.type else { return nil }

        let label: String
        let limitType: String
        if type == "TIME_LIMIT" {
            label = "MCP工具额度"
            limitType = "mcp"
        } else if item.unit == 1 {
            label = "每小时额度"
            limitType = "tokens"
        } else {
            label = "Token额度"
            limitType = "tokens"
        }

        let usageRate = item.percentage ?? 0
        return WatchQuota(label: label, usageRate: usageRate,
                          resetAt: formatReset(item.nextResetTime ?? 0), limitType: limitType)
    }

    private static func formatReset(_ ms: Double) -> String {
        guard ms > 0 else { return "" }
        let diff = Date(timeIntervalSince1970: ms / 1000).timeIntervalSinceNow
        guard diff > 0 else { return "已重置" }
        let h = Int(diff / 3600)
        let d = h / 24
        if d > 0 { return "\(d)天后重置" }
        if h > 0 { return "\(h)小时后重置" }
        return "\(Int(diff / 60))分钟后重置"
    }
}
