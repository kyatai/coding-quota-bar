import Foundation

// MARK: - Provider Protocol

protocol Provider {
    var name: String { get }
    func fetchUsage(apiKey: String) async throws -> UsageResult
}

// MARK: - Zhipu Provider

class ZhipuProvider: Provider {
    let name = "Z AI"
    private let baseUrl: String
    private let client = HttpClient(maxRetries: 3, baseDelay: 1.0)

    init(baseUrl: String = "https://api.z.ai") {
        self.baseUrl = baseUrl
    }

    func fetchUsage(apiKey: String) async throws -> UsageResult {
        async let limitsTask = fetchLimits(apiKey: apiKey)
        async let model1d = fetchModelUsage(apiKey: apiKey, days: 1)
        async let model7d = fetchModelUsage(apiKey: apiKey, days: 7)
        async let model30d = fetchModelUsage(apiKey: apiKey, days: 30)
        async let tool1d = fetchToolUsage(apiKey: apiKey, days: 1)
        async let tool7d = fetchToolUsage(apiKey: apiKey, days: 7)
        async let tool30d = fetchToolUsage(apiKey: apiKey, days: 30)

        let limits = try await limitsTask
        let m1 = try await model1d
        let m7 = try await model7d
        let m30 = try await model30d
        let t1 = try await tool1d
        let t7 = try await tool7d
        let t30 = try await tool30d

        return buildResult(limits: limits, model1d: m1, model7d: m7, model30d: m30,
                           tool1d: t1, tool7d: t7, tool30d: t30)
    }

    // MARK: - Fetch Limits

    private func fetchLimits(apiKey: String) async throws -> ZhipuLimitData? {
        let url = "\(baseUrl)/api/monitor/usage/quota/limit"
        let data = try await client.get(url: url, headers: [
            "Authorization": "Bearer \(apiKey)"
        ])
        let resp = try JSONDecoder().decode(ZhipuLimitResponse.self, from: data)
        return resp.data
    }

    // MARK: - Fetch Model Usage

    private func fetchModelUsage(apiKey: String, days: Int) async throws -> ZhipuModelUsageData? {
        let (start, end) = timeRange(days: days)
        let url = "\(baseUrl)/api/monitor/usage/model-usage?startTime=\(start)&endTime=\(end)"
        let data = try await client.get(url: url, headers: [
            "Authorization": "Bearer \(apiKey)"
        ])
        let resp = try JSONDecoder().decode(ZhipuModelUsageResponse.self, from: data)
        return resp.data
    }

    // MARK: - Fetch Tool Usage

    private func fetchToolUsage(apiKey: String, days: Int) async throws -> ZhipuToolUsageData? {
        let (start, end) = timeRange(days: days)
        let url = "\(baseUrl)/api/monitor/usage/tool-usage?startTime=\(start)&endTime=\(end)"
        let data = try await client.get(url: url, headers: [
            "Authorization": "Bearer \(apiKey)"
        ])
        let resp = try JSONDecoder().decode(ZhipuToolUsageResponse.self, from: data)
        return resp.data
    }

    // MARK: - Build Result

    private func buildResult(
        limits: ZhipuLimitData?,
        model1d: ZhipuModelUsageData?, model7d: ZhipuModelUsageData?, model30d: ZhipuModelUsageData?,
        tool1d: ZhipuToolUsageData?, tool7d: ZhipuToolUsageData?, tool30d: ZhipuToolUsageData?
    ) -> UsageResult {
        var quotas: [QuotaItem] = []
        var lowestUsed = 0.0
        var lowestTotal = 1.0

        if let limitItems = limits?.limits {
            for item in limitItems {
                guard let type = item.type else { continue }
                let number = item.number ?? 0
                let remaining = item.remaining ?? 0
                let percentage = item.percentage ?? 0
                let resetTime = item.nextResetTime ?? 0

                var label: String
                var limitType: String
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

                // Use API-provided percentage directly to avoid unit mismatch
                // (TIME_LIMIT and TOKENS_LIMIT have different number/remaining units)
                let usageRate = percentage  // already-used %
                let used = number > 0 ? max(0, number - remaining) : 0

                quotas.append(QuotaItem(
                    label: label,
                    used: used,
                    total: number,
                    usageRate: usageRate,
                    resetAt: formatResetTime(resetTime),
                    color: percentage >= 50 ? .green : (percentage >= 20 ? .yellow : .red),
                    limitType: limitType
                ))

                if type != "TIME_LIMIT" && (lowestTotal == 0 || percentage < (lowestUsed / lowestTotal * 100)) {
                    lowestUsed = used
                    lowestTotal = number
                }
            }
        }

        return UsageResult(
            used: lowestUsed,
            total: lowestTotal,
            expiresAt: "",
            level: limits?.level,
            error: nil,
            details: UsageDetails(
                quotas: quotas,
                history1d: buildUsageHistory(model1d),
                history7d: buildUsageHistory(model7d),
                history30d: buildUsageHistory(model30d),
                totalTokens1d: model1d?.totalUsage?.totalTokensUsage ?? 0,
                totalTokens7d: model7d?.totalUsage?.totalTokensUsage ?? 0,
                totalTokens30d: model30d?.totalUsage?.totalTokensUsage ?? 0,
                mcpHistory1d: buildMcpHistory(tool1d),
                mcpHistory7d: buildMcpHistory(tool7d),
                mcpHistory30d: buildMcpHistory(tool30d),
                modelHistory1d: buildModelHistory(model1d),
                modelHistory7d: buildModelHistory(model7d),
                modelHistory30d: buildModelHistory(model30d)
            )
        )
    }

    // MARK: - History Builders

    private func buildUsageHistory(_ data: ZhipuModelUsageData?) -> [UsageRecord] {
        guard let times = data?.x_time, let models = data?.modelDataList else { return [] }
        guard !times.isEmpty else { return [] }

        return times.enumerated().map { (i, time) in
            let totalForDate = models.reduce(0.0) { sum, model in
                let values = model.tokensUsage ?? []
                return sum + (i < values.count ? values[i] : 0)
            }
            return UsageRecord(date: time, used: totalForDate)
        }
    }

    private func buildMcpHistory(_ data: ZhipuToolUsageData?) -> [McpUsageRecord] {
        guard let times = data?.x_time else { return [] }
        let search = data?.networkSearchCount ?? []
        let webRead = data?.webReadMcpCount ?? []
        let zread = data?.zreadMcpCount ?? []

        return times.enumerated().map { (i, time) in
            McpUsageRecord(
                date: time,
                search: i < search.count ? search[i] : 0,
                webRead: i < webRead.count ? webRead[i] : 0,
                zread: i < zread.count ? zread[i] : 0
            )
        }
    }

    private func buildModelHistory(_ data: ZhipuModelUsageData?) -> [ModelTokenRecord] {
        guard let times = data?.x_time, let models = data?.modelDataList else { return [] }

        var records: [ModelTokenRecord] = []
        for model in models {
            guard let name = model.modelName else { continue }
            let values = model.tokensUsage ?? []
            for (i, time) in times.enumerated() {
                if i < values.count {
                    records.append(ModelTokenRecord(date: time, model: name, used: values[i]))
                }
            }
        }
        return records
    }

    // MARK: - Time Range Helper

    private func timeRange(days: Int) -> (String, String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        return (formatter.string(from: start), formatter.string(from: now))
    }
}
