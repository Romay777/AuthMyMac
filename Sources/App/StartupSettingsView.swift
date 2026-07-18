import ServiceManagement
import SwiftUI
import UI

struct StartupSettingsView: View {
    let launchesAtLogin: SMAppService
    @Binding var hidesAppFromDock: Bool
    @Binding var showsMenuBarExtra: Bool
    @State private var isLaunchAtLoginEnabled: Bool
    @State private var displaysLaunchAtLoginError = false

    init(
        launchesAtLogin: SMAppService,
        hidesAppFromDock: Binding<Bool>,
        showsMenuBarExtra: Binding<Bool>
    ) {
        self.launchesAtLogin = launchesAtLogin
        self._hidesAppFromDock = hidesAppFromDock
        self._showsMenuBarExtra = showsMenuBarExtra
        self._isLaunchAtLoginEnabled = State(initialValue: launchesAtLogin.status == .enabled)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Toggle("Open AuthMyMac at login", isOn: launchAtLoginBinding)
                .controlSize(.large)
                .font(.body.weight(.medium))
                .padding(.vertical, 14)

            Divider()

            Toggle("Hide AuthMyMac from the Dock", isOn: dockVisibilityBinding)
                .controlSize(.large)
                .font(.body.weight(.medium))
                .padding(.vertical, 14)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .alert("Couldn't Update Login Item", isPresented: $displaysLaunchAtLoginError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("AuthMyMac could not update its launch-at-login setting. Try again after installing the app in Applications.")
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { isLaunchAtLoginEnabled },
            set: { isEnabled in
                do {
                    if isEnabled {
                        try launchesAtLogin.register()
                    } else {
                        try launchesAtLogin.unregister()
                    }
                    isLaunchAtLoginEnabled = isEnabled
                } catch {
                    displaysLaunchAtLoginError = true
                }
            }
        )
    }

    private var dockVisibilityBinding: Binding<Bool> {
        Binding(
            get: { hidesAppFromDock },
            set: { isHidden in
                if isHidden {
                    showsMenuBarExtra = true
                }
                hidesAppFromDock = isHidden
            }
        )
    }
}
