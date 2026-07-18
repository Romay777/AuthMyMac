import Domain
import SwiftUI
import UniformTypeIdentifiers

public struct AuthenticatorRootView: View {
    private let accounts: [OTPAccount]
    private let copiedAccountID: UUID?
    private let codeFor: (OTPAccount) -> String
    private let isCodeAvailableFor: (OTPAccount) -> Bool
    private let currentDate: Date
    private let onAddManually: () -> Void
    private let onScanCamera: () -> Void
    private let onScanScreenArea: () -> Void
    private let onImportImage: (URL) -> Void
    private let onExport: () -> Void
    private let onCopy: (OTPAccount) -> Void
    private let onEdit: (OTPAccount) -> Void
    private let onToggleFavorite: (OTPAccount) -> Void
    private let onDelete: (OTPAccount) -> Void
    private let settingsContent: AnyView
    @State private var destination = VaultDestination.all
    @State private var searchText = ""
    @State private var isPresentingImageImporter = false

    public init(
        accounts: [OTPAccount],
        copiedAccountID: UUID? = nil,
        codeFor: @escaping (OTPAccount) -> String,
        isCodeAvailableFor: @escaping (OTPAccount) -> Bool,
        currentDate: Date,
        onAddManually: @escaping () -> Void,
        onScanCamera: @escaping () -> Void,
        onScanScreenArea: @escaping () -> Void,
        onImportImage: @escaping (URL) -> Void = { _ in },
        onExport: @escaping () -> Void,
        onCopy: @escaping (OTPAccount) -> Void,
        onEdit: @escaping (OTPAccount) -> Void,
        onToggleFavorite: @escaping (OTPAccount) -> Void,
        onDelete: @escaping (OTPAccount) -> Void,
        settingsContent: AnyView = AnyView(EmptyView())
    ) {
        self.accounts = accounts
        self.copiedAccountID = copiedAccountID
        self.codeFor = codeFor
        self.isCodeAvailableFor = isCodeAvailableFor
        self.currentDate = currentDate
        self.onAddManually = onAddManually
        self.onScanCamera = onScanCamera
        self.onScanScreenArea = onScanScreenArea
        self.onImportImage = onImportImage
        self.onExport = onExport
        self.onCopy = onCopy
        self.onEdit = onEdit
        self.onToggleFavorite = onToggleFavorite
        self.onDelete = onDelete
        self.settingsContent = settingsContent
    }

    public var body: some View {
        HSplitView {
            VaultSidebar(selection: $destination)

            VStack(spacing: 0) {
                if destination == .settings {
                    settingsContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    VaultHeader(
                        title: destination == .all ? "All Codes" : "Favorites",
                        accountCount: destinationAccounts.count,
                        exportableAccountCount: accounts.count,
                        searchText: $searchText,
                        onAddManually: onAddManually,
                        onScanCamera: onScanCamera,
                        onScanScreenArea: onScanScreenArea,
                        onSelectImage: { isPresentingImageImporter = true },
                        onExport: onExport
                    )
                    accountContent
                }
            }
            .background(AuthMyMacColors.content)
            .frame(minWidth: AuthMyMacMetrics.contentMinimumWidth)
            .navigationTitle("")
        }
        .background(AuthMyMacColors.window)
        .foregroundStyle(AuthMyMacColors.ink)
        .tint(AuthMyMacColors.accent)
        .preferredColorScheme(.light)
        .fileImporter(
            isPresented: $isPresentingImageImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(urls) = result, let url = urls.first else { return }
            onImportImage(url)
        }
        .frame(
            minWidth: AuthMyMacMetrics.sidebarMinimumWidth + AuthMyMacMetrics.contentMinimumWidth,
            minHeight: AuthMyMacMetrics.windowMinimumHeight
        )
    }

    @ViewBuilder
    private var accountContent: some View {
        if accounts.isEmpty {
            emptyVault
        } else if destination == .favorites && destinationAccounts.isEmpty {
            ContentUnavailableView(
                "No Favorites",
                systemImage: "star",
                description: Text("Favorite an account to keep it here.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if visibleAccounts.isEmpty {
            ContentUnavailableView.search(text: searchText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: AuthMyMacMetrics.accountListRowSpacing) {
                    ForEach(visibleAccounts) { account in
                        AccountCard(
                            account: account,
                            code: codeFor(account),
                            remainingSeconds: remainingSeconds(for: account),
                            isCopied: copiedAccountID == account.id,
                            isCopyAvailable: isCodeAvailableFor(account),
                            onEdit: { onEdit(account) },
                            onFavorite: { onToggleFavorite(account) },
                            onCopy: { onCopy(account) },
                            onDelete: { onDelete(account) }
                        )
                    }
                }
                .frame(maxWidth: AuthMyMacMetrics.accountListMaximumWidth)
                .padding(AuthMyMacSpacing.section.value)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var emptyVault: some View {
        ContentUnavailableView {
            Label("No Accounts", systemImage: "key.viewfinder")
        } description: {
            Text("Add an account to generate verification codes.")
        } actions: {
            Button("Scan QR Code", systemImage: "camera.viewfinder", action: onScanCamera)
                .buttonStyle(.borderedProminent)
            Button("Add Manually", systemImage: "plus", action: onAddManually)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var destinationAccounts: [OTPAccount] {
        guard destination != .settings else { return [] }
        return VaultAccountFilter.accounts(accounts, destination: destination, query: "")
    }

    private var visibleAccounts: [OTPAccount] {
        VaultAccountFilter.accounts(accounts, destination: destination, query: searchText)
    }

    private func remainingSeconds(for account: OTPAccount) -> Int {
        let elapsedSeconds = Int(currentDate.timeIntervalSince1970.rounded(.down))
        return max(1, account.period - elapsedSeconds % account.period)
    }
}

enum VaultAccountFilter {
    static func accounts(
        _ accounts: [OTPAccount],
        destination: VaultDestination,
        query: String
    ) -> [OTPAccount] {
        let destinationAccounts = destination == .favorites ? accounts.filter(\.isFavorite) : accounts
        guard !query.isEmpty else { return destinationAccounts }
        return destinationAccounts.filter {
            $0.issuer.localizedCaseInsensitiveContains(query)
                || $0.accountName.localizedCaseInsensitiveContains(query)
        }
    }
}

#if DEBUG
private enum VaultPreviewData {
    static let accounts = [
        account(0, issuer: "GitHub", identity: "octocat@example.com", favorite: true),
        account(1, issuer: "Google", identity: "workspace@example.com"),
        account(2, issuer: "Microsoft", identity: "developer@example.com", favorite: true),
        account(3, issuer: "Amazon Web Services", identity: "production-admin@example.com"),
        account(4, issuer: "Cloudflare", identity: "security@example.com"),
        account(5, issuer: "A Very Long Issuer Name for Layout Testing", identity: "a-very-long-account-identity@example.com", digits: .eight),
    ]

    private static func account(
        _ index: Int,
        issuer: String,
        identity: String,
        favorite: Bool = false,
        digits: OTPDigits = .six
    ) -> OTPAccount {
        try! OTPAccount(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000\(String(format: "%02d", index + 1))")!,
            issuer: issuer,
            accountName: identity,
            secretKeychainID: "synthetic-preview-reference-\(index)",
            digits: digits,
            createdAt: Date(timeIntervalSince1970: 0),
            sortOrder: index,
            isFavorite: favorite
        )
    }
}

private extension AuthenticatorRootView {
    static func preview(accounts: [OTPAccount] = VaultPreviewData.accounts) -> AuthenticatorRootView {
        AuthenticatorRootView(
            accounts: accounts,
            codeFor: { $0.digits == .eight ? "12345678" : "123456" },
            isCodeAvailableFor: { _ in true },
            currentDate: Date(timeIntervalSince1970: 12),
            onAddManually: {},
            onScanCamera: {},
            onScanScreenArea: {},
            onExport: {},
            onCopy: { _ in },
            onEdit: { _ in },
            onToggleFavorite: { _ in },
            onDelete: { _ in }
        )
    }
}

#Preview("Main Vault", traits: .fixedLayout(width: 880, height: 750)) {
    AuthenticatorRootView.preview()
}

#Preview("Empty Vault", traits: .fixedLayout(width: 880, height: 750)) {
    AuthenticatorRootView.preview(accounts: [])
}

#Preview("Dark", traits: .fixedLayout(width: 880, height: 750)) {
    AuthenticatorRootView.preview()
        .preferredColorScheme(.dark)
}

#Preview("Search No Results", traits: .fixedLayout(width: 620, height: 400)) {
    ContentUnavailableView.search(text: "No matching account")
}
#endif
