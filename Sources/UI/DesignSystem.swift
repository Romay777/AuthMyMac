import SwiftUI

public enum AuthMyMacSpacing: CGFloat, CaseIterable, Sendable {
    case hairline = 2
    case compact = 6
    case standard = 12
    case roomy = 16
    case section = 24
    case large = 32

    public var value: CGFloat { rawValue }
}

public enum AuthMyMacMetrics {
    public static let windowCornerRadius: CGFloat = 12
    public static let sheetCornerRadius: CGFloat = 12
    public static let panelCornerRadius: CGFloat = 8
    public static let rowCornerRadius: CGFloat = 8
    public static let inputCornerRadius: CGFloat = 7
    public static let sidebarSelectionCornerRadius: CGFloat = 6

    public static let sidebarIdealWidth: CGFloat = 220
    public static let sidebarMinimumWidth: CGFloat = 200
    public static let sidebarMaximumWidth: CGFloat = 240
    public static let sidebarTitleVerticalMargin: CGFloat = 24
    public static let sidebarNavigationRowHeight: CGFloat = 45
    public static let sidebarNavigationFontSize: CGFloat = 13
    public static let sidebarNavigationIconScale: CGFloat = 1.25
    public static let headerHeight: CGFloat = 72
    public static let headerTopInset: CGFloat = headerControlHeight / 20
    public static let accountRowHeight: CGFloat = 82
    public static let accountListRowSpacing: CGFloat = 2
    public static let accountDeleteRevealWidth: CGFloat = 58
    public static let accountDeleteTriggerDistance: CGFloat = 42
    public static let accountMarkSize: CGFloat = 42
    public static let countdownSize: CGFloat = 36
    public static let minimumControlSize: CGFloat = 32
    public static let actionButtonSize: CGFloat = 34
    public static let headerControlHeight: CGFloat = 36
    public static let headerActionWidth: CGFloat = 36
    public static let searchFieldWidth: CGFloat = 210

    public static let contentMinimumWidth: CGFloat = 560
    public static let windowMinimumHeight: CGFloat = 560
    public static let accountListMaximumWidth: CGFloat = 760
}

public enum AuthMyMacColors {
    // Reference palette: cool milk-glass surfaces over a pale periwinkle shell.
    public static let window = Color(red: 0.925, green: 0.925, blue: 0.975)
    public static let content = Color(red: 0.970, green: 0.968, blue: 0.990)
    public static let sheet = Color(red: 0.955, green: 0.952, blue: 0.985)
    public static let surface = Color.white.opacity(0.64)
    public static let elevatedSurface = Color.white.opacity(0.82)
    public static let input = Color(red: 0.925, green: 0.920, blue: 0.965).opacity(0.66)
    public static let stroke = Color(red: 0.315, green: 0.320, blue: 0.470).opacity(0.10)
    public static let selectedSidebar = Color.black.opacity(0.10)
    public static let glassTint = Color(red: 0.900, green: 0.895, blue: 0.975).opacity(0.28)
    public static let ink = Color(red: 0.055, green: 0.065, blue: 0.130)
    public static let subduedText = Color(red: 0.390, green: 0.405, blue: 0.510)
    public static let accent = Color(red: 0.600, green: 0.500, blue: 0.900)
}

public enum AuthMyMacTypography {
    public static let windowTitle = Font.title2.weight(.semibold)
    public static let sectionTitle = Font.title3.weight(.semibold)
    public static let accountName = Font.body.weight(.semibold)
    public static let accountIdentity = Font.callout
    public static let otpCode = Font.system(.title2, design: .monospaced, weight: .semibold)
    public static let caption = Font.caption
    public static let formLabel = Font.callout.weight(.medium)
}

public extension View {
    func authMyMacInputStyle() -> some View {
        self
            .textFieldStyle(.plain)
            .padding(.horizontal, 10)
            .frame(height: AuthMyMacMetrics.headerControlHeight)
            .background(
                AuthMyMacColors.input,
                in: .rect(cornerRadius: AuthMyMacMetrics.inputCornerRadius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AuthMyMacMetrics.inputCornerRadius)
                    .stroke(AuthMyMacColors.stroke, lineWidth: 1)
            }
    }
}
