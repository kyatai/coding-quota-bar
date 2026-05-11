import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: DataStore
    @Binding var config: AppConfig
    @Binding var showSettings: Bool

    @State private var showApiKey: [String: Bool] = [:]
    @State private var saveStatus: String = ""
    @State private var saveTimer: Timer?

    private let refreshOptions: [(String, Int)] = [
        ("1分钟", 60), ("2分钟", 120), ("5分钟", 300),
        ("10分钟", 600), ("30分钟", 1800)
    ]

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Provider Section
                Section(header: Text("Provider")) {
                    ForEach(Array(config.providers.keys.sorted()), id: \.self) { key in
                        providerRow(key: key)
                    }
                }

                // MARK: - General Section
                Section(header: Text("通用设置")) {
                    // Refresh interval
                    Picker("刷新间隔", selection: $config.refreshInterval) {
                        ForEach(refreshOptions, id: \.1) { option in
                            Text(option.0).tag(option.1)
                        }
                    }

                    // Language
                    Picker("语言", selection: Binding(
                        get: { config.language },
                        set: { config.language = $0 }
                    )) {
                        Text("中文").tag("zh-CN")
                        Text("English").tag("en-US")
                    }

                    // Theme
                    Picker("主题", selection: Binding(
                        get: { config.theme },
                        set: { config.theme = $0 }
                    )) {
                        Text("浅色").tag("light")
                        Text("深色").tag("dark")
                        Text("跟随系统").tag("auto")
                    }
                }

                // MARK: - Color Thresholds
                Section(header: Text("颜色阈值")) {
                    VStack(alignment: .leading) {
                        Text("绿色阈值: \(Int(config.display.colorThresholds.green))%")
                            .font(.caption)
                        Slider(value: $config.display.colorThresholds.green, in: 0...100, step: 5)
                    }
                    VStack(alignment: .leading) {
                        Text("黄色阈值: \(Int(config.display.colorThresholds.yellow))%")
                            .font(.caption)
                        Slider(value: $config.display.colorThresholds.yellow, in: 0...100, step: 5)
                    }
                }

                // MARK: - Watch Sync
                Section(header: Text("Apple Watch 同步")) {
                    HStack {
                        Text("状态")
                            .font(.subheadline)
                        Spacer()
                        Text(WatchSyncManager.shared.syncStatus.isEmpty
                             ? "未同步"
                             : WatchSyncManager.shared.syncStatus)
                            .font(.caption)
                            .foregroundColor(syncStatusColor)
                    }
                    Button("手动同步到 Watch") {
                        WatchSyncManager.shared.syncAllKeys(config.providers)
                    }
                    .font(.subheadline)
                }

                // MARK: - About
                Section(header: Text("关于")) {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("完成") {
                        showSettings = false
                    }
                }
            }
            .onChange(of: config) { _ in
                saveConfig()
            }
        }
    }

    // MARK: - Provider Row

    @ViewBuilder
    private func providerRow(key: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle(isOn: Binding(
                    get: { config.providers[key]?.enabled ?? false },
                    set: { config.providers[key]?.enabled = $0 }
                )) {
                    Text(providerDisplayName(key))
                        .fontWeight(.medium)
                }
            }

            if config.providers[key]?.enabled == true {
                HStack {
                    if showApiKey[key] == true {
                        TextField("API Key", text: Binding(
                            get: { config.providers[key]?.apiKey ?? "" },
                            set: { config.providers[key]?.apiKey = $0 }
                        ))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.subheadline, design: .monospaced))
                    } else {
                        SecureField("API Key", text: Binding(
                            get: { config.providers[key]?.apiKey ?? "" },
                            set: { config.providers[key]?.apiKey = $0 }
                        ))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.subheadline, design: .monospaced))
                    }

                    Button {
                        showApiKey[key] = !(showApiKey[key] ?? false)
                    } label: {
                        Image(systemName: showApiKey[key] == true ? "eye.slash" : "eye")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func providerDisplayName(_ key: String) -> String {
        switch key {
        case "zhipu":  return "Z AI (智谱)"
        case "minimax": return "MiniMax"
        case "kimi":   return "Kimi"
        default:       return key
        }
    }

    private var syncStatusColor: Color {
        let s = WatchSyncManager.shared.syncStatus
        if s.contains("✅") { return .green }
        if s.contains("❌") { return .red }
        if s.contains("⏳") { return .orange }
        return .secondary
    }

    // MARK: - Auto Save

    private func saveConfig() {
        let manager = ConfigManager()
        manager.save(config)
        store.updateConfig(config)
        store.stopRefresh()
        store.startRefresh(interval: TimeInterval(config.refreshInterval))

        // 同步所有启用的 provider API key 到 Watch
        WatchSyncManager.shared.syncAllKeys(config.providers)

        saveStatus = "已保存"
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { _ in
            saveStatus = ""
        }
    }
}
