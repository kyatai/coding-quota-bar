import SwiftUI

struct MainView: View {
    @ObservedObject var store: DataStore
    @Binding var showSettings: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if store.isLoading && store.usageState.providers.isEmpty {
                        loadingSkeleton
                    } else if store.usageState.providers.isEmpty {
                        emptyState
                    } else {
                        ForEach(store.usageState.providers) { provider in
                            providerSection(provider)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Coding Quota Bar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        if store.isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }

                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if !store.usageState.lastUpdate.isEmpty {
                    Text(formatRelativeTime(store.usageState.lastUpdate))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 8)
                }
            }
            .refreshable {
                await store.refresh()
            }
        }
    }

    // MARK: - Provider Section

    @ViewBuilder
    private func providerSection(_ provider: ProviderUsageData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Provider name + level badge
            HStack {
                Text(provider.name)
                    .font(.headline)
                    .fontWeight(.bold)
                if let level = provider.level {
                    Text(level.uppercased())
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor)
                        .cornerRadius(4)
                }
            }

            // Error card
            if let error = provider.error {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(2)
                }
                .padding(10)
                .background(Color.red.opacity(0.08))
                .cornerRadius(8)
            }

            // Quota cards
            let tokensQuotas = provider.quotas.filter { $0.limitType == "tokens" }
            let otherQuotas = provider.quotas.filter { $0.limitType != "tokens" }

            // Non-token quotas: full width
            ForEach(otherQuotas) { quota in
                QuotaCardView(quota: quota)
            }

            // Token quotas: paired side by side
            let pairs = stride(from: 0, to: tokensQuotas.count, by: 2).map {
                Array(tokensQuotas[$0..<min($0+2, tokensQuotas.count)])
            }
            ForEach(pairs, id: \.first!.id) { pair in
                HStack(spacing: 8) {
                    ForEach(pair) { quota in
                        QuotaCardView(quota: quota)
                    }
                }
            }

            // Charts (if data exists)
            let hasModel = !provider.modelHistory7d.isEmpty
            let hasMcp = !provider.mcpHistory7d.isEmpty
            if hasModel || hasMcp {
                UsageStatsView(provider: provider)
            }
        }
        .padding(12)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }

    // MARK: - Loading Skeleton

    private var loadingSkeleton: some View {
        VStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.15))
                .frame(height: 20)
                .shimmer()
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.gray.opacity(0.1))
                .frame(height: 70)
                .shimmer()
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.gray.opacity(0.1))
                .frame(height: 70)
                .shimmer()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("暂无监控已启用")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("请在设置中添加 Provider 并输入 API Key")
                .font(.caption)
                .foregroundColor(.secondary)
            Button("前往设置") {
                showSettings = true
            }
            .buttonStyle(.bordered)
        }
        .padding(.top, 60)
    }
}

// MARK: - Shimmer Modifier

extension View {
    func shimmer() -> some View {
        self.modifier(ShimmerModifier())
    }
}

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay {
                LinearGradient(
                    colors: [.clear, .white.opacity(0.3), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: phase)
                .animation(
                    .easeInOut(duration: 1.5)
                    .repeatForever(autoreverses: false),
                    value: phase
                )
                .onAppear { phase = 300 }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
