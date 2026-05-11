import SwiftUI
import Charts

struct TokenChartView: View {
    let records: [ModelTokenRecord]
    let totalTokens: Double

    private let modelColors: [Color] = [
        .blue, .purple, .orange, .pink, .cyan,
        .indigo, .mint, .yellow
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text("Token 使用统计")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(formatNumber(totalTokens)) tokens")
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
                let grouped = Dictionary(grouping: sorted) { $0.model }

                Chart {
                    ForEach(Array(grouped.keys.enumerated()), id: \.offset) { idx, model in
                        ForEach(grouped[model] ?? []) { record in
                            BarMark(
                                x: .value("日期", parseDate(record.date)),
                                y: .value("Tokens", record.used)
                            )
                            .foregroundStyle(modelColors[idx % modelColors.count])
                            .position(by: .value("模型", model))
                        }
                    }
                }
                .chartYAxisLabel("Tokens")
                .frame(height: 100)
            }
        }
        .padding(10)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(10)
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
    TokenChartView(records: [
        ModelTokenRecord(date: "2026-04-14", model: "GLM-4", used: 50000),
        ModelTokenRecord(date: "2026-04-14", model: "GLM-5", used: 30000),
        ModelTokenRecord(date: "2026-04-15", model: "GLM-4", used: 60000),
        ModelTokenRecord(date: "2026-04-15", model: "GLM-5", used: 40000),
    ], totalTokens: 180000)
    .padding()
}
