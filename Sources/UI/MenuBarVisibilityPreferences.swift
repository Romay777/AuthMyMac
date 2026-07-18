import Foundation

/// Keeps at least one application entry point available while the Dock icon is hidden.
public enum MenuBarVisibilityPreferences {
    public static func isMenuBarExtraInserted(
        showMenuBarExtra: Bool,
        hideAppFromDock: Bool
    ) -> Bool {
        hideAppFromDock || showMenuBarExtra
    }

    public static func updatedMenuBarExtraVisibility(
        _ requestedValue: Bool,
        hideAppFromDock: Bool
    ) -> Bool {
        hideAppFromDock || requestedValue
    }
}
