import Foundation

enum SharedConstants {
    /// MUST match the App Group entitlement configured on BOTH targets
    /// (see project.yml). If you rename it, rename it in both places.
    static let appGroupIdentifier = "group.com.networkconditioner.shared"

    /// Where the last-applied profile is cached so the extension can
    /// pick it up on cold start, before the app has a chance to send
    /// a live provider message.
    static let profileDefaultsKey = "currentConditionProfile"

    /// MUST match the extension target's bundle identifier
    /// (PRODUCT_BUNDLE_IDENTIFIER in project.yml).
    static let extensionBundleIdentifier = "com.networkconditioner.app.extension"
}
