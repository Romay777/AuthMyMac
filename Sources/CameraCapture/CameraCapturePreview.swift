@preconcurrency import AVFoundation
import AppKit
import SwiftUI

/// AppKit bridge for previewing the session owned by `CameraScanner`.
public struct CameraCapturePreview: NSViewRepresentable {
    public let session: AVCaptureSession

    public init(session: AVCaptureSession) {
        self.session = session
    }

    public func makeNSView(context: Context) -> NSView {
        let view = PreviewView()
        view.previewLayer.session = session
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? PreviewView)?.previewLayer.session = session
    }
}

private final class PreviewView: NSView {
    let previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(previewLayer)
        previewLayer.videoGravity = .resizeAspectFill
    }

    required init?(coder: NSCoder) { nil }

    override public func layout() {
        super.layout()
        previewLayer.frame = bounds
    }
}
