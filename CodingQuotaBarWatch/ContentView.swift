import SwiftUI

// MARK: - Root

struct ContentView: View {
    @EnvironmentObject var store: WatchDataStore

    var body: some View {
        NavigationStack {
            if store.apiKey.isEmpty {
                SetupView()
            } else {
                QuotaListView()
            }
        }
    }
}

// MARK: - Quota List

struct QuotaListView: View {
    @EnvironmentObject var store: WatchDataStore

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ringView
                if let err = store.error {
                    errorCard(err)
                }
                if !store.quotas.isEmpty {
                    quotaRows
                }
                footerRow
                settingsLink
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .navigationTitle("Quota Bar")
        .onAppear { Task { await store.refresh() } }
    }

    // MARK: - Ring

    private var ringView: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 8)
            Circle()
                .trim(from: 0, to: CGFloat(store.tokenPercent / 100))
                .stroke(store.tokenColor,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.5), value: store.tokenPercent)
            VStack(spacing: 1) {
                if store.isLoading {
                    ProgressView().scaleEffect(0.7)
                } else {
                    Text(String(format: "%.0f%%", store.tokenPercent))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(store.tokenColor)
                    Text("Token")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(width: 96, height: 96)
        .padding(.top, 4)
    }

    // MARK: - Error

    @ViewBuilder
    private func errorCard(_ msg: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(.red)
                .font(.caption)
            Text(msg)
                .font(.caption2)
                .foregroundColor(.red)
                .lineLimit(2)
        }
        .padding(8)
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - Quota Rows

    private var quotaRows: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(store.quotas) { quota in
                WatchQuotaRowView(quota: quota)
                if quota.id != store.quotas.last?.id {
                    Divider()
                }
            }
        }
        .padding(.horizontal, 2)
    }

    // MARK: - Footer

    private var footerRow: some View {
        HStack {
            if let update = store.lastUpdate {
                Text(relativeTime(update))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Settings Link

    private var settingsLink: some View {
        NavigationLink {
            WatchSettingsView()
        } label: {
            Label("设置", systemImage: "gearshape")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }
}

// MARK: - Quota Row

struct WatchQuotaRowView: View {
    let quota: WatchQuota

    private var color: Color {
        if quota.remainingPercent >= 50 { return .green }
        if quota.remainingPercent >= 20 { return .orange }
        return .red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(quota.label)
                    .font(.system(size: 11))
                    .lineLimit(1)
                Spacer()
                Text(String(format: "%.0f%%", quota.remainingPercent))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.primary.opacity(0.12))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: geo.size.width * quota.remainingPercent / 100)
                }
            }
            .frame(height: 4)
            if !quota.resetAt.isEmpty {
                Text(quota.resetAt)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Setup View

struct SetupView: View {
    @EnvironmentObject var store: WatchDataStore
    @State private var tempKey = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: "key.fill")
                    .font(.title3)
                    .foregroundColor(.yellow)

                Text("输入 Z AI API Key")
                    .font(.caption)
                    .multilineTextAlignment(.center)

                TextField("API Key", text: $tempKey)
                    .font(.system(size: 10, design: .monospaced))
                    .padding(6)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(6)

                Button("确认") {
                    store.apiKey = tempKey.trimmingCharacters(in: .whitespaces)
                    Task { await store.refresh() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .font(.caption)
                .disabled(tempKey.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(10)
        }
        .navigationTitle("设置")
    }
}

// MARK: - Settings View

struct WatchSettingsView: View {
    @EnvironmentObject var store: WatchDataStore
    @State private var tempKey = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("API Key")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                TextField("API Key", text: $tempKey)
                    .font(.system(size: 10, design: .monospaced))
                    .padding(6)
                    .background(Color.gray.opacity(0.15))
                    .cornerRadius(6)

                Button("保存") {
                    store.apiKey = tempKey.trimmingCharacters(in: .whitespaces)
                    Task { await store.refresh() }
                }
                .tint(.green)
                .font(.caption)

                Divider()

                Button("清除配置") {
                    store.apiKey = ""
                    store.quotas = []
                    tempKey = ""
                }
                .foregroundColor(.red)
                .font(.caption)
            }
            .padding(10)
        }
        .navigationTitle("设置")
        .onAppear { tempKey = store.apiKey }
    }
}

// MARK: - Helpers

private func relativeTime(_ date: Date) -> String {
    let diff = Int(Date().timeIntervalSince(date))
    if diff < 60 { return "刚刚" }
    if diff < 3600 { return "\(diff / 60)分钟前" }
    return "\(diff / 3600)小时前"
}
