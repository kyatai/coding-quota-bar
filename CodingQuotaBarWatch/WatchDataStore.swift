import SwiftUI
import Combine
import WatchConnectivity
import WidgetKit

// MARK: - Widget 共享数据模型

struct WidgetQuotaData: Codable {
    let label: String
    let usageRate: Double
    let resetAt: String
    let limitType: String?

    var remainingPercent: Double { max(0, 100 - usageRate) }
}

@MainActor
class WatchDataStore: NSObject, ObservableObject {
    @Published var quotas: [WatchQuota] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var lastUpdate: Date?

    @AppStorage("watchApiKey", store: UserDefaults(suiteName: "group.top.hyizhou.codingquotabar"))
    var apiKey: String = "" {
        didSet {
            if !apiKey.isEmpty {
                Task { await refresh() }
            }
        }
    }

    static let appGroup = "group.top.hyizhou.codingquotabar"

    var tokenPercent: Double {
        let tokens = quotas.filter { $0.limitType == "tokens" }
        return tokens.map(\.remainingPercent).min() ?? 100
    }

    var tokenColor: Color {
        if tokenPercent >= 50 { return .green }
        if tokenPercent >= 20 { return .orange }
        return .red
    }

    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func refresh() async {
        guard !apiKey.isEmpty else { return }
        isLoading = true
        error = nil
        do {
            quotas = try await ZhipuWatchService.fetchQuotas(apiKey: apiKey)
            lastUpdate = Date()
            syncToWidget()
        } catch {
            self.error = "获取失败"
        }
        isLoading = false
    }

    // MARK: - 同步数据到 Watch Widget

    private func syncToWidget() {
        let defaults = UserDefaults(suiteName: WatchDataStore.appGroup)

        // 写入 overallPercent
        defaults?.set(tokenPercent, forKey: "overallPercent")

        // 写入 lastUpdate
        defaults?.set(Date().timeIntervalSince1970, forKey: "lastUpdate")

        // 写入 quotaItems
        let items = quotas.map { q in
            WidgetQuotaData(label: q.label, usageRate: q.usageRate,
                            resetAt: q.resetAt, limitType: q.limitType)
        }
        if let data = try? JSONEncoder().encode(items) {
            defaults?.set(data, forKey: "quotaItems")
        }

        // 刷新 Widget timeline
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - WCSessionDelegate

extension WatchDataStore: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {}

    nonisolated func session(_ session: WCSession,
                             didReceiveUserInfo userInfo: [String: Any]) {
        let key = userInfo["zhipuApiKey"] as? String
            ?? userInfo["zhipu_apiKey"] as? String
            ?? ""
        guard !key.isEmpty else { return }
        Task { @MainActor in
            self.apiKey = key
        }
    }

    nonisolated func session(_ session: WCSession,
                             didReceiveMessage message: [String: Any]) {
        let key = message["zhipuApiKey"] as? String
            ?? message["zhipu_apiKey"] as? String
            ?? ""
        guard !key.isEmpty else { return }
        Task { @MainActor in
            self.apiKey = key
        }
    }
}
