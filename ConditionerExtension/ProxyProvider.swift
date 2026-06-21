import NetworkExtension
import os.log

final class ProxyProvider: NETransparentProxyProvider {
    private let log = OSLog(subsystem: "com.networkconditioner.app.extension", category: "ProxyProvider")

    // Keep strong references so relays aren't deallocated mid-flow.
    private var activeTCPRelays: [ObjectIdentifier: TCPFlowRelay] = [:]
    private var activeUDPRelays: [ObjectIdentifier: UDPFlowRelay] = [:]
    private let relaysLock = NSLock()

    override func startProxy(options: [String: Any]? = nil, completionHandler: @escaping (Error?) -> Void) {
        os_log(.info, log: log, "startProxy")

        // Pick up whatever profile the app last saved, in case this is
        // a cold launch (device reboot, on-demand reconnect) and the
        // app hasn't sent a live message yet this session.
        if let defaults = UserDefaults(suiteName: SharedConstants.appGroupIdentifier),
           let data = defaults.data(forKey: SharedConstants.profileDefaultsKey),
           let saved = try? JSONDecoder().decode(ConditionProfile.self, from: data) {
            ConditionProfileStore.shared.update(saved)
        }

        let settings = NETransparentProxyNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        let rule = NENetworkRule(
            remoteNetwork: nil,
            remotePrefix: 0,
            localNetwork: nil,
            localPrefix: 0,
            protocol: .any,
            direction: .outbound
        )
        settings.includedNetworkRules = [rule]

        setTunnelNetworkSettings(settings) { error in
            if let error {
                os_log(.error, log: self.log, "setTunnelNetworkSettings failed: %{public}@", error.localizedDescription)
            }
            completionHandler(error)
        }
    }

    override func stopProxy(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        os_log(.info, log: log, "stopProxy reason=%{public}d", reason.rawValue)
        completionHandler()
    }

    override func handleNewFlow(_ flow: NEAppProxyFlow) -> Bool {
        if let tcpFlow = flow as? NEAppProxyTCPFlow {
            let relay = TCPFlowRelay(flow: tcpFlow)
            store(relay, for: tcpFlow)
            relay.start()
            return true
        }
        if let udpFlow = flow as? NEAppProxyUDPFlow {
            let relay = UDPFlowRelay(flow: udpFlow)
            store(relay, for: udpFlow)
            relay.start()
            return true
        }
        return false
    }

    /// Live profile push from the app — applied to every flow already
    /// open, no reconnect involved. See ConditionerManager.applyProfileLive().
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)? = nil) {
        guard let profile = try? JSONDecoder().decode(ConditionProfile.self, from: messageData) else {
            completionHandler?(nil)
            return
        }
        ConditionProfileStore.shared.update(profile)

        if let defaults = UserDefaults(suiteName: SharedConstants.appGroupIdentifier),
           let data = try? JSONEncoder().encode(profile) {
            defaults.set(data, forKey: SharedConstants.profileDefaultsKey)
        }

        completionHandler?(profile.summary.data(using: .utf8))
    }

    // MARK: - Relay bookkeeping (just keeps strong refs alive)

    private func store(_ relay: TCPFlowRelay, for flow: NEAppProxyTCPFlow) {
        relaysLock.lock()
        activeTCPRelays[ObjectIdentifier(flow)] = relay
        relaysLock.unlock()
    }

    private func store(_ relay: UDPFlowRelay, for flow: NEAppProxyUDPFlow) {
        relaysLock.lock()
        activeUDPRelays[ObjectIdentifier(flow)] = relay
        relaysLock.unlock()
    }
}
