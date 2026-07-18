import CoreGraphics
import Foundation
import QR

public struct ScreenRegion: Equatable, Sendable {
    public let displayID: UInt32
    public let rectangle: CGRect

    public init(displayID: UInt32, rectangle: CGRect) {
        self.displayID = displayID
        self.rectangle = rectangle
    }
}

public protocol ScreenRegionCapturing: Sendable {
    func selectRegion() async throws -> ScreenRegion
    func captureAndDecode(_ region: ScreenRegion) async throws -> QRPayload
    func cancel() async
}

public enum ScreenCaptureError: LocalizedError, Equatable, Sendable {
    case permissionDenied
    case selectionCancelled
    case invalidRegion
    case noQRCodeFound
    case captureFailed

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Screen Recording access is required. Allow AuthMyMac in System Settings > Privacy & Security > Screen Recording, then quit and reopen the app."
        case .selectionCancelled:
            "Screen selection was cancelled."
        case .invalidRegion:
            "Select a larger screen area around the QR code."
        case .noQRCodeFound:
            "No supported authenticator QR code was found in the selected area. Include the entire QR code and its white border."
        case .captureFailed:
            "The selected screen area could not be captured. Try again after quitting and reopening AuthMyMac."
        }
    }
}
