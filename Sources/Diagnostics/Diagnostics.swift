import Foundation

public enum DiagnosticsCategory: String, CaseIterable, Sendable {
    case appLifecycle = "app.lifecycle"
    case camera
    case screenCapture
    case qr
    case storage
    case export
}

public struct DiagnosticsMetadata: Equatable, Sendable {
    public enum ValidationError: Error, Equatable, Sendable {
        case sensitiveKey(String)
    }

    private static let sensitiveFragments = [
        "secret",
        "otp",
        "code",
        "uri",
        "payload",
        "account",
    ]

    public let values: [String: String]

    public init(_ values: [String: String] = [:]) throws {
        for key in values.keys {
            let normalizedKey = key.lowercased()
            guard !Self.sensitiveFragments.contains(where: normalizedKey.contains) else {
                throw ValidationError.sensitiveKey(key)
            }
        }
        self.values = values
    }
}

public struct DiagnosticsEvent: Equatable, Sendable {
    public let category: DiagnosticsCategory
    public let name: String
    public let metadata: DiagnosticsMetadata

    public init(category: DiagnosticsCategory, name: String, metadata: DiagnosticsMetadata) {
        self.category = category
        self.name = name
        self.metadata = metadata
    }
}

public protocol DiagnosticsRecording: Sendable {
    func record(_ event: DiagnosticsEvent)
}

public struct NoOpDiagnostics: DiagnosticsRecording {
    public init() {}

    public func record(_ event: DiagnosticsEvent) {}
}
