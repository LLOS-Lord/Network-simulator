import Foundation

/// A network condition profile applied uniformly to every flow the proxy
/// handles. There is no per-packet-type, per-size, or per-direction
/// selection here on purpose — the conditioner is meant to simulate a
/// uniformly bad network, not to single out specific traffic.
struct ConditionProfile: Codable, Equatable {
    /// Probability (0...100) that any given UDP datagram is dropped,
    /// in either direction, regardless of size or payload.
    var packetLossPercent: Double

    /// Extra delay (in milliseconds) added before relaying data,
    /// applied to both TCP and UDP, both directions.
    var delayMilliseconds: Double

    /// Master switch. When false, the proxy still relays traffic
    /// (so the VPN stays connected) but applies zero loss/delay.
    var isEnabled: Bool

    static let passthrough = ConditionProfile(packetLossPercent: 0, delayMilliseconds: 0, isEnabled: false)

    static let lossRange: ClosedRange<Double> = 0...100
    static let delayRange: ClosedRange<Double> = 0...5000

    func clamped() -> ConditionProfile {
        var copy = self
        copy.packetLossPercent = min(max(packetLossPercent, Self.lossRange.lowerBound), Self.lossRange.upperBound)
        copy.delayMilliseconds = min(max(delayMilliseconds, Self.delayRange.lowerBound), Self.delayRange.upperBound)
        return copy
    }

    var summary: String {
        guard isEnabled else { return "Tắt — mạng đi bình thường" }
        return "loss=\(Int(packetLossPercent))% delay=\(Int(delayMilliseconds))ms"
    }
}
