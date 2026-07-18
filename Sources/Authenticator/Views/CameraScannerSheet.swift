import CameraCapture
import SwiftUI
import UI

struct CameraScannerSheet: View {
    @Bindable var coordinator: AuthenticatorCoordinator

    var body: some View {
        VStack(spacing: AuthMyMacSpacing.standard.value) {
            AddAccountModePicker(coordinator: coordinator)
                .frame(width: 220)

            scanStatus
                .frame(minHeight: 20)

            scannerContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black.opacity(0.88))
                .clipShape(.rect(cornerRadius: AuthMyMacMetrics.panelCornerRadius))
                .overlay { ScannerGuides().padding(42) }
        }
        .padding(.horizontal, AuthMyMacSpacing.roomy.value)
        .padding(.bottom, AuthMyMacSpacing.roomy.value)
    }

    @ViewBuilder
    private var scanStatus: some View {
        if let progress = coordinator.cameraMigrationProgress {
            Label {
                Text("QR code \(progress.scannedCount) of \(progress.totalCount) scanned. Scan the next code to continue.")
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            .font(.callout.weight(.medium))
            .accessibilityElement(children: .combine)
        } else {
            Text("Position the QR code inside the frame")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var scannerContent: some View {
        switch coordinator.cameraPresentationState {
        case .active:
            CameraCapturePreview(session: coordinator.previewSession)
                .accessibilityLabel("Camera preview for QR code scanning")
        case .loading:
            ProgressView("Preparing camera...")
                .foregroundStyle(.white)
                .controlSize(.large)
        case .denied:
            cameraMessage(
                title: "Camera Access Required",
                message: "Allow camera access in System Settings, then try again.",
                systemImage: "camera.fill"
            )
        case .unavailable:
            cameraMessage(
                title: "Camera Unavailable",
                message: "Use Select Screen Area from the add menu instead.",
                systemImage: "camera.slash"
            )
        }
    }

    private func cameraMessage(title: LocalizedStringKey, message: LocalizedStringKey, systemImage: String) -> some View {
        VStack(spacing: AuthMyMacSpacing.standard.value) {
            Image(systemName: systemImage)
                .font(.title)
            Text(title).font(.headline)
            Text(message)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.white)
        .padding(AuthMyMacSpacing.section.value)
    }
}

private struct ScannerGuides: View {
    var body: some View {
        Canvas { context, size in
            let length: CGFloat = 24
            let width: CGFloat = 3
            let corners = [
                Path { path in
                    path.move(to: .zero); path.addLine(to: CGPoint(x: length, y: 0))
                    path.move(to: .zero); path.addLine(to: CGPoint(x: 0, y: length))
                },
                Path { path in
                    path.move(to: CGPoint(x: size.width, y: 0)); path.addLine(to: CGPoint(x: size.width - length, y: 0))
                    path.move(to: CGPoint(x: size.width, y: 0)); path.addLine(to: CGPoint(x: size.width, y: length))
                },
                Path { path in
                    path.move(to: CGPoint(x: 0, y: size.height)); path.addLine(to: CGPoint(x: length, y: size.height))
                    path.move(to: CGPoint(x: 0, y: size.height)); path.addLine(to: CGPoint(x: 0, y: size.height - length))
                },
                Path { path in
                    path.move(to: CGPoint(x: size.width, y: size.height)); path.addLine(to: CGPoint(x: size.width - length, y: size.height))
                    path.move(to: CGPoint(x: size.width, y: size.height)); path.addLine(to: CGPoint(x: size.width, y: size.height - length))
                },
            ]
            for path in corners {
                context.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: width, lineCap: .round))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
