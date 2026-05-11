import Foundation
import Combine
import WidgetKit

// MARK: - Widget Shared Data

struct WidgetQuotaItem: Codable {
    let label: String
    let usageRate: Double   // already used %
    let resetAt: String
    let limitType: String?
}

// MARK: - Data Store (Observable)

@MainActor
class DataStore: ObservableObject {
    @Published var usageState: UsageState = UsageState(
        providers: [],
        lastUpdate: "",
        overallPercent: 100
    )
    @Published var isLoading = false
    @Published var lastError: String?

    private var config: AppConfig
    private var providers: [String: Provider] = [:]
    private var refreshTask: Task<Void, Never>?
    private var previousResults: [String: UsageResult] = [:]

    // Callback for widget data
    var onPercentUpdate: ((Double) -> Void)?

    init(config: AppConfig) {
        self.config = config
        setupProviders()
    }

    // MARK: - Setup

    func updateConfig(_ newConfig: AppConfig) {
        self.config = newConfig
        setupProviders()
    }

    private func setupProviders() {
        providers.removeAll()
        if let pc = config.providers["zhipu"], pc.enabled {
            providers["zhipu"] = ZhipuProvider()
        }
    }

    // MARK: - Refresh

    func refresh() async {
        isLoading = true
        lastError = nil

        var providerResults: [(String, Result<UsageResult, Error>)] = []

        await withTaskGroup(of: (String, Result<UsageResult, Error>).self) { group in
            for (key, provider) in providers {
                guard let pc = config.providers[key], pc.enabled, !pc.apiKey.isEmpty else { continue }
                group.addTask {
                    do {
                        let result = try await provider.fetchUsage(apiKey: pc.apiKey)
                        return (key, .success(result))
                    } catch {
                        return (key, .failure(error))
                    }
                }
            }
            for await result in group {
                providerResults.append(result)
            }
        }

        // Process results
        var displayProviders: [ProviderUsageData] = []
        var lowestPercent = 100.0
        var allWidgetQuotas: [WidgetQuotaItem] = []

        for (key, result) in providerResults {
            switch result {
            case .success(let usage):
                self.previousResults[key] = usage
                let displayData = convertToDisplayData(key: key, result: usage)
                displayProviders.append(displayData)

                for quota in usage.details.quotas {
                    lowestPercent = min(lowestPercent, max(0, 100 - quota.usageRate))
                    allWidgetQuotas.append(WidgetQuotaItem(
                        label: quota.label,
                        usageRate: quota.usageRate,
                        resetAt: quota.resetAt,
                        limitType: quota.limitType
                    ))
                }

            case .failure(let error):
                // Use previous result if available
                if let prev = self.previousResults[key] {
                    var prevWithError = prev
                    prevWithError.error = error.localizedDescription
                    displayProviders.append(convertToDisplayData(key: key, result: prevWithError))
                } else {
                    displayProviders.append(ProviderUsageData(
                        name: providerDisplayName(key),
                        error: error.localizedDescription,
                        quotas: [], history1d: [], history7d: [], history30d: [],
                        totalTokens1d: 0, totalTokens7d: 0, totalTokens30d: 0,
                        mcpHistory1d: [], mcpHistory7d: [], mcpHistory30d: [],
                        modelHistory1d: [], modelHistory7d: [], modelHistory30d: []
                    ))
                }
                self.lastError = error.localizedDescription
            }
        }

        self.usageState = UsageState(
            providers: displayProviders,
            lastUpdate: ISO8601DateFormatter().string(from: Date()),
            overallPercent: lowestPercent
        )

        isLoading = false

        // Notify widget
        onPercentUpdate?(lowestPercent)

        // Save for widget
        saveWidgetData(percent: lowestPercent, quotas: allWidgetQuotas)
    }

    // MARK: - Start Periodic Refresh

    func startRefresh(interval: TimeInterval) {
        refreshTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    func stopRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    // MARK: - Convert

    private func convertToDisplayData(key: String, result: UsageResult) -> ProviderUsageData {
        let thresholds = ColorThresholds(
            green: config.display.colorThresholds.green,
            yellow: config.display.colorThresholds.yellow
        )

        let quotaItems = result.details.quotas.map { q in
            let remainingPercent = max(0, 100 - q.usageRate)
            return QuotaItem(
                label: q.label,
                labelParams: q.labelParams,
                used: q.used,
                total: q.total,
                usageRate: q.usageRate,
                resetAt: q.resetAt,
                color: thresholds.color(for: remainingPercent),
                limitType: q.limitType
            )
        }

        return ProviderUsageData(
            name: providerDisplayName(key),
            level: result.level,
            error: result.error,
            quotas: quotaItems,
            history1d: result.details.history1d,
            history7d: result.details.history7d,
            history30d: result.details.history30d,
            totalTokens1d: result.details.totalTokens1d,
            totalTokens7d: result.details.totalTokens7d,
            totalTokens30d: result.details.totalTokens30d,
            mcpHistory1d: result.details.mcpHistory1d,
            mcpHistory7d: result.details.mcpHistory7d,
            mcpHistory30d: result.details.mcpHistory30d,
            modelHistory1d: result.details.modelHistory1d,
            modelHistory7d: result.details.modelHistory7d,
            modelHistory30d: result.details.modelHistory30d
        )
    }

    private func providerDisplayName(_ key: String) -> String {
        switch key {
        case "zhipu":  return "Z AI"
        case "minimax": return "MiniMax"
        case "kimi":   return "Kimi"
        default:       return key
        }
    }

    // MARK: - Widget Data

    private func saveWidgetData(percent: Double, quotas: [WidgetQuotaItem]) {
        let defaults = UserDefaults(suiteName: "group.top.kyatai.codingquotabar")
        defaults?.set(percent, forKey: "overallPercent")
        defaults?.set(Date().timeIntervalSince1970, forKey: "lastUpdate")
        if let data = try? JSONEncoder().encode(quotas) {
            defaults?.set(data, forKey: "quotaItems")
        }
        // Save API key so widget can fetch data independently
        if let zhipuConfig = config.providers["zhipu"], zhipuConfig.enabled, !zhipuConfig.apiKey.isEmpty {
            defaults?.set(zhipuConfig.apiKey, forKey: "zhipuApiKey")
        }
        defaults?.synchronize()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
