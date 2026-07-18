import Domain
import Foundation

/// Boundary for the RFC 6238 implementation. The concrete engine belongs in this module.
public protocol TOTPGenerating: Sendable {
    func code(
        for secret: SecretValue,
        account: OTPAccount,
        at date: Date
    ) async throws -> String
}

public enum TOTPGenerationError: Error, Equatable, Sendable {
    case invalidSecret
    case unsupportedConfiguration
}
