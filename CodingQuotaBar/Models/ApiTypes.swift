import Foundation

// MARK: - App Config

struct AppConfig: Codable, Equatable {
    var refreshInterval: Int = 300            // seconds
    var providers: [String: ProviderConfig] = ["zhipu": ProviderConfig()]
    var display: DisplayConfig = DisplayConfig()
    var autoStart: Bool = false
    var language: String = "zh-CN"
    var theme: String = "auto"                // light, dark, auto

    struct DisplayConfig: Codable, Equatable {
        var colorThresholds: ColorThresholds = ColorThresholds()
    }

    struct ColorThresholds: Codable, Equatable {
        var green: Double = 50
        var yellow: Double = 20
    }
}

struct ProviderConfig: Codable, Equatable {
    var enabled: Bool = false
    var apiKey: String = ""
}

// MARK: - Zhipu API Response Types

struct ZhipuLimitResponse: Codable {
    let code: Int?
    let data: ZhipuLimitData?
    let msg: String?
    let success: Bool?
}

struct ZhipuLimitData: Codable {
    let limits: [ZhipuLimitItem]?
    let level: String?
}

struct ZhipuLimitItem: Codable {
    let type: String?
    let unit: Int?
    let number: Double?
    let usage: Double?
    let currentValue: Double?
    let remaining: Double?
    let percentage: Double?
    let nextResetTime: Double?           // epoch ms
    let usageDetails: [ZhipuUsageDetail]?

    struct ZhipuUsageDetail: Codable {
        let modelCode: String?
        let usage: Double?
    }
}

struct ZhipuModelUsageResponse: Codable {
    let code: Int?
    let data: ZhipuModelUsageData?
    let msg: String?
    let success: Bool?
}

struct ZhipuModelUsageData: Codable {
    let x_time: [String]?
    let modelDataList: [ZhipuModelDataItem]?
    let totalUsage: ZhipuModelTotal?
}

struct ZhipuModelDataItem: Codable {
    let modelName: String?
    let sortOrder: Int?
    let tokensUsage: [Double]?
    let totalTokens: Double?
}

struct ZhipuModelTotal: Codable {
    let totalModelCallCount: Double?
    let totalTokensUsage: Double?
}

struct ZhipuToolUsageResponse: Codable {
    let code: Int?
    let data: ZhipuToolUsageData?
    let msg: String?
    let success: Bool?
}

struct ZhipuToolUsageData: Codable {
    let x_time: [String]?
    let networkSearchCount: [Double]?
    let webReadMcpCount: [Double]?
    let zreadMcpCount: [Double]?
    let totalUsage: ZhipuToolTotal?
}

struct ZhipuToolTotal: Codable {
    let totalNetworkSearchCount: Double?
    let totalWebReadMcpCount: Double?
    let totalZreadMcpCount: Double?
}

// MARK: - Usage Result (internal aggregation)

struct UsageResult {
    var used: Double
    var total: Double
    var expiresAt: String
    var level: String?
    var error: String?
    var details: UsageDetails
}

struct UsageDetails {
    var quotas: [QuotaItem] = []
    var history1d: [UsageRecord] = []
    var history7d: [UsageRecord] = []
    var history30d: [UsageRecord] = []
    var totalTokens1d: Double = 0
    var totalTokens7d: Double = 0
    var totalTokens30d: Double = 0
    var mcpHistory1d: [McpUsageRecord] = []
    var mcpHistory7d: [McpUsageRecord] = []
    var mcpHistory30d: [McpUsageRecord] = []
    var modelHistory1d: [ModelTokenRecord] = []
    var modelHistory7d: [ModelTokenRecord] = []
    var modelHistory30d: [ModelTokenRecord] = []
}
