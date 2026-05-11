import WidgetKit
import SwiftUI

// MARK: - Shared Data Types

struct WidgetQuotaItem: Codable {
    let label: String
    let usageRate: Double   // already used %
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

struct QuotaEntry: TimelineEntry {
    let date: Date
    let overallPercent: Double
    let quotas: [WidgetQuotaItem]
    let lastUpdate: Date?
}

// MARK: - API Response Types (widget-local)

private struct WidgetAPIResponse: Codable {
    let code: Int?
    let data: WidgetAPIData?
}

private struct WidgetAPIData: Codable {
    let limits: [WidgetAPILimit]?
}

private struct WidgetAPILimit: Codable {
    let type: String?
    let unit: Int?
    let number: Double?
    let remaining: Double?
    let percentage: Double?
    let nextResetTime: Double?
}

// MARK: - Timeline Provider

struct QuotaProvider: TimelineProvider {
    private let appGroup = "group.top.hyizhou.codingquotabar"

    func placeholder(in context: Context) -> QuotaEntry {
        QuotaEntry(date: Date(), overallPercent: 75, quotas: [
            WidgetQuotaItem(label: "Token额度", usageRate: 25, resetAt: "3天后重置", limitType: "tokens"),
            WidgetQuotaItem(label: "MCP工具额度", usageRate: 10, resetAt: "7天后重置", limitType: "mcp"),
        ], lastUpdate: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (QuotaEntry) -> Void) {
        completion(loadCachedEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuotaEntry>) -> Void) {
        Task {
            let entry = await fetchFreshEntry()
            let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    // MARK: - Network Fetch

    private func fetchFreshEntry() async -> QuotaEntry {
        let defaults = UserDefaults(suiteName: appGroup)
        guard let apiKey = defaults?.string(forKey: "zhipuApiKey"), !apiKey.isEmpty else {
            return loadCachedEntry()
        }

        do {
            let quotas = try await fetchQuotas(apiKey: apiKey)
            let tokenPercent = quotas
                .filter { $0.limitType == "tokens" }
                .map { max(0, 100 - $0.usageRate) }
                .min() ?? 100

            // Cache results for fallback
            if let data = try? JSONEncoder().encode(quotas) {
                defaults?.set(data, forKey: "quotaItems")
            }
            defaults?.set(tokenPercent, forKey: "overallPercent")
            defaults?.set(Date().timeIntervalSince1970, forKey: "lastUpdate")

            return QuotaEntry(date: Date(), overallPercent: tokenPercent,
                              quotas: quotas, lastUpdate: Date())
        } catch {
            return loadCachedEntry()
        }
    }

    private func fetchQuotas(apiKey: String) async throws -> [WidgetQuotaItem] {
        guard let url = URL(string: "https://api.z.ai/api/monitor/usage/quota/limit") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let resp = try JSONDecoder().decode(WidgetAPIResponse.self, from: data)
        return (resp.data?.limits ?? []).compactMap { parseLimit($0) }
            .sorted { ($0.limitType == "tokens" ? 0 : 1) < ($1.limitType == "tokens" ? 0 : 1) }
    }

    private func parseLimit(_ item: WidgetAPILimit) -> WidgetQuotaItem? {
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
        return WidgetQuotaItem(
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

    // MARK: - Cache Fallback

    private func loadCachedEntry() -> QuotaEntry {
        let defaults = UserDefaults(suiteName: appGroup)
        let percent = defaults?.double(forKey: "overallPercent") ?? 100
        let ts = defaults?.double(forKey: "lastUpdate") ?? 0
        let lastUpdate = ts > 0 ? Date(timeIntervalSince1970: ts) : nil

        var quotas: [WidgetQuotaItem] = []
        if let data = defaults?.data(forKey: "quotaItems"),
           let items = try? JSONDecoder().decode([WidgetQuotaItem].self, from: data) {
            quotas = items.sorted { a, b in
                let rank: (WidgetQuotaItem) -> Int = { $0.limitType == "tokens" ? 0 : 1 }
                return rank(a) < rank(b)
            }
        }
        return QuotaEntry(date: Date(), overallPercent: percent, quotas: quotas, lastUpdate: lastUpdate)
    }
}

// MARK: - Entry View (router)

struct QuotaWidgetEntryView: View {
    let entry: QuotaEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                CircularView(entry: entry)
            case .accessoryRectangular:
                RectangularView(entry: entry)
            case .systemMedium:
                MediumView(entry: entry)
            default:
                SmallView(entry: entry)
            }
        }
        .widgetBackground(family)
    }
}

// MARK: - widget background helper

extension View {
    @ViewBuilder
    func widgetBackground(_ family: WidgetFamily) -> some View {
        switch family {
        case .accessoryCircular, .accessoryRectangular:
            // accessory 组件由系统渲染背景，不设置 containerBackground
            self
        default:
            self.containerBackground(for: .widget) {
                Color(UIColor.systemBackground)
            }
        }
    }
}

// MARK: - accessoryCircular

struct CircularView: View {
    let entry: QuotaEntry

    private var tokenPercent: Double {
        let tokens = entry.quotas.filter { $0.limitType == "tokens" }
        return tokens.map(\.remainingPercent).min() ?? entry.overallPercent
    }

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            GeometryReader { geo in
                let size = min(geo.size.width, geo.size.height)
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 3)
                        .frame(width: size - 6, height: size - 6)
                    Circle()
                        .trim(from: 0, to: tokenPercent / 100)
                        .stroke(colorFor(tokenPercent),
                                style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: size - 6, height: size - 6)
                        .rotationEffect(.degrees(-90))
                    Text(String(format: "%.0f%%", tokenPercent))
                        .font(.system(size: size * 0.27, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.5)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }
}

// MARK: - accessoryRectangular (下拉通知/锁屏矩形)

struct RectangularView: View {
    let entry: QuotaEntry

    private var tokenQuotas: [WidgetQuotaItem] {
        entry.quotas.filter { $0.limitType == "tokens" }
    }

    private var tokenPercent: Double {
        tokenQuotas.map(\.remainingPercent).min() ?? entry.overallPercent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // 第一行：标题 + 总百分比
            HStack {
                Text("Token 额度")
                    .font(.headline)
                Spacer()
                Text(String(format: "%.0f%% 剩余", tokenPercent))
                    .font(.caption)
                    .foregroundColor(colorFor(tokenPercent))
            }

            // 每个 Token 额度条目
            if tokenQuotas.isEmpty {
                Text("暂无数据")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                ForEach(tokenQuotas.prefix(3), id: \.label) { quota in
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

            // 最后更新时间
            if let last = entry.lastUpdate {
                Text(relativeTime(last))
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - systemSmall

struct SmallView: View {
    let entry: QuotaEntry

    private var tokenPercent: Double {
        let tokens = entry.quotas.filter { $0.limitType == "tokens" }
        return tokens.map(\.remainingPercent).min() ?? entry.overallPercent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                Text("Quota")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Text(String(format: "%.0f%%", tokenPercent))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(colorFor(tokenPercent))
            }
            .padding(.bottom, 5)

            if entry.quotas.isEmpty {
                Spacer()
                Text("暂无数据").font(.caption2).foregroundColor(.secondary)
                Spacer()
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(entry.quotas.prefix(4), id: \.label) { quota in
                        QuotaRowView(quota: quota, showReset: false)
                    }
                }
            }

            Spacer(minLength: 2)
            Text(relativeTime(entry.lastUpdate))
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .padding(12)
    }
}

// MARK: - systemMedium

struct MediumView: View {
    let entry: QuotaEntry

    private var tokenPercent: Double {
        let tokens = entry.quotas.filter { $0.limitType == "tokens" }
        return tokens.map(\.remainingPercent).min() ?? entry.overallPercent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Coding Quota Bar")
                        .font(.system(size: 13, weight: .bold))
                    Text(relativeTime(entry.lastUpdate))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(String(format: "%.0f%%", tokenPercent))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(colorFor(tokenPercent))
                    Text("Token剩余")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.bottom, 8)

            if entry.quotas.isEmpty {
                Spacer()
                HStack { Spacer(); Text("暂无配额数据").font(.caption2).foregroundColor(.secondary); Spacer() }
                Spacer()
            } else {
                let cols = split(entry.quotas)
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(cols.0, id: \.label) { QuotaRowView(quota: $0, showReset: true) }
                    }
                    if !cols.1.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(cols.1, id: \.label) { QuotaRowView(quota: $0, showReset: true) }
                        }
                    }
                }
            }
        }
        .padding(14)
    }

    private func split(_ items: [WidgetQuotaItem]) -> ([WidgetQuotaItem], [WidgetQuotaItem]) {
        let half = (items.count + 1) / 2
        return (Array(items.prefix(half)), Array(items.dropFirst(half)))
    }
}

// MARK: - Quota Row

struct QuotaRowView: View {
    let quota: WidgetQuotaItem
    let showReset: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(quota.label)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .foregroundColor(.primary)
                Spacer()
                Text(String(format: "%.0f%%", quota.remainingPercent))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(quota.statusColor)
            }
            ProgressBarView(value: quota.remainingPercent / 100, color: quota.statusColor)
            if showReset && !quota.resetAt.isEmpty {
                Text(quota.resetAt)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Progress Bar

struct ProgressBarView: View {
    let value: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(Color.primary.opacity(0.12))
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: geo.size.width * min(1, max(0, value)))
            }
        }
        .frame(height: 4)
    }
}

// MARK: - Helpers

private func colorFor(_ percent: Double) -> Color {
    if percent >= 50 { return .green }
    if percent >= 20 { return .orange }
    return .red
}

private func relativeTime(_ date: Date?) -> String {
    guard let date else { return "未更新" }
    let diff = Int(Date().timeIntervalSince(date))
    if diff < 60 { return "刚刚" }
    if diff < 3600 { return "\(diff / 60)分钟前" }
    return "\(diff / 3600)小时前"
}

// MARK: - Widget Configuration

struct QuotaWidget: Widget {
    let kind = "QuotaWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuotaProvider()) { entry in
            QuotaWidgetEntryView(entry: entry)
                .widgetURL(URL(string: "codingquotabar://main")!)
        }
        .configurationDisplayName("Coding Quota Bar")
        .description("显示 AI Coding 额度使用情况")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

// MARK: - Widget Bundle

@main
struct QuotaWidgetBundle: WidgetBundle {
    var body: some Widget {
        QuotaWidget()
    }
}
