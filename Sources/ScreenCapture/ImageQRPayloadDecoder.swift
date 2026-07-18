import CoreGraphics
import Foundation
import ImageIO
import QR

public struct ImageQRPayloadDecoder: Sendable {
    private let visionDecoder: VisionQRPayloadDecoder

    public init(decoder: any QRPayloadDecoding = QRPayloadDecoder()) {
        self.visionDecoder = VisionQRPayloadDecoder(decoder: decoder)
    }

    public func decode(contentsOf url: URL) throws -> QRPayload {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ImageQRImportError.unreadableImage
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 4096,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImageQRImportError.unreadableImage
        }
        return try visionDecoder.decode(image)
    }
}

public enum ImageQRImportError: LocalizedError, Equatable, Sendable {
    case unreadableImage

    public var errorDescription: String? {
        "The selected image could not be read. Choose a PNG, JPEG, or HEIC image containing a supported QR code."
    }
}
