import Foundation
import QR

public enum CameraAuthorizationState: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case unavailable
}

public struct MigrationScanProgress: Equatable, Sendable {
    public let scannedCount: Int
    public let totalCount: Int

    public init(scannedCount: Int, totalCount: Int) {
        self.scannedCount = scannedCount
        self.totalCount = totalCount
    }
}

/// Owns the lifecycle of one user-initiated camera scan.
public protocol CameraScanning: Sendable {
    func authorizationState() async -> CameraAuthorizationState
    func scan() async throws -> QRPayload
    func scan(
        onMigrationProgress: @escaping @Sendable (MigrationScanProgress) -> Void
    ) async throws -> QRPayload
    func stop() async
}

public extension CameraScanning {
    func scan(
        onMigrationProgress: @escaping @Sendable (MigrationScanProgress) -> Void
    ) async throws -> QRPayload {
        try await scan()
    }
}

public enum CameraScanError: LocalizedError, Equatable, Sendable {
    case permissionDenied
    case noDevice
    case cancelled
    case noQRCodeFound
    case invalidPayload

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Camera access is required to scan a QR code. Allow access in System Settings, then try again."
        case .noDevice:
            "No available camera was found."
        case .cancelled:
            "Camera scanning was cancelled."
        case .noQRCodeFound:
            "No QR code was found."
        case .invalidPayload:
            "The QR code is not a supported authenticator code."
        }
    }
}
