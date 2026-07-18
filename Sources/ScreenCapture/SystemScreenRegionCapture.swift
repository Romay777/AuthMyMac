@preconcurrency import AppKit
@preconcurrency import ScreenCaptureKit
@preconcurrency import Vision
import CoreGraphics
import Foundation
import QR

public struct SystemScreenRegionCapture: ScreenRegionCapturing {
    private let decoder: any QRPayloadDecoding

    public init(decoder: any QRPayloadDecoding = QRPayloadDecoder()) {
        self.decoder = decoder
    }

    public func selectRegion() async throws -> ScreenRegion {
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            throw ScreenCaptureError.permissionDenied
        }
        return try await ScreenRegionSelector.select()
    }

    public func captureAndDecode(_ region: ScreenRegion) async throws -> QRPayload {
        guard !region.rectangle.isNull, !region.rectangle.isEmpty else {
            throw ScreenCaptureError.invalidRegion
        }
        do {
            let image = try await SCScreenshotManager.captureImage(in: region.rectangle)
            return try VisionQRPayloadDecoder(decoder: decoder).decode(image)
        } catch let error as ScreenCaptureError {
            throw error
        } catch {
            if !CGPreflightScreenCaptureAccess() {
                throw ScreenCaptureError.permissionDenied
            }
            throw ScreenCaptureError.captureFailed
        }
    }

    public func cancel() async {
        await ScreenRegionSelector.cancel()
    }
}

public struct VisionQRPayloadDecoder: Sendable {
    private let decoder: any QRPayloadDecoding

    public init(decoder: any QRPayloadDecoding = QRPayloadDecoder()) {
        self.decoder = decoder
    }

    public func decode(_ image: CGImage) throws -> QRPayload {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        for observation in request.results ?? [] {
            guard let payload = observation.payloadStringValue,
                  let decoded = try? decoder.decode(payload) else { continue }
            return decoded
        }
        throw ScreenCaptureError.noQRCodeFound
    }
}

@MainActor
private final class ScreenRegionSelector: NSObject {
    private static var active: ScreenRegionSelector?
    private var panels: [SelectionPanel] = []
    private var continuation: CheckedContinuation<ScreenRegion, Error>?

    static func select() async throws -> ScreenRegion {
        guard active == nil else { throw ScreenCaptureError.selectionCancelled }
        return try await withCheckedThrowingContinuation { continuation in
            let selector = ScreenRegionSelector(continuation: continuation)
            active = selector
            selector.show()
        }
    }

    static func cancel() {
        active?.finish(.failure(ScreenCaptureError.selectionCancelled))
    }

    private init(continuation: CheckedContinuation<ScreenRegion, Error>) {
        self.continuation = continuation
    }

    private func show() {
        for screen in NSScreen.screens {
            let panel = SelectionPanel(screen: screen) { [weak self] rectangle in
                self?.finish(.success(rectangle))
            } onCancel: { [weak self] in
                self?.finish(.failure(ScreenCaptureError.selectionCancelled))
            }
            panels.append(panel)
            panel.orderFrontRegardless()
        }
    }

    private func finish(_ result: Result<ScreenRegion, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
        Self.active = nil
        continuation.resume(with: result)
    }
}

@MainActor
private final class SelectionPanel: NSPanel {
    init(screen: NSScreen, onSelection: @escaping (ScreenRegion) -> Void, onCancel: @escaping () -> Void) {
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        let view = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size)) { localRect in
            let displayBounds = CGDisplayBounds(displayID)
            let captureRect = ScreenCoordinateConverter.captureRectangle(
                localRectangle: localRect,
                screenHeight: screen.frame.height,
                displayOrigin: displayBounds.origin
            )
            onSelection(ScreenRegion(displayID: displayID, rectangle: captureRect))
        } onCancel: {
            onCancel()
        }
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = view
        makeFirstResponder(view)
    }
}

@MainActor
private final class SelectionView: NSView {
    private var startPoint: CGPoint?
    private var selectedRect = CGRect.zero
    private let onSelection: (CGRect) -> Void
    private let onCancel: () -> Void

    init(frame frameRect: NSRect, onSelection: @escaping (CGRect) -> Void, onCancel: @escaping () -> Void) {
        self.onSelection = onSelection
        self.onCancel = onCancel
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        selectedRect = .zero
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startPoint else { return }
        selectedRect = CGRect(start: startPoint, end: convert(event.locationInWindow, from: nil)).standardized
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard selectedRect.width >= 8, selectedRect.height >= 8 else {
            onCancel()
            return
        }
        onSelection(selectedRect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel() }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.45).setFill()
        dirtyRect.fill()
        guard !selectedRect.isEmpty else { return }
        NSGraphicsContext.current?.cgContext.saveGState()
        NSGraphicsContext.current?.cgContext.setBlendMode(.clear)
        NSGraphicsContext.current?.cgContext.fill(selectedRect)
        NSGraphicsContext.current?.cgContext.restoreGState()
        NSColor.controlAccentColor.setStroke()
        NSBezierPath(rect: selectedRect).lineWidth = 2
        NSBezierPath(rect: selectedRect).stroke()
    }
}

enum ScreenCoordinateConverter {
    static func captureRectangle(
        localRectangle: CGRect,
        screenHeight: CGFloat,
        displayOrigin: CGPoint
    ) -> CGRect {
        CGRect(
            x: displayOrigin.x + localRectangle.minX,
            y: displayOrigin.y + screenHeight - localRectangle.maxY,
            width: localRectangle.width,
            height: localRectangle.height
        )
    }
}

private extension CGRect {
    init(start: CGPoint, end: CGPoint) {
        self.init(x: start.x, y: start.y, width: end.x - start.x, height: end.y - start.y)
    }
}
