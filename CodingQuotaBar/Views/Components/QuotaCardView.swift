import SwiftUI

struct QuotaCardView: View {
    let quota: QuotaItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top row: label + percentage
            HStack {
                Text(quota.label)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text(String(format: "%.0f%%", 100 - quota.usageRate))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(colorForDisplay(quota.color))
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.15))
                        .frame(height: 6)

                    // Fill
                    RoundedRectangle(cornerRadius: 3)
                        .fill(gradientForDisplay(quota.color))
                        .frame(
                            width: max(0, geo.size.width * CGFloat((100 - quota.usageRate) / 100)),
                            height: 6
                        )
                }
            }
            .frame(height: 6)

            // Reset time
            Text(quota.resetAt)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(10)
    }

    private func colorForDisplay(_ color: DisplayColor) -> Color {
        switch color {
        case .green:  return .green
        case .yellow: return .orange
        case .red:    return .red
        }
    }

    private func gradientForDisplay(_ color: DisplayColor) -> LinearGradient {
        let colors: [Color] = {
            switch color {
            case .green:  return [.green, .green.opacity(0.7)]
            case .yellow: return [.orange, .orange.opacity(0.7)]
            case .red:    return [.red, .red.opacity(0.7)]
            }
        }()
        return LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    }
}

#Preview {
    QuotaCardView(quota: QuotaItem(
        label: "Token额度",
        used: 750000,
        total: 1000000,
        usageRate: 75,
        resetAt: "2小时后重置",
        color: .green,
        limitType: "tokens"
    ))
    .padding()
}
