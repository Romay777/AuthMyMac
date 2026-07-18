import SwiftUI

public struct SettingsRootView<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        Form {
            content
        }
        .formStyle(.grouped)
        .scenePadding()
        .frame(width: 420, height: 160)
    }
}
