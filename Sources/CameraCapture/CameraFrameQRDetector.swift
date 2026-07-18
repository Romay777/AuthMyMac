import CoreVideo
import ImageIO
@preconcurrency import Vision

struct CameraFrameQRDetector {
    func detectValues(
        in pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation
    ) throws -> [String] {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        try VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: orientation,
            options: [:]
        ).perform([request])
        return (request.results ?? []).compactMap(\.payloadStringValue)
    }
}
