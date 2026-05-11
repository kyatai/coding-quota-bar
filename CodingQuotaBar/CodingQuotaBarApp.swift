import SwiftUI

@main
struct CodingQuotaBarApp: App {
    @StateObject private var store: DataStore
    @StateObject private var themeManager = ThemeManager()
    @State private var config: AppConfig
    @State private var showSettings = false

    init() {
        let manager = ConfigManager()
        let loadedConfig = manager.load()
        _config = State(initialValue: loadedConfig)
        _store = StateObject(wrappedValue: DataStore(config: loadedConfig))
    }

    var body: some Scene {
        WindowGroup {
            contentView
            .environmentObject(themeManager)
            .onAppear {
                _ = WatchSyncManager.shared  // activate WCSession
                store.startRefresh(interval: TimeInterval(config.refreshInterval))
                Task { await store.refresh() }
                // sync all enabled provider keys to Watch on launch
                WatchSyncManager.shared.syncAllKeys(config.providers)
            }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        MainView(store: store, showSettings: $showSettings)
            .sheet(isPresented: $showSettings) {
                SettingsView(store: store, config: $config, showSettings: $showSettings)
            }
            .preferredColorScheme(themeManager.colorScheme)
            .onOpenURL { url in
                if url.host == "main" {
                    showSettings = false
                }
            }
    }
}

// MARK: - Theme Manager

class ThemeManager: ObservableObject {
    @Published var theme: String = "auto" {
        didSet {
            UserDefaults.standard.set(theme, forKey: "appTheme")
        }
    }

    var colorScheme: ColorScheme? {
        switch theme {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil  // follow system
        }
    }

    init() {
        self.theme = UserDefaults.standard.string(forKey: "appTheme") ?? "auto"
    }
}
