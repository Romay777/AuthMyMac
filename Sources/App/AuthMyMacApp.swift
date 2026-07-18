import AppKit
import ServiceManagement
import SwiftUI
import Authenticator
import UI

@main
struct AuthMyMacApp: App {
    private static let mainWindowID = "main"
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true
    @AppStorage("hideAppFromDock") private var hideAppFromDock = false
    @State private var model = AuthenticatorCoordinator()

    var body: some Scene {
        @Bindable var model = model

        Window("AuthMyMac", id: Self.mainWindowID) {
            AuthenticatorWorkspace(
                coordinator: model,
                settingsContent: AnyView(
                    StartupSettingsView(
                        launchesAtLogin: SMAppService.mainApp,
                        hidesAppFromDock: $hideAppFromDock,
                        showsMenuBarExtra: menuBarExtraBinding
                    )
                )
            )
                .task { await model.load() }
                .task(id: hideAppFromDock) {
                    if hideAppFromDock {
                        showMenuBarExtra = true
                    }
                    Self.applyDockVisibility(hideAppFromDock)
                }
        }
        .defaultSize(width: 880, height: 750)
        .defaultPosition(.center)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra(
            "AuthMyMac",
            systemImage: "key.viewfinder",
            isInserted: menuBarExtraBinding
        ) {
            AuthenticatorMenuContent(mainWindowID: Self.mainWindowID, coordinator: model)
        }

        Settings {
            TabView {
                Tab("Startup", systemImage: "power") {
                    StartupSettingsView(
                        launchesAtLogin: SMAppService.mainApp,
                        hidesAppFromDock: $hideAppFromDock,
                        showsMenuBarExtra: menuBarExtraBinding
                    )
                }

                Tab("Menu Bar", systemImage: "menubar.rectangle") {
                    SettingsRootView {
                        Toggle("Show AuthMyMac in the menu bar", isOn: menuBarExtraBinding)
                    }
                }
            }
            .frame(width: 420, height: 220)
        }
    }

    private var menuBarExtraBinding: Binding<Bool> {
        Binding(
            get: {
                MenuBarVisibilityPreferences.isMenuBarExtraInserted(
                    showMenuBarExtra: showMenuBarExtra,
                    hideAppFromDock: hideAppFromDock
                )
            },
            set: { requestedValue in
                showMenuBarExtra = MenuBarVisibilityPreferences.updatedMenuBarExtraVisibility(
                    requestedValue,
                    hideAppFromDock: hideAppFromDock
                )
            }
        )
    }

    private static func applyDockVisibility(_ isHidden: Bool) {
        _ = NSApp.setActivationPolicy(isHidden ? .accessory : .regular)
    }
}
