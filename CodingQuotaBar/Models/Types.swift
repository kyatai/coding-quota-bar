import Foundation

// MARK: - Display Color

enum DisplayColor: String, Codable {
    case green, yellow, red

    var colorHex: String {
        switch self {
        case .green:  return "#22C55E"
        case .yellow: return "#F59E0B"
        case .red:    return "#EF4444"
        }
    }
}

// MARK: - Quota Item (display)

struct QuotaItem: Identifiable, Codable {
    var id = UUID()
    var label: String
    var labelParams: [String: StringValue]?
    var used: Double
    var total: Double
    var usageRate: Double      // 0-100
    var resetAt: String
    var color: DisplayColor
    var limitType: String?

    enum StringValue: Codable {
        case string(String)
        case int(Int)
        case double(Double)

        var stringValue: String {
            switch self {
            case .string(let v): return v
            case .int(let v):    return String(v)
            case .double(let v): return String(v)
            }
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let v = try? container.decode(String.self) { self = .string(v) }
            else if let v = try? container.decode(Int.self) { self = .int(v) }
            else if let v = try? container.decode(Double.self) { self = .double(v) }
            else { self = .string("") }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let v): try container.encode(v)
            case .int(let v):    try container.encode(v)
            case .double(let v): try container.encode(v)
            }
        }
    }
}

// MARK: - Usage Records

struct UsageRecord: Identifiable, Codable {
    var id = UUID()
    var date: String
    var used: Double
}

struct McpUsageRecord: Identifiable, Codable {
    var id = UUID()
    var date: String
    var search: Double
    var webRead: Double
    var zread: Double
}

struct ModelTokenRecord: Identifiable, Codable {
    var id = UUID()
    var date: String
    var model: String
    var used: Double
}

// MARK: - Provider Display Data

struct ProviderUsageData: Identifiable, Codable {
    var id = UUID()
    var name: String
    var level: String?
    var error: String?
    var quotas: [QuotaItem]
    var history1d: [UsageRecord]
    var history7d: [UsageRecord]
    var history30d: [UsageRecord]
    var totalTokens1d: Double
    var totalTokens7d: Double
    var totalTokens30d: Double
    var mcpHistory1d: [McpUsageRecord]
    var mcpHistory7d: [McpUsageRecord]
    var mcpHistory30d: [McpUsageRecord]
    var modelHistory1d: [ModelTokenRecord]
    var modelHistory7d: [ModelTokenRecord]
    var modelHistory30d: [ModelTokenRecord]
}

// MARK: - Usage State (top-level)

struct UsageState: Codable {
    var providers: [ProviderUsageData]
    var lastUpdate: String
    var overallPercent: Double
}
