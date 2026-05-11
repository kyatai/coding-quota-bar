import Foundation
import WatchConnectivity

class WatchSyncManager: NSObject, WCSessionDelegate, ObservableObject {
    static let shared = WatchSyncManager()

    /// 同步状态，UI 可观察
    @Published var syncStatus: String = ""

    /// 缓存所有 provider 的 key，激活成功后重试发送
    private var pendingKeys: [String: String] = [:]

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// 同步所有启用的 provider API key 到 Watch
    func syncAllKeys(_ providers: [String: ProviderConfig]) {
        var dict: [String: String] = [:]
        for (key, config) in providers where config.enabled && !config.apiKey.isEmpty {
            dict[key] = config.apiKey
        }
        pendingKeys = dict
        trySend()
    }

    /// 同步单个 provider key
    func syncApiKey(_ provider: String, _ key: String) {
        guard !key.isEmpty else {
            pendingKeys.removeValue(forKey: provider)
            return
        }
        pendingKeys[provider] = key
        trySend()
    }

    // MARK: - Send Logic

    private func trySend() {
        guard WCSession.isSupported() else {
            syncStatus = "❌ WCSession 不支持"
            print("[WatchSync] ❌ WCSession not supported")
            return
        }

        let session = WCSession.default
        print("[WatchSync] state=\(session.activationState.rawValue) paired=\(session.isPaired) installed=\(session.isWatchAppInstalled) reachable=\(session.isReachable)")

        guard session.activationState == .activated else {
            syncStatus = "⏳ WCSession 未激活 (\(stateLabel(session.activationState)))"
            print("[WatchSync] ⏳ not activated: \(session.activationState)")
            return
        }
        guard session.isPaired else {
            syncStatus = "❌ 没有配对的 Apple Watch"
            print("[WatchSync] ❌ not paired")
            return
        }
        guard session.isWatchAppInstalled else {
            syncStatus = "❌ Watch 端未安装 App"
            print("[WatchSync] ❌ watch app not installed")
            return
        }

        var userInfo: [String: Any] = [:]
        for (provider, key) in pendingKeys {
            userInfo["\(provider)_apiKey"] = key
        }
        // 兼容旧版 Watch 端仍然读取 "zhipuApiKey"
        if let zhipuKey = pendingKeys["zhipu"] {
            userInfo["zhipuApiKey"] = zhipuKey
        }

        guard !userInfo.isEmpty else {
            syncStatus = "⚠️ 没有需要同步的 Key"
            return
        }

        // 优先用 transferUserInfo（可靠排队送达）
        session.transferUserInfo(userInfo)

        let keyList = pendingKeys.keys.joined(separator: ", ")
        syncStatus = "✅ 已发送 (\(keyList))"
        print("[WatchSync] ✅ sent keys: \(keyList)")

        // 同时尝试实时通道
        trySendMessage()
    }

    /// 用 interactive message 实时推送（Watch 前台时可立即收到）
    private func trySendMessage() {
        guard WCSession.isSupported(),
              WCSession.default.activationState == .activated,
              WCSession.default.isReachable else { return }

        var userInfo: [String: Any] = [:]
        for (provider, key) in pendingKeys {
            userInfo["\(provider)_apiKey"] = key
        }
        if let zhipuKey = pendingKeys["zhipu"] {
            userInfo["zhipuApiKey"] = zhipuKey
        }

        guard !userInfo.isEmpty else { return }
        WCSession.default.sendMessage(userInfo, replyHandler: nil) { error in
            print("[WatchSync] sendMessage error: \(error.localizedDescription)")
        }
        print("[WatchSync] 📨 sendMessage sent (realtime)")
    }

    private func stateLabel(_ state: WCSessionActivationState) -> String {
        switch state {
        case .notActivated: return "未激活"
        case .inactive: return "非活跃"
        case .activated: return "已激活"
        @unknown default: return "未知"
        }
    }

    // MARK: - WCSessionDelegate (required on iOS)

    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        print("[WatchSync] activationDidComplete: state=\(activationState.rawValue) error=\(error?.localizedDescription ?? "nil")")
        if activationState == .activated {
            DispatchQueue.main.async {
                self.trySend()
            }
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    /// Watch 变为可达时，实时推送
    func sessionReachabilityDidChange(_ session: WCSession) {
        print("[WatchSync] reachability changed: reachable=\(session.isReachable)")
        if session.isReachable {
            DispatchQueue.main.async {
                self.trySendMessage()
            }
        }
    }
}
