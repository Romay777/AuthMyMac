import CoreImage
import Foundation
import ImageIO
import QR
@testable import ScreenCapture
import Testing
import UniformTypeIdentifiers

@Suite("Vision QR payload decoding")
struct VisionQRPayloadDecoderTests {
    @Test("Converts AppKit selection coordinates to display coordinates")
    func convertsSelectionCoordinates() {
        let rectangle = ScreenCoordinateConverter.captureRectangle(
            localRectangle: CGRect(x: 100, y: 120, width: 240, height: 180),
            screenHeight: 900,
            displayOrigin: CGPoint(x: 1440, y: -200)
        )

        #expect(rectangle == CGRect(x: 1540, y: 400, width: 240, height: 180))
    }

    @Test("Screen capture errors provide actionable descriptions")
    func errorDescriptions() {
        #expect(ScreenCaptureError.permissionDenied.errorDescription?.contains("quit and reopen") == true)
        #expect(ScreenCaptureError.noQRCodeFound.errorDescription?.contains("entire QR code") == true)
        #expect(ScreenCaptureError.captureFailed.errorDescription?.contains("could not be captured") == true)
        #expect(ImageQRImportError.unreadableImage.errorDescription?.contains("PNG") == true)
    }

    @Test("Recognizes a provisioning URI from a QR image")
    func recognizesProvisioningURI() throws {
        let value = "otpauth://totp/Example:user?secret=JBSWY3DP&issuer=Example"
        let filter = try #require(CIFilter(name: "CIQRCodeGenerator"))
        filter.setValue(Data(value.utf8), forKey: "inputMessage")
        let image = try #require(filter.outputImage)
        let scaled = image.transformed(by: .init(scaleX: 12, y: 12))
        let cgImage = try #require(CIContext().createCGImage(scaled, from: scaled.extent))

        let payload = try VisionQRPayloadDecoder().decode(cgImage)
        guard case let .account(account) = payload else {
            Issue.record("Expected a single account payload")
            return
        }
        #expect(account.issuer == "Example")
        #expect(account.accountName == "user")

        let imageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AuthMyMacTests-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: imageURL) }
        let destination = try #require(CGImageDestinationCreateWithURL(
            imageURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(destination, cgImage, nil)
        #expect(CGImageDestinationFinalize(destination))

        let importedPayload = try ImageQRPayloadDecoder().decode(contentsOf: imageURL)
        #expect(importedPayload == payload)
    }
}
