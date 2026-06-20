import SwiftUI

// MARK: - Shared state (ObservableObject so SwiftUI reacts)

class QuotaViewModel: ObservableObject {
    @Published var data: QuotaData?
    @Published var errorMessage: String?
    @Published var isFetching = false
}

@main
struct CodexGaugeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(delegate.viewModel)
                .frame(minWidth: 300, minHeight: 520)
        }
        .defaultSize(width: 300, height: 560)
    }
}

// MARK: - AppDelegate (background timer only)

class AppDelegate: NSObject, NSApplicationDelegate {
    let viewModel = QuotaViewModel()
    private var refreshTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let saved = QuotaStore.load() {
            viewModel.data = saved
        }

        Task { await fetchQuota() }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            Task { @MainActor in await self.fetchQuota() }
        }
    }

    @MainActor
    private func fetchQuota() async {
        guard !viewModel.isFetching else {
            print("[Gauge] Fetch skipped — already in progress")
            return
        }
        viewModel.isFetching = true
        defer { viewModel.isFetching = false }

        do {
            let data = try await QuotaFetcher.fetch()
            viewModel.data = data
            viewModel.errorMessage = nil
        } catch {
            print("[Gauge] Fetch error: \(error.localizedDescription)")
            viewModel.errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Main Content View

struct ContentView: View {
    @EnvironmentObject var viewModel: QuotaViewModel
    @State private var isPinned = false

    var body: some View {
        VStack(spacing: 0) {
            // ── Title bar ──
            HStack(spacing: 8) {
                Circle()
                    .fill(statusDotColor)
                    .frame(width: 7, height: 7)
                Text("CodexGauge")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Spacer()
                Button(action: togglePin) {
                    Image(systemName: isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 10))
                        .foregroundStyle(isPinned ? .blue : .secondary)
                }
                .buttonStyle(.plain)
                .help(isPinned ? "取消置顶" : "窗口置顶")
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            Divider().padding(.horizontal, 14)

            // ── Gauge ──
            GaugeDial(
                percent: Double(displayPercent),
                state: gaugeState
            )
            .frame(height: 210)
            .padding(.horizontal, 20)
            .padding(.top, 4)

            // Percentage + status
            VStack(spacing: 2) {
                Text("\(displayPercent)%")
                    .font(.system(size: 40, weight: .light, design: .rounded))
                    .foregroundStyle(gaugeColor)
                    .contentTransition(.numericText())
                    .animation(.default, value: displayPercent)

                Text(statusLabel)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.top, -2)
            }
            .padding(.top, -16)

            // ── Info pills ──
            if let data = viewModel.data {
                HStack(spacing: 8) {
                    InfoPill(label: "5hr", value: "\(data.primaryRemaining ?? 0)%")
                    InfoPill(label: "7d", value: "\(data.secondaryRemaining ?? 0)%")
                    InfoPill(label: "Plan", value: data.planType)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            // Reset time
            if let data = viewModel.data, let resetsAt = data.resetsAt {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Text("Resets \(resetsAt.formatted(.relative(presentation: .named)))")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 6)
            }

            Spacer(minLength: 6)

            // ── Proxy settings (collapsible) ──
            Divider().padding(.horizontal, 14)
            ProxySettingsView()
                .padding(.horizontal, 16)
                .padding(.vertical, 4)

            // ── Bottom bar ──
            Divider().padding(.horizontal, 14)
            HStack {
                Button(action: { Task { await refresh() } }) {
                    HStack(spacing: 4) {
                        if viewModel.isFetching {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.65)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 10))
                        }
                        Text("Refresh")
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isFetching)

                Spacer()

                Text(lastUpdatedText)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }

    // ── Computed properties ──

    private var displayPercent: Int {
        viewModel.data?.remainingPercent ?? 0
    }

    private var gaugeState: QuotaState {
        viewModel.data?.state ?? .ok
    }

    private var gaugeColor: Color {
        guard let d = viewModel.data else { return .gray }
        switch d.state {
        case .ok:     return Color(red: 0.15, green: 0.90, blue: 0.35)
        case .warning: return .yellow
        case .critical: return .red
        }
    }

    private var statusDotColor: Color {
        if viewModel.errorMessage != nil { return .red }
        if viewModel.isFetching { return .blue }
        return gaugeColor
    }

    private var statusLabel: String {
        if viewModel.isFetching && viewModel.data == nil { return "Connecting…" }
        if let err = viewModel.errorMessage, viewModel.data == nil { return err }
        guard let d = viewModel.data else { return "Loading…" }
        switch d.state {
        case .ok:      return "Quota healthy"
        case .warning: return "Running low"
        case .critical: return "Exhausted"
        }
    }

    private var lastUpdatedText: String {
        guard let data = viewModel.data else { return "—" }
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .abbreviated
        return fmt.localizedString(for: data.fetchedAt, relativeTo: Date())
    }

    // ── Actions ──

    private func togglePin() {
        isPinned.toggle()
        if let window = NSApp.windows.first(where: { $0.isVisible }) {
            window.level = isPinned ? .floating : .normal
        }
    }

    private func refresh() async {
        viewModel.errorMessage = nil
        do {
            let d = try await QuotaFetcher.fetch()
            viewModel.data = d
            viewModel.errorMessage = nil
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Reusable components

struct InfoPill: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Proxy Settings

struct ProxySettingsView: View {
    @State private var showSettings = false
    @State private var useSystemProxy = ProxySettings.useSystemProxy
    @State private var host = ProxySettings.manualHost
    @State private var port = ProxySettings.manualPort

    var body: some View {
        VStack(spacing: 4) {
            Button(action: { showSettings.toggle() }) {
                HStack(spacing: 4) {
                    Image(systemName: "network")
                        .font(.system(size: 9))
                    Text(proxySummary)
                        .font(.system(size: 9))
                    Spacer()
                    Image(systemName: showSettings ? "chevron.up" : "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                }
                .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)

            if showSettings {
                VStack(spacing: 6) {
                    Toggle("Use system proxy", isOn: $useSystemProxy)
                        .font(.system(size: 10))
                        .toggleStyle(.checkbox)
                        .onChange(of: useSystemProxy) { _, newValue in
                            ProxySettings.useSystemProxy = newValue
                        }

                    if !useSystemProxy {
                        HStack(spacing: 4) {
                            TextField("Host", text: $host)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 10))
                                .frame(width: 110)
                            Text(":")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                            TextField("Port", text: $port)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 10))
                                .frame(width: 50)
                            Spacer()
                        }
                        .onChange(of: host) { _, newValue in ProxySettings.manualHost = newValue }
                        .onChange(of: port) { _, newValue in ProxySettings.manualPort = newValue }
                    } else {
                        if let sys = ProxySettings.systemProxy() {
                            Text("Detected: \(sys.host):\(sys.port)")
                                .font(.system(size: 10))
                                .foregroundStyle(.green)
                        } else {
                            Text("No system proxy set")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private var proxySummary: String {
        if let p = ProxySettings.effective() {
            return "Proxy: \(p.host):\(p.port)"
        }
        return "No proxy"
    }
}
