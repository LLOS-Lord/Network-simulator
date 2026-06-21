import Foundation
import NetworkExtension
import Combine

@MainActor
final class ConditionerManager: ObservableObject {
    @Published var isConnected: Bool = false
    @Published var statusMessage: String = "Chưa kết nối"

    /// Changing this immediately persists to the App Group (so a fresh
    /// extension launch picks it up) AND, if the tunnel is already
    /// running, sends a live provider message — no stop/start needed.
    @Published var profile: ConditionProfile = .passthrough {
        didSet {
            guard profile != oldValue else { return }
            profile = profile.clamped()
            persistProfile()
            applyProfileLive()
        }
    }

    private var manager: NETransparentProxyManager?
    private var statusObserver: NSObjectProtocol?

    init() {
        loadCachedProfile()
        Task { await loadExistingManager() }
    }

    deinit {
        if let statusObserver {
            NotificationCenter.default.removeObserver(statusObserver)
        }
    }

    // MARK: - Setup / load existing configuration

    private func loadExistingManager() async {
        do {
            let managers = try await NETransparentProxyManager.loadAllFromPreferences()
            if let existing = managers.first {
                manager = existing
                isConnected = existing.connection.status == .connected
                statusMessage = describe(existing.connection.status)
                observe(existing)
            }
        } catch {
            statusMessage = "Lỗi tải cấu hình: \(error.localizedDescription)"
        }
    }

    private func observe(_ manager: NETransparentProxyManager) {
        if let statusObserver {
            NotificationCenter.default.removeObserver(statusObserver)
        }
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: manager.connection,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.isConnected = manager.connection.status == .connected
                self.statusMessage = self.describe(manager.connection.status)
                if self.isConnected {
                    // Tunnel just came up (fresh start or auto-reconnect) —
                    // make sure it has the latest profile right away.
                    self.applyProfileLive()
                }
            }
        }
    }

    private func describe(_ status: NEVPNStatus) -> String {
        switch status {
        case .connected: return "Đang chạy"
        case .connecting: return "Đang kết nối..."
        case .disconnecting: return "Đang ngắt..."
        case .disconnected: return "Đã ngắt"
        case .invalid: return "Cấu hình không hợp lệ — bấm Bắt đầu để tạo lại"
        case .reasserting: return "Đang thiết lập lại..."
        @unknown default: return "Không rõ trạng thái"
        }
    }

    // MARK: - Start / stop

    func start() async {
        do {
            let mgr = manager ?? NETransparentProxyManager()
            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = SharedConstants.extensionBundleIdentifier
            proto.serverAddress = "Local Network Conditioner"
            mgr.localizedDescription = "Network Conditioner"
            mgr.protocolConfiguration = proto
            mgr.isEnabled = true

            try await mgr.saveToPreferences()
            try await mgr.loadFromPreferences()

            manager = mgr
            observe(mgr)

            try mgr.connection.startVPNTunnel()
            statusMessage = "Đang khởi động..."
        } catch {
            statusMessage = "Lỗi khởi động: \(error.localizedDescription)"
        }
    }

    func stop() {
        manager?.connection.stopVPNTunnel()
    }

    // MARK: - Live profile updates (no reconnect required)

    private func applyProfileLive() {
        guard let session = manager?.connection as? NETunnelProviderSession,
              manager?.connection.status == .connected,
              let data = try? JSONEncoder().encode(profile) else {
            return
        }
        do {
            try session.sendProviderMessage(data) { [weak self] response in
                guard let self, let response, let text = String(data: response, encoding: .utf8) else { return }
                Task { @MainActor in
                    self.statusMessage = "Đang chạy — \(text)"
                }
            }
        } catch {
            statusMessage = "Lỗi gửi cấu hình tới extension: \(error.localizedDescription)"
        }
    }

    // MARK: - Persistence (App Group, read by extension on cold start)

    private func persistProfile() {
        guard let defaults = UserDefaults(suiteName: SharedConstants.appGroupIdentifier),
              let data = try? JSONEncoder().encode(profile) else { return }
        defaults.set(data, forKey: SharedConstants.profileDefaultsKey)
    }

    private func loadCachedProfile() {
        guard let defaults = UserDefaults(suiteName: SharedConstants.appGroupIdentifier),
              let data = defaults.data(forKey: SharedConstants.profileDefaultsKey),
              let saved = try? JSONDecoder().decode(ConditionProfile.self, from: data) else { return }
        profile = saved
    }
}
