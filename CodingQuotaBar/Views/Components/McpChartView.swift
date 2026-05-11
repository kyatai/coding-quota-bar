import SwiftUI
import Charts

struct McpChartView: View {
    let records: [McpUsageRecord]
    let totalSearch: Double
    let totalWebRead: Double
    let totalZread: Double

    private var totalCount: Double {
        totalSearch + totalWebRead + totalZread
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text("MCP 工具使用")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(formatNumber(totalCount)) 次")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
            }

            if records.isEmpty {
                Text("暂无数据")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                let sorted = records.sorted { parseDate($0.date) < parseDate($1.date) }

                Chart {
                    ForEach(sorted) { record in
                        BarMark(
                            x: .value("日期", parseDate(record.date)),
                            y: .value("次数", record.search)
                        )
                        .foregroundStyle(Color.blue)

                        BarMark(
                            x: .value("日期", parseDate(record.date)),
                            y: .value("次数", record.webRead)
                        )
                        .foregroundStyle(Color.green)

                        BarMark(
                            x: .value("日期", parseDate(record.date)),
                            y: .value("次数", record.zread)
                        )
                        .foregroundStyle(Color.orange)
                    }
                }
                .chartLegend {
                    HStack(spacing: 12) {
                        legendItem(color: .blue, text: "搜索")
                        legendItem(color: .green, text: "网页")
                        legendItem(color: .orange, text: "ZRead")
                    }
                    .font(.caption2)
                }
                .frame(height: 100)
            }
        }
        .padding(10)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(10)
    }

    private func legendItem(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).foregroundColor(.secondary)
        }
    }

    private func parseDate(_ date: String) -> Date {
        let formatters: [DateFormatter] = [
            { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"; return f }(),
            { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd'T'HH:mm"; return f }(),
            { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd'T'HH"; return f }(),
            { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"; return f }(),
            { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"; return f }(),
            { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH"; return f }(),
            { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f }(),
        ]
        for fmt in formatters {
            if let d = fmt.date(from: date) { return d }
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: date) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: date) { return d }
        return Date.distantPast
    }
}

#Preview {
    McpChartView(
        records: [
            McpUsageRecord(date: "2026-04-14", search: 5, webRead: 10, zread: 3),
            McpUsageRecord(date: "2026-04-15", search: 8, webRead: 12, zread: 6),
        ],
        totalSearch: 13, totalWebRead: 22, totalZread: 9
    )
    .padding()
}
