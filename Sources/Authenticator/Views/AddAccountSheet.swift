import CameraCapture
import SwiftUI
import UI

struct AddAccountSheet: View {
    @Bindable var coordinator: AuthenticatorCoordinator

    var body: some View {
        VStack(spacing: 0) {
            AddAccountSheetHeader(coordinator: coordinator)
            Group {
                switch coordinator.addAccountRoute ?? .manual {
                case .scan:
                    CameraScannerSheet(coordinator: coordinator)
                case .manual:
                    ManualAccountEntryView(coordinator: coordinator)
                }
            }
        }
        .frame(
            width: coordinator.addAccountRoute == .scan ? 410 : 450,
            height: coordinator.addAccountRoute == .scan ? 440 : 350
        )
        .background(AuthMyMacColors.sheet)
        .foregroundStyle(AuthMyMacColors.ink)
        .tint(AuthMyMacColors.accent)
        .preferredColorScheme(.light)
    }
}

private struct AddAccountSheetHeader: View {
    @Bindable var coordinator: AuthenticatorCoordinator

    var body: some View {
        ZStack {
            HStack {
                Button {
                    coordinator.dismissAddAccount()
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: AuthMyMacMetrics.minimumControlSize, height: AuthMyMacMetrics.minimumControlSize)
                }
                .buttonStyle(.borderless)
                .help("Close")
                .accessibilityLabel("Close")
                Spacer()
            }

            Text(coordinator.addAccountRoute == .scan ? "Scan QR Code" : "Add Account")
                .font(.headline)
        }
        .padding(.horizontal, AuthMyMacSpacing.roomy.value)
        .frame(height: 52)
    }
}

struct AddAccountModePicker: View {
    @Bindable var coordinator: AuthenticatorCoordinator

    var body: some View {
        Picker("Add account method", selection: routeBinding) {
            Label("Scan", systemImage: "camera.viewfinder").tag(AddAccountRoute.scan)
            Label("Manual", systemImage: "keyboard").tag(AddAccountRoute.manual)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var routeBinding: Binding<AddAccountRoute> {
        Binding(
            get: { coordinator.addAccountRoute ?? .manual },
            set: { coordinator.selectAddAccountRoute($0) }
        )
    }
}

#if DEBUG
#Preview("Manual Entry Empty") {
    AddAccountSheet(coordinator: .preview(route: .manual))
}

#Preview("Manual Entry Invalid") {
    AddAccountSheet(coordinator: .preview(
        route: .manual,
        manualError: "The Base32 secret is invalid."
    ))
}

#Preview("Manual Entry Submitting") {
    AddAccountSheet(coordinator: .preview(route: .manual, isSubmitting: true))
}

#Preview("Scanner Active") {
    AddAccountSheet(coordinator: .preview(route: .scan, cameraState: .active))
}

#Preview("Scanner Migration Progress") {
    AddAccountSheet(coordinator: .preview(
        route: .scan,
        cameraState: .active,
        migrationProgress: MigrationScanProgress(scannedCount: 1, totalCount: 2)
    ))
}

#Preview("Scanner Permission Denied") {
    AddAccountSheet(coordinator: .preview(route: .scan, cameraState: .denied))
}

#Preview("Scanner Unavailable") {
    AddAccountSheet(coordinator: .preview(route: .scan, cameraState: .unavailable))
}
#endif
