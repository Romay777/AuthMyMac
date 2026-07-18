import SwiftUI

public struct GlassPanel<Content: View>: View {
    private let cornerRadius: CGFloat
    private let content: Content

    public init(
        cornerRadius: CGFloat = AuthMyMacMetrics.panelCornerRadius,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    public var body: some View {
        content
            .padding(AuthMyMacSpacing.standard.value)
            .glassEffect(
                .regular.tint(AuthMyMacColors.glassTint),
                in: .rect(cornerRadius: cornerRadius)
            )
    }
}
