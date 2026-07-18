import SwiftUI

public enum VaultDestination: String, CaseIterable, Identifiable, Sendable {
    case all
    case favorites
    case settings

    public var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .all: "All"
        case .favorites: "Favorites"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .all: "square.grid.2x2"
        case .favorites: "star"
        case .settings: "gear"
        }
    }
}

public struct VaultSidebar: View {
    @Binding private var selection: VaultDestination

    public init(selection: Binding<VaultDestination>) {
        self._selection = selection
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("AuthMyMac")
                .font(AuthMyMacTypography.windowTitle)
                .padding(.horizontal, AuthMyMacSpacing.roomy.value)
                .padding(.vertical, AuthMyMacMetrics.sidebarTitleVerticalMargin)

            VStack(spacing: AuthMyMacSpacing.hairline.value) {
                ForEach(VaultDestination.allCases) { destination in
                    Button {
                        selection = destination
                    } label: {
                        Label {
                            Text(destination.title)
                        } icon: {
                            Image(systemName: destination.systemImage)
                                .font(
                                    .system(
                                        size: AuthMyMacMetrics.sidebarNavigationFontSize
                                            * AuthMyMacMetrics.sidebarNavigationIconScale
                                    )
                                )
                        }
                            .font(
                                .system(
                                    size: AuthMyMacMetrics.sidebarNavigationFontSize,
                                    weight: selection == destination ? .semibold : .regular
                                )
                            )
                            .foregroundStyle(AuthMyMacColors.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, AuthMyMacSpacing.compact.value)
                            .frame(height: AuthMyMacMetrics.sidebarNavigationRowHeight)
                            .contentShape(Rectangle())
                            .background(
                                selection == destination ? AuthMyMacColors.selectedSidebar : .clear,
                                in: .rect(cornerRadius: AuthMyMacMetrics.sidebarSelectionCornerRadius)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == destination ? .isSelected : [])
                }
            }
            .padding(.horizontal, AuthMyMacSpacing.standard.value)
            .frame(maxWidth: .infinity)

            Spacer(minLength: 0)
        }
        .frame(
            minWidth: AuthMyMacMetrics.sidebarMinimumWidth,
            idealWidth: AuthMyMacMetrics.sidebarIdealWidth,
            maxWidth: AuthMyMacMetrics.sidebarMaximumWidth,
            maxHeight: .infinity
        )
    }
}
