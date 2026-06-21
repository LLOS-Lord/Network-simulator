import Foundation

/// Thread-safe holder for the profile currently in effect. Every flow
/// relay (TCP and UDP, many running concurrently) reads from here on
/// each read/write cycle, so a live update from the app applies to
/// already-open connections immediately — no flow needs to be torn
/// down and reopened.
final class ConditionProfileStore: @unchecked Sendable {
    static let shared = ConditionProfileStore()

    private let lock = NSLock()
    private var _profile: ConditionProfile = .passthrough

    private init() {}

    var profile: ConditionProfile {
        lock.lock()
        defer { lock.unlock() }
        return _profile
    }

    func update(_ newProfile: ConditionProfile) {
        lock.lock()
        _profile = newProfile.clamped()
        lock.unlock()
    }
}
