import SwiftUI

public enum MenuBarAction: String, CaseIterable, Identifiable, Sendable {
    case openAuthenticator
    case selectScreenArea
    case scanWithCamera
    case exportAccounts
    case quit

    public var id: String { rawValue }
}

public struct MenuBarContent: View {
    private let enabledActions: Set<MenuBarAction>
    private let perform: (MenuBarAction) -> Void

    public init(
        enabledActions: Set<MenuBarAction>,
        perform: @escaping (MenuBarAction) -> Void
    ) {
        self.enabledActions = enabledActions
        self.perform = perform
    }

    public var body: some View {
        Button("Open Authenticator", systemImage: "macwindow") {
            perform(.openAuthenticator)
        }
        .disabled(!enabledActions.contains(.openAuthenticator))

        Divider()

        Button("Select Screen Area", systemImage: "viewfinder.rectangular") {
            perform(.selectScreenArea)
        }
        .disabled(!enabledActions.contains(.selectScreenArea))

        Button("Scan with Camera", systemImage: "camera.viewfinder") {
            perform(.scanWithCamera)
        }
        .disabled(!enabledActions.contains(.scanWithCamera))

        Button("Export Accounts", systemImage: "square.and.arrow.up") {
            perform(.exportAccounts)
        }
        .disabled(!enabledActions.contains(.exportAccounts))

        Divider()

        Button("Quit", systemImage: "power", role: .destructive) {
            perform(.quit)
        }
        .keyboardShortcut("q")
        .disabled(!enabledActions.contains(.quit))
    }
}
