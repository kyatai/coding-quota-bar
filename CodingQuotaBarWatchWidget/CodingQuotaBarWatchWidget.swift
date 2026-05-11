import WidgetKit
import SwiftUI

// MARK: - 共享数据模型（与 WatchDataStore.WidgetQuotaData 一致）

struct SharedQuotaItem: Codable {
    let label: String
    let usageRate: Double
    let resetAt: String
    let limitType: String?

    var remainingPercent: Double { max(0, 100 - usageRate) }
    var statusColor: Color {
        if remainingPercent >= 50 { return .green }
        if remainingPercent >= 20 { return .orange }
        return .red
    }
}

// MARK: - Timeline Entry

struct WatchQuotaEntry: TimelineEntry {
    let date: Date
    let overallPercent: Double
    let quotas: [SharedQuotaItem]
    let lastUpdate: Date?
}

// MARK: - API Response（Widget 独立副本）

private struct APIResponse: Codable {
    let code: Int?
    let data: APIData?
}

private struct APIData: Codable {
    let limits: [APILimit]?
}

private struct APILimit: Codable {
    let type: String?
    let unit: Int?
    let number: Double?
    let remaining: Double?
    let percentage: Double?
    let nextResetTime: Double?
}

// MARK: - Timeline Provider

struct WatchQuotaProvider: TimelineProvider {
    private let appGroup = "group.top.kyatai.codingquotabar"

    func placeholder(in context: Context) -> WatchQuotaEntry {
        WatchQuotaEntry(date: Date(), overallPercent: 75, quotas: [
            SharedQuotaItem(label: "每小时额度", usageRate: 25, resetAt: "3小时后重置", limitType: "tokens"),
            SharedQuotaItem(label: "Token额度", usageRate: 10, resetAt: "7天后重置", limitType: "tokens"),
        ], lastUpdate: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchQuotaEntry) -> Void) {
        completion(loadCachedEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchQuotaEntry>) -> Void) {
        Task {
            let entry = await fetchFreshEntry()
            let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    // MARK: - 网络获取

    private func fetchFreshEntry() async -> WatchQuotaEntry {
        let defaults = UserDefaults(suiteName: appGroup)
        guard let apiKey = defaults?.string(forKey: "watchApiKey"), !apiKey.isEmpty else {
            return loadCachedEntry()
        }

        do {
            let quotas = try await fetchQuotas(apiKey: apiKey)
            let tokenPercent = quotas
                .filter { $0.limitType == "tokens" }
                .map { max(0, 100 - $0.usageRate) }
                .min() ?? 100

            // 写入缓存，Watch App 也能读到
            if let data = try? JSONEncoder().encode(quotas) {
                defaults?.set(data, forKey: "quotaItems")
            }
            defaults?.set(tokenPercent, forKey: "overallPercent")
            defaults?.set(Date().timeIntervalSince1970, forKey: "lastUpdate")

            return WatchQuotaEntry(date: Date(), overallPercent: tokenPercent,
                                   quotas: quotas, lastUpdate: Date())
        } catch {
            return loadCachedEntry()
        }
    }

    private func fetchQuotas(apiKey: String) async throws -> [SharedQuotaItem] {
        guard let url = URL(string: "https://api.z.ai/api/monitor/usage/quota/limit") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let resp = try JSONDecoder().decode(APIResponse.self, from: data)
        return (resp.data?.limits ?? []).compactMap { parseLimit($0) }
            .sorted { ($0.limitType == "tokens" ? 0 : 1) < ($1.limitType == "tokens" ? 0 : 1) }
    }

    private func parseLimit(_ item: APILimit) -> SharedQuotaItem? {
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
        return SharedQuotaItem(
            label: label,
            usageRate: item.percentage ?? 0,
            resetAt: formatResetTime(item.nextResetTime ?? 0),
            limitType: limitType
        )
    }

    private func formatResetTime(_ ms: Double) -> String {
        guard ms > 0 else { return "" }
        let diff = Date(timeIntervalSince1970: ms / 1000).timeIntervalSinceNow
        guard diff > 0 else { return "已重置" }
        let h = Int(diff / 3600)
        let d = h / 24
        if d > 0 { return "\(d)天后重置" }
        if h > 0 { return "\(h)小时后重置" }
        return "\(Int(diff / 60))分钟后重置"
    }

    // MARK: - 缓存读取（网络失败时的降级）

    private func loadCachedEntry() -> WatchQuotaEntry {
        let defaults = UserDefaults(suiteName: appGroup)
        let percent = defaults?.double(forKey: "overallPercent") ?? 100
        let ts = defaults?.double(forKey: "lastUpdate") ?? 0
        let lastUpdate = ts > 0 ? Date(timeIntervalSince1970: ts) : nil

        var quotas: [SharedQuotaItem] = []
        if let data = defaults?.data(forKey: "quotaItems"),
           let items = try? JSONDecoder().decode([SharedQuotaItem].self, from: data) {
            quotas = items.sorted { a, b in
                let rank: (SharedQuotaItem) -> Int = { $0.limitType == "tokens" ? 0 : 1 }
                return rank(a) < rank(b)
            }
        }
        return WatchQuotaEntry(date: Date(), overallPercent: percent, quotas: quotas, lastUpdate: lastUpdate)
    }
}

// MARK: - Entry View (router)

struct WatchQuotaWidgetEntryView: View {
    let entry: WatchQuotaEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                WatchCircularView(entry: entry)
            case .accessoryRectangular:
                WatchRectangularView(entry: entry)
            default:
                WatchCircularView(entry: entry)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - accessoryCircular

struct WatchCircularView: View {
    let entry: WatchQuotaEntry

    private var tokenPercent: Double {
        let tokens = entry.quotas.filter { $0.limitType == "tokens" }
        return tokens.map(\.remainingPercent).min() ?? entry.overallPercent
    }

    private var color: Color {
        if tokenPercent >= 50 { return .green }
        if tokenPercent >= 20 { return .orange }
        return .red
    }

    var body: some View {
        ZStack {
            GeometryReader { geo in
                let size = min(geo.size.width, geo.size.height)
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 3)
                        .frame(width: size - 6, height: size - 6)
                    Circle()
                        .trim(from: 0, to: min(1, tokenPercent / 100))
                        .stroke(color,
                                style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: size - 6, height: size - 6)
                        .rotationEffect(.degrees(-90))
                    Text(String(format: "%.0f%%", tokenPercent))
                        .font(.system(size: size * 0.27, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .foregroundColor(color)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }
}

// MARK: - accessoryRectangular

struct WatchRectangularView: View {
    let entry: WatchQuotaEntry

    private var tokenQuotas: [SharedQuotaItem] {
        entry.quotas.filter { $0.limitType == "tokens" }
    }

    private var tokenPercent: Double {
        tokenQuotas.map(\.remainingPercent).min() ?? entry.overallPercent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                Text("Token 额度")
                    .font(.headline)
                Spacer()
                Text(String(format: "%.0f%%", tokenPercent))
                    .font(.caption)
                    .foregroundColor(tokenPercent >= 50 ? .green : tokenPercent >= 20 ? .orange : .red)
            }

            if tokenQuotas.isEmpty {
                Text("暂无数据")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                ForEach(tokenQuotas.prefix(2), id: \.label) { quota in
                    HStack(spacing: 4) {
                        Text(quota.label)
                            .font(.caption2)
                            .lineLimit(1)
                        Spacer()
                        Text(String(format: "%.0f%%", quota.remainingPercent))
                            .font(.caption2)
                            .foregroundColor(quota.statusColor)
                    }
                }
            }
        }
    }
}

// MARK: - Widget Configuration

@main
struct CodingQuotaBarWatchWidget: Widget {
    let kind: String = "CodingQuotaBarWatchWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchQuotaProvider()) { entry in
            WatchQuotaWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Token 余量")
        .description("显示 Token 剩余额度")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}
