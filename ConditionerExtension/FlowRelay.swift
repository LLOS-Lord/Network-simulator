import Foundation
import NetworkExtension
import Network

/// Relays one TCP flow: reads bytes the app is sending, forwards them
/// to the real remote host over a genuine NWConnection, and writes
/// whatever comes back to the flow so the app receives it. Delay is
/// applied to every chunk in both directions. Packet loss is NOT
/// applied to TCP — dropping bytes mid-stream corrupts the connection
/// rather than simulating a lost-and-retransmitted packet, so loss is
/// scoped to UDP only (see UDPFlowRelay below).
final class TCPFlowRelay {
    private let flow: NEAppProxyTCPFlow
    private var connection: NWConnection?

    init(flow: NEAppProxyTCPFlow) {
        self.flow = flow
    }

    func start() {
        flow.open(withLocalEndpoint: nil) { [weak self] error in
            guard let self else { return }
            guard error == nil else {
                self.flow.closeReadAndWrite()
                return
            }
            guard let host = self.flow.remoteEndpoint as? NWHostEndpoint,
                  let port = NWEndpoint.Port(host.port) else {
                self.flow.closeReadAndWrite()
                return
            }
            let conn = NWConnection(host: NWEndpoint.Host(host.hostname), port: port, using: .tcp)
            self.connection = conn
            conn.start(queue: .global(qos: .userInitiated))
            self.pumpAppToRemote()
            self.pumpRemoteToApp(conn)
        }
    }

    private func pumpAppToRemote() {
        flow.readData { [weak self] data, error in
            guard let self, let connection = self.connection else { return }
            guard let data, error == nil, !data.isEmpty else {
                connection.cancel()
                self.flow.closeReadAndWrite()
                return
            }
            let delay = ConditionProfileStore.shared.profile.delaySeconds
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                connection.send(content: data, completion: .contentProcessed { _ in
                    self.pumpAppToRemote()
                })
            }
        }
    }

    private func pumpRemoteToApp(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                let delay = ConditionProfileStore.shared.profile.delaySeconds
                DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                    self.flow.write(data) { _ in
                        if !isComplete && error == nil {
                            self.pumpRemoteToApp(connection)
                        }
                    }
                }
            } else if !isComplete && error == nil {
                self.pumpRemoteToApp(connection)
            }
            if isComplete || error != nil {
                self.flow.closeReadAndWrite()
                connection.cancel()
            }
        }
    }
}

/// Relays one UDP flow. Each datagram, in each direction, independently
/// has `packetLossPercent` chance of being dropped — this is a real
/// datagram-level loss, the same kind a lossy radio link produces,
/// applied without regard to size, content, or which side sent it.
final class UDPFlowRelay {
    private let flow: NEAppProxyUDPFlow
    private let queue = DispatchQueue(label: "udp.flow.relay")
    private var connectionsByEndpoint: [String: NWConnection] = [:]

    init(flow: NEAppProxyUDPFlow) {
        self.flow = flow
    }

    func start() {
        flow.open(withLocalEndpoint: nil) { [weak self] error in
            guard let self, error == nil else {
                self?.flow.closeReadAndWrite()
                return
            }
            self.pumpAppToRemote()
        }
    }

    private func pumpAppToRemote() {
        flow.readDatagrams { [weak self] datagrams, endpoints, error in
            guard let self else { return }
            guard error == nil, let datagrams, let endpoints else {
                self.flow.closeReadAndWrite()
                return
            }
            let profile = ConditionProfileStore.shared.profile
            for (index, datagram) in datagrams.enumerated() {
                guard index < endpoints.count else { continue }
                let endpoint = endpoints[index]
                if profile.shouldDrop {
                    continue // simulated loss, outbound direction
                }
                let delay = profile.delaySeconds
                self.queue.asyncAfter(deadline: .now() + delay) {
                    self.send(datagram, to: endpoint)
                }
            }
            self.pumpAppToRemote()
        }
    }

    private func send(_ data: Data, to endpoint: NWEndpoint) {
        let connection = connection(for: endpoint)
        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    private func connection(for endpoint: NWEndpoint) -> NWConnection {
        let key = "\(endpoint)"
        if let existing = connectionsByEndpoint[key] {
            return existing
        }
        let connection = NWConnection(to: endpoint, using: .udp)
        connectionsByEndpoint[key] = connection
        connection.start(queue: queue)
        listenForReplies(connection, originalEndpoint: endpoint)
        return connection
    }

    private func listenForReplies(_ connection: NWConnection, originalEndpoint: NWEndpoint) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                let profile = ConditionProfileStore.shared.profile
                if !profile.shouldDrop {
                    let delay = profile.delaySeconds
                    self.queue.asyncAfter(deadline: .now() + delay) {
                        self.flow.writeDatagrams([data], sentTo: [originalEndpoint]) { _ in }
                    }
                }
            }
            if error == nil {
                self.listenForReplies(connection, originalEndpoint: originalEndpoint)
            } else {
                self.connectionsByEndpoint.removeValue(forKey: "\(originalEndpoint)")
            }
        }
    }
}

private extension ConditionProfile {
    var delaySeconds: Double {
        isEnabled ? delayMilliseconds / 1000.0 : 0
    }

    var shouldDrop: Bool {
        isEnabled && Double.random(in: 0..<100) < packetLossPercent
    }
}

extension NEAppProxyFlow {
    func closeReadAndWrite() {
        closeReadWithError(nil)
        closeWriteWithError(nil)
    }
}
