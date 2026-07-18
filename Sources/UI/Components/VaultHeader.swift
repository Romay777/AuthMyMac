import SwiftUI

public struct VaultHeader: View {
    private let title: LocalizedStringKey
    private let accountCount: Int
    private let exportableAccountCount: Int
    @Binding private var searchText: String
    private let onAddManually: () -> Void
    private let onScanCamera: () -> Void
    private let onScanScreenArea: () -> Void
    private let onSelectImage: () -> Void
    private let onExport: () -> Void

    public init(
        title: LocalizedStringKey,
        accountCount: Int,
        exportableAccountCount: Int,
        searchText: Binding<String>,
        onAddManually: @escaping () -> Void,
        onScanCamera: @escaping () -> Void,
        onScanScreenArea: @escaping () -> Void,
        onSelectImage: @escaping () -> Void = {},
        onExport: @escaping () -> Void
    ) {
        self.title = title
        self.accountCount = accountCount
        self.exportableAccountCount = exportableAccountCount
        self._searchText = searchText
        self.onAddManually = onAddManually
        self.onScanCamera = onScanCamera
        self.onScanScreenArea = onScanScreenArea
        self.onSelectImage = onSelectImage
        self.onExport = onExport
    }

    public var body: some View {
        HStack(spacing: AuthMyMacSpacing.standard.value) {
            VStack(alignment: .leading, spacing: AuthMyMacSpacing.hairline.value) {
                Text(title)
                    .font(AuthMyMacTypography.sectionTitle)
                Text(accountCount == 1 ? "1 account" : "\(accountCount) accounts")
                    .font(AuthMyMacTypography.caption)
                    .foregroundStyle(AuthMyMacColors.subduedText)
            }

            Spacer(minLength: AuthMyMacSpacing.standard.value)

            TextField("Search accounts", text: $searchText)
                .authMyMacInputStyle()
                .frame(width: AuthMyMacMetrics.searchFieldWidth)

            HStack(spacing: AuthMyMacSpacing.compact.value) {
                Menu {
                    Button("Add Manually", systemImage: "keyboard", action: onAddManually)
                        .keyboardShortcut("n", modifiers: .command)
                    Button("Scan with Camera", systemImage: "camera.viewfinder", action: onScanCamera)
                    Button("Select Screen Area", systemImage: "viewfinder.rectangular", action: onScanScreenArea)
                    Button("Select Image File", systemImage: "photo", action: onSelectImage)
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(
                    width: AuthMyMacMetrics.headerActionWidth,
                    height: AuthMyMacMetrics.headerControlHeight
                )
                .contentShape(.rect)
                .background(
                    .ultraThinMaterial,
                    in: .rect(cornerRadius: AuthMyMacMetrics.panelCornerRadius)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: AuthMyMacMetrics.panelCornerRadius)
                        .stroke(AuthMyMacColors.stroke, lineWidth: 1)
                }
                .fixedSize()
                .help("Add Account")
                .accessibilityLabel("Add Account")

                Menu {
                    Button("Export Accounts", systemImage: "square.and.arrow.up", action: onExport)
                        .disabled(exportableAccountCount == 0)
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(
                    width: AuthMyMacMetrics.headerActionWidth,
                    height: AuthMyMacMetrics.headerControlHeight
                )
                .contentShape(.rect)
                .background(
                    .ultraThinMaterial,
                    in: .rect(cornerRadius: AuthMyMacMetrics.panelCornerRadius)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: AuthMyMacMetrics.panelCornerRadius)
                        .stroke(AuthMyMacColors.stroke, lineWidth: 1)
                }
                .fixedSize()
                .help("Vault Actions")
                .accessibilityLabel("Vault Actions")
            }
        }
        .padding(.horizontal, AuthMyMacSpacing.section.value)
        .padding(.top, AuthMyMacMetrics.headerTopInset)
        .frame(height: AuthMyMacMetrics.headerHeight, alignment: .top)
    }
}
