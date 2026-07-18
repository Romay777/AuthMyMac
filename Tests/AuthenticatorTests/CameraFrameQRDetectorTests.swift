import CoreImage
import CoreVideo
import Domain
import Foundation
import QR
@testable import CameraCapture
import Testing

@Suite("Camera frame QR detection")
struct CameraFrameQRDetectorTests {
    @Test("Recognizes an authenticator QR rendered into a camera-sized pixel buffer")
    func recognizesQRCodeInCameraFrame() throws {
        let value = "otpauth://totp/Example:user?secret=JBSWY3DP&issuer=Example"
        let filter = try #require(CIFilter(name: "CIQRCodeGenerator"))
        filter.setValue(Data(value.utf8), forKey: "inputMessage")
        let qrImage = try #require(filter.outputImage)
            .transformed(by: .init(scaleX: 12, y: 12))
        let frameBounds = CGRect(x: 0, y: 0, width: 1280, height: 720)
        let background = CIImage(color: .white).cropped(to: frameBounds)
        let centeredQRCode = qrImage.transformed(by: .init(
            translationX: frameBounds.midX - qrImage.extent.midX,
            y: frameBounds.midY - qrImage.extent.midY
        ))
        let frame = centeredQRCode.composited(over: background)
        var storage: CVPixelBuffer?
        let attributes = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ] as CFDictionary
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(frameBounds.width),
            Int(frameBounds.height),
            kCVPixelFormatType_32BGRA,
            attributes,
            &storage
        )
        #expect(status == kCVReturnSuccess)
        let pixelBuffer = try #require(storage)
        let context = CIContext()
        context.render(
            frame,
            to: pixelBuffer,
            bounds: frameBounds,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        let values = try CameraFrameQRDetector().detectValues(
            in: pixelBuffer,
            orientation: .up
        )

        #expect(values.contains(value))
    }

    @Test("Reports a detected non-authenticator QR instead of ignoring it")
    func rejectsUnsupportedQRCode() {
        var decoder = CameraScannedValueDecoder()

        #expect(throws: CameraScanError.invalidPayload) {
            try decoder.decode("https://example.com")
        }
    }

    @Test("Keeps the first Google migration QR pending until the second arrives")
    func reassemblesTwoMigrationQRCodes() throws {
        let accounts = [
            migrationAccount(name: "first@example.com", secretByte: 1),
            migrationAccount(name: "second@example.com", secretByte: 2),
        ]
        let codec = MigrationPayloadCodec()
        let first = try codec.encode(
            [accounts[0]], batchSize: 2, batchIndex: 0, batchID: -42
        )
        let second = try codec.encode(
            [accounts[1]], batchSize: 2, batchIndex: 1, batchID: -42
        )
        var decoder = CameraScannedValueDecoder()

        #expect(try decoder.decode(first.absoluteString) == nil)
        #expect(decoder.takeMigrationProgress() == MigrationScanProgress(scannedCount: 1, totalCount: 2))
        #expect(try decoder.decode(second.absoluteString) == .migration(accounts))
    }

    private func migrationAccount(name: String, secretByte: UInt8) -> ParsedOTPAccount {
        ParsedOTPAccount(
            issuer: "Example",
            accountName: name,
            secret: SecretValue(Data(repeating: secretByte, count: 4)),
            algorithm: .sha1,
            digits: .six,
            period: 30
        )
    }
}
