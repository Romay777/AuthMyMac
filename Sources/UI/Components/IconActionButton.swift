import SwiftUI

public struct IconActionButton: View {
    private let title: LocalizedStringKey
    private let systemImage: String
    private let role: ButtonRole?
    private let action: () -> Void

    public init(
        _ title: LocalizedStringKey,
        systemImage: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.action = action
    }

    public var body: some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .frame(
                    minWidth: AuthMyMacMetrics.minimumControlSize,
                    minHeight: AuthMyMacMetrics.minimumControlSize
                )
        }
        .buttonStyle(.borderless)
        .help(Text(title))
        .accessibilityLabel(Text(title))
    }
}
