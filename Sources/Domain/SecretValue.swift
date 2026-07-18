import Foundation

/// A deliberately non-Codable wrapper whose textual representations are always redacted.
public struct SecretValue: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    private let storage: Data

    public init(_ data: Data) {
        storage = data
    }

    public func data() -> Data {
        storage
    }

    public var description: String {
        "<redacted>"
    }

    public var debugDescription: String {
        "<redacted>"
    }
}
