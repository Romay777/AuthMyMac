public struct StorageNamespace: Equatable, Sendable {
    public let metadataKey: String
    public let keychainService: String

    public init(metadataKey: String, keychainService: String) {
        self.metadataKey = metadataKey
        self.keychainService = keychainService
    }

    // Keep the historical namespace attached to development builds because
    // BUILD.sh has produced debug bundles by default since the project began.
    public static let development = StorageNamespace(
        metadataKey: "AuthMyMac.accounts.v1",
        keychainService: "dev.geeky.AuthMyMac"
    )

    public static let release = StorageNamespace(
        metadataKey: "AuthMyMac.accounts.v1.release",
        keychainService: "dev.geeky.AuthMyMac.release"
    )

    public static var current: StorageNamespace {
#if DEBUG
        .development
#else
        .release
#endif
    }
}
