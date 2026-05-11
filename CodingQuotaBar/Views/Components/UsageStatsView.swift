import SwiftUI

struct UsageStatsView: View {
    let provider: ProviderUsageData

    @State private var chartType = 0   // 0 = Token, 1 = MCP
    @State private var timeRange = 1   // 0 = 1d, 1 = 7d, 2 = 30d

    var body: some View {
        VStack(spacing: 8) {
            // Chart type tabs
            HStack(spacing: 0) {
                tabButton(title: "Token", tag: 0, selection: $chartType)
                tabButton(title: "MCP", tag: 1, selection: $chartType)
            }

            // Time range tabs
            HStack(spacing: 0) {
                timeButton(title: "1天", tag: 0, selection: $timeRange)
                timeButton(title: "7天", tag: 1, selection: $timeRange)
                timeButton(title: "30天", tag: 2, selection: $timeRange)
            }

            // Chart content
            if chartType == 0 {
                tokenChart
            } else {
                mcpChart
            }
        }
    }

    // MARK: - Token Chart

    @ViewBuilder
    private var tokenChart: some View {
        let (records, total) = tokenData
        TokenChartView(records: records, totalTokens: total)
    }

    // MARK: - MCP Chart

    @ViewBuilder
    private var mcpChart: some View {
        let (records, searchT, webReadT, zreadT) = mcpData
        McpChartView(records: records, totalSearch: searchT, totalWebRead: webReadT, totalZread: zreadT)
    }

    // MARK: - Data Getters

    private var tokenData: ([ModelTokenRecord], Double) {
        switch timeRange {
        case 0: return (provider.modelHistory1d, provider.totalTokens1d)
        case 1: return (provider.modelHistory7d, provider.totalTokens7d)
        default: return (provider.modelHistory30d, provider.totalTokens30d)
        }
    }

    private var mcpData: ([McpUsageRecord], Double, Double, Double) {
        let records: [McpUsageRecord]
        switch timeRange {
        case 0: records = provider.mcpHistory1d
        case 1: records = provider.mcpHistory7d
        default: records = provider.mcpHistory30d
        }
        let searchT = records.reduce(0) { $0 + $1.search }
        let webReadT = records.reduce(0) { $0 + $1.webRead }
        let zreadT = records.reduce(0) { $0 + $1.zread }
        return (records, searchT, webReadT, zreadT)
    }

    // MARK: - Tab Buttons

    private func tabButton(title: String, tag: Int, selection: Binding<Int>) -> some View {
        Button {
            selection.wrappedValue = tag
        } label: {
            Text(title)
                .font(.caption)
                .fontWeight(selection.wrappedValue == tag ? .semibold : .regular)
                .foregroundColor(selection.wrappedValue == tag ? .primary : .secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(selection.wrappedValue == tag ? Color.accentColor.opacity(0.12) : Color.clear)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    private func timeButton(title: String, tag: Int, selection: Binding<Int>) -> some View {
        Button {
            selection.wrappedValue = tag
        } label: {
            Text(title)
                .font(.caption2)
                .foregroundColor(selection.wrappedValue == tag ? .accentColor : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}
