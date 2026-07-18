import AppKit
import AVFoundation
import CameraCapture
import CoreImage
import Domain
import MenuBar
import Notifications
import Observation
import OTP
import QR
import ScreenCapture
import Storage
import SwiftUI
import UI

enum AddAccountRoute: String, Identifiable, CaseIterable {
    case scan
    case manual

    var id: String { rawValue }
}

enum CameraPresentationState: Equatable {
    case loading
    case active
    case denied
    case unavailable
}

@MainActor
@Observable
public final class AuthenticatorCoordinator {
    private let store: any AccountStoring
    private let generator: any TOTPGenerating
    private let decoder: any QRPayloadDecoding
    private let notifications: any NotificationPosting
    private let cameraScanner: any CameraScanning
    private let cameraPreviewSession: AVCaptureSession
    private let screenCapture: any ScreenRegionCapturing
    private var clockTask: Task<Void, Never>?
    private var cameraScanTask: Task<Void, Never>?
    private var cameraScanID: UUID?
    private var secretsByAccountID: [UUID: SecretValue] = [:]
    private var generatedCounterByAccountID: [UUID: Int64] = [:]
    private var isRefreshingCodes = false

    public private(set) var accounts: [OTPAccount] = []
    public private(set) var codes: [UUID: String] = [:]
    public private(set) var currentDate = Date()
    public private(set) var exportURIs: [String] = []
    public private(set) var errorMessage: String?
    var exportBatchIndex = 0
    var addAccountRoute: AddAccountRoute?
    var isPresentingExportConfirmation = false
    var isPresentingExport = false
    var accountPendingDeletion: OTPAccount?
    var accountPendingEdit: OTPAccount?
    var manualIssuer = ""
    var manualAccountName = ""
    var manualSecret = ""
    private(set) var manualEntryErrorMessage: String?
    private(set) var isAddingManualAccount = false
    private(set) var cameraPresentationState = CameraPresentationState.loading
    private(set) var cameraMigrationProgress: MigrationScanProgress?
    private(set) var copiedAccountID: UUID?

    var activeExportURI: String? {
        exportURIs.indices.contains(exportBatchIndex) ? exportURIs[exportBatchIndex] : nil
    }

    var activeExportNumber: Int {
        exportBatchIndex + 1
    }

    var exportBatchCount: Int {
        exportURIs.count
    }

    var previewSession: AVCaptureSession {
        cameraPreviewSession
    }

    public convenience init() {
        let scanner = CameraScanner()
        self.init(
            store: SecureAccountStore(),
            generator: RFC6238TOTPGenerator(),
            decoder: QRPayloadDecoder(),
            notifications: UserNotificationPoster(),
            cameraScanner: scanner,
            cameraPreviewSession: scanner.captureSession,
            screenCapture: SystemScreenRegionCapture()
        )
    }

    public init(
        store: any AccountStoring,
        generator: any TOTPGenerating,
        decoder: any QRPayloadDecoding,
        notifications: any NotificationPosting,
        cameraScanner: any CameraScanning,
        cameraPreviewSession: AVCaptureSession,
        screenCapture: any ScreenRegionCapturing
    ) {
        self.store = store
        self.generator = generator
        self.decoder = decoder
        self.notifications = notifications
        self.cameraScanner = cameraScanner
        self.cameraPreviewSession = cameraPreviewSession
        self.screenCapture = screenCapture
    }

    public func load() async {
        do {
            accounts = try await store.accounts()
            secretsByAccountID = secretsByAccountID.filter { accountID, _ in
                accounts.contains { $0.id == accountID }
            }
            generatedCounterByAccountID = generatedCounterByAccountID.filter { accountID, _ in
                accounts.contains { $0.id == accountID }
            }
            codes = codes.filter { accountID, _ in
                accounts.contains { $0.id == accountID }
            }
            await refreshCodes()
            startClock()
        } catch {
            present(error)
        }
    }

    public func importPayload(_ payload: QRPayload) async throws {
        let parsedAccounts: [ParsedOTPAccount]
        switch payload {
        case let .account(account):
            parsedAccounts = [account]
        case let .migration(accounts):
            parsedAccounts = accounts
        }

        let requests = parsedAccounts.map {
            AccountCreationRequest(
                issuer: $0.issuer,
                accountName: $0.accountName,
                secret: $0.secret,
                algorithm: $0.algorithm,
                digits: $0.digits,
                period: $0.period
            )
        }
        let imported = try await store.create(requests)
        if let lastImported = imported.last {
            await notifyAboutImport(lastImported)
        }
        await load()
    }

    public func prepareExport() async throws {
        var records: [ParsedOTPAccount] = []
        records.reserveCapacity(accounts.count)
        for account in accounts {
            records.append(ParsedOTPAccount(
                issuer: account.issuer,
                accountName: account.accountName,
                secret: try await store.secret(for: account),
                algorithm: account.algorithm,
                digits: account.digits,
                period: account.period
            ))
        }
        let urls = try MigrationPayloadCodec().encodeBatches(records)
        guard urls.allSatisfy({ QRCodeImage.make(from: $0.absoluteString) != nil }) else {
            throw QRPayloadError.payloadTooLarge
        }
        exportURIs = urls.map(\.absoluteString)
        exportBatchIndex = 0
        isPresentingExport = true
    }

    func beginManualEntry() {
        if addAccountRoute == .scan {
            cancelCameraScan()
        }
        manualEntryErrorMessage = nil
        addAccountRoute = .manual
    }

    func addManualAccount() {
        guard !isAddingManualAccount else { return }
        let trimmedIssuer = manualIssuer.trimmingCharacters(in: .whitespacesAndNewlines)
        let issuer = trimmedIssuer.isEmpty ? "Other" : trimmedIssuer
        let accountName = manualAccountName
        let encodedSecret = manualSecret
        manualEntryErrorMessage = nil
        isAddingManualAccount = true
        Task {
            defer { isAddingManualAccount = false }
            do {
                let secret = try Base32.decode(encodedSecret)
                _ = try await store.create(AccountCreationRequest(
                    issuer: issuer,
                    accountName: accountName,
                    secret: secret
                ))
                manualIssuer = ""
                manualAccountName = ""
                manualSecret = ""
                addAccountRoute = nil
                await load()
            } catch {
                manualEntryErrorMessage = message(for: error)
            }
        }
    }

    func clearManualEntryError() {
        manualEntryErrorMessage = nil
    }

    func importPayload(_ value: String) {
        Task {
            do {
                try await importPayload(decoder.decode(value))
            } catch {
                present(error)
            }
        }
    }

    public func beginCameraScan() {
        addAccountRoute = .scan
        cameraPresentationState = .loading
        cameraMigrationProgress = nil
        let previousTask = cameraScanTask
        previousTask?.cancel()
        let scanID = UUID()
        cameraScanID = scanID
        cameraScanTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if cameraScanID == scanID {
                    cameraScanTask = nil
                    cameraScanID = nil
                }
            }
            if let previousTask {
                await cameraScanner.stop()
                await previousTask.value
            }
            guard cameraScanID == scanID, addAccountRoute == .scan else { return }
            do {
                let authorization = await cameraScanner.authorizationState()
                try Task.checkCancellation()
                guard cameraScanID == scanID, addAccountRoute == .scan else { return }
                cameraPresentationState = switch authorization {
                case .authorized, .notDetermined: .active
                case .denied: .denied
                case .unavailable: .unavailable
                }
                guard authorization != .denied else { return }
                guard authorization != .unavailable else { return }
                let payload = try await cameraScanner.scan { [weak self] progress in
                    Task { @MainActor [weak self] in
                        guard let self, cameraScanID == scanID, addAccountRoute == .scan else { return }
                        cameraMigrationProgress = progress
                    }
                }
                try Task.checkCancellation()
                guard cameraScanID == scanID else { return }
                try await importPayload(payload)
                guard cameraScanID == scanID, !Task.isCancelled else { return }
                addAccountRoute = nil
                cameraMigrationProgress = nil
            } catch {
                guard cameraScanID == scanID, addAccountRoute == .scan, !Task.isCancelled else { return }
                switch error {
                case CameraScanError.permissionDenied:
                    cameraPresentationState = .denied
                case CameraScanError.noDevice:
                    cameraPresentationState = .unavailable
                case CameraScanError.cancelled:
                    break
                default:
                    addAccountRoute = nil
                    present(error)
                }
            }
        }
    }

    public func cancelCameraScan() {
        addAccountRoute = nil
        cameraMigrationProgress = nil
        let task = cameraScanTask
        task?.cancel()
        guard task != nil else { return }
        Task { await cameraScanner.stop() }
    }

    func dismissAddAccount() {
        if addAccountRoute == .scan || cameraScanTask != nil {
            cancelCameraScan()
        } else {
            addAccountRoute = nil
        }
    }

    func selectAddAccountRoute(_ route: AddAccountRoute) {
        switch route {
        case .scan:
            beginCameraScan()
        case .manual:
            beginManualEntry()
        }
    }

    func toggleFavorite(_ account: OTPAccount) {
        Task {
            do {
                let updated = try await store.setFavorite(id: account.id, isFavorite: !account.isFavorite)
                if let index = accounts.firstIndex(where: { $0.id == updated.id }) {
                    accounts[index] = updated
                }
            } catch {
                present(error)
            }
        }
    }

    func updateAccount(_ account: OTPAccount, issuer: String, accountName: String) async throws {
        let updated = try await store.update(id: account.id, issuer: issuer, accountName: accountName)
        if let index = accounts.firstIndex(where: { $0.id == updated.id }) {
            accounts[index] = updated
        }
    }

    func scanScreenArea() {
        Task {
            do {
                let region = try await screenCapture.selectRegion()
                try await importPayload(screenCapture.captureAndDecode(region))
            } catch ScreenCaptureError.selectionCancelled {
                return
            } catch {
                present(error)
            }
        }
    }

    func importImage(from url: URL) {
        Task {
            let hasSecurityScope = url.startAccessingSecurityScopedResource()
            defer {
                if hasSecurityScope {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let payload = try ImageQRPayloadDecoder(decoder: decoder).decode(contentsOf: url)
                try await importPayload(payload)
            } catch {
                present(error)
            }
        }
    }

    func deletePendingAccount() {
        guard let account = accountPendingDeletion else { return }
        accountPendingDeletion = nil
        Task {
            do {
                try await store.delete(id: account.id)
                await load()
            } catch {
                present(error)
            }
        }
    }

    func copy(_ account: OTPAccount) {
        guard let code = codes[account.id] else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        copiedAccountID = account.id
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard self?.copiedAccountID == account.id else { return }
            self?.copiedAccountID = nil
        }
    }

    func beginExport() {
        Task {
            do {
                try await prepareExport()
            } catch {
                present(error)
            }
        }
    }

    func previousExportBatch() {
        guard exportBatchIndex > 0 else { return }
        exportBatchIndex -= 1
    }

    func nextExportBatch() {
        guard exportBatchIndex + 1 < exportURIs.count else { return }
        exportBatchIndex += 1
    }

    func copyActiveExportURI() {
        guard let activeExportURI else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(activeExportURI, forType: .string)
    }

    func clearError() {
        errorMessage = nil
    }

    private func notifyAboutImport(_ account: OTPAccount) async {
        if await notifications.authorizationState() == .notDetermined {
            _ = try? await notifications.requestAuthorization()
        }
        if await notifications.authorizationState() == .authorized {
            try? await notifications.postScanSuccess(for: account)
        }
    }

    private func startClock() {
        guard clockTask == nil else { return }
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Self.sleepUntilNextSecond()
                guard !Task.isCancelled else { return }
                await self?.refreshCodes()
            }
        }
    }

    private func refreshCodes() async {
        guard !isRefreshingCodes else { return }
        isRefreshingCodes = true
        defer { isRefreshingCodes = false }

        let now = Date()
        currentDate = now
        for account in accounts {
            let counter = Int64((now.timeIntervalSince1970 / Double(account.period)).rounded(.down))
            guard generatedCounterByAccountID[account.id] != counter else { continue }
            generatedCounterByAccountID[account.id] = counter

            let secret: SecretValue
            if let cachedSecret = secretsByAccountID[account.id] {
                secret = cachedSecret
            } else {
                do {
                    let fetchedSecret = try await store.secret(for: account)
                    secretsByAccountID[account.id] = fetchedSecret
                    secret = fetchedSecret
                } catch {
                    codes[account.id] = nil
                    present(error)
                    continue
                }
            }

            do {
                let code = try await generator.code(for: secret, account: account, at: now)
                if codes[account.id] != code {
                    codes[account.id] = code
                }
            } catch {
                codes[account.id] = nil
                present(error)
            }
        }
    }

    private static func sleepUntilNextSecond() async throws {
        let now = Date().timeIntervalSince1970
        let nextSecond = now.rounded(.down) + 1
        let nanoseconds = max(1, Int64((nextSecond - now) * 1_000_000_000))
        try await Task.sleep(for: .nanoseconds(nanoseconds))
    }

    private func present(_ error: Error) {
        errorMessage = message(for: error)
    }

    private func message(for error: Error) -> String {
        if case QRPayloadError.unsupportedMigrationPeriod = error {
            return "Migration exports support only 30-second verification codes."
        }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

public struct AuthenticatorWorkspace: View {
    @Bindable private var coordinator: AuthenticatorCoordinator
    private let settingsContent: AnyView

    public init(
        coordinator: AuthenticatorCoordinator,
        settingsContent: AnyView = AnyView(EmptyView())
    ) {
        self.coordinator = coordinator
        self.settingsContent = settingsContent
    }

    public var body: some View {
        AuthenticatorRootView(
            accounts: coordinator.accounts,
            copiedAccountID: coordinator.copiedAccountID,
            codeFor: { coordinator.codes[$0.id] ?? String(repeating: "-", count: $0.digits.rawValue) },
            isCodeAvailableFor: { coordinator.codes[$0.id] != nil },
            currentDate: coordinator.currentDate,
            onAddManually: { coordinator.beginManualEntry() },
            onScanCamera: { coordinator.beginCameraScan() },
            onScanScreenArea: { coordinator.scanScreenArea() },
            onImportImage: { coordinator.importImage(from: $0) },
            onExport: { coordinator.isPresentingExportConfirmation = true },
            onCopy: { coordinator.copy($0) },
            onEdit: { coordinator.accountPendingEdit = $0 },
            onToggleFavorite: { coordinator.toggleFavorite($0) },
            onDelete: { coordinator.accountPendingDeletion = $0 },
            settingsContent: settingsContent
        )
        .sheet(item: $coordinator.addAccountRoute, onDismiss: { coordinator.dismissAddAccount() }) { _ in
            AddAccountSheet(coordinator: coordinator)
        }
        .sheet(item: $coordinator.accountPendingEdit) { account in
            EditAccountSheet(account: account, coordinator: coordinator)
        }
        .confirmationDialog(
            "Delete \(coordinator.accountPendingDeletion?.issuer ?? "")?",
            isPresented: Binding(
                get: { coordinator.accountPendingDeletion != nil },
                set: { if !$0 { coordinator.accountPendingDeletion = nil } }
            )
        ) {
            Button("Delete Account", role: .destructive) {
                coordinator.deletePendingAccount()
            }
            Button("Cancel", role: .cancel) { coordinator.accountPendingDeletion = nil }
        } message: {
            Text("The account and its Keychain secret will be permanently removed.")
        }
        .confirmationDialog(
            "Export all accounts?",
            isPresented: $coordinator.isPresentingExportConfirmation
        ) {
            Button("Continue") { coordinator.beginExport() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The export QR code contains every stored authenticator secret.")
        }
        .sheet(isPresented: $coordinator.isPresentingExport) {
            ExportSheet(coordinator: coordinator)
        }
        .alert("AuthMyMac", isPresented: Binding(
            get: { coordinator.errorMessage != nil },
            set: { if !$0 { coordinator.clearError() } }
        )) {
            Button("OK") { coordinator.clearError() }
        } message: {
            Text(coordinator.errorMessage ?? "An unexpected error occurred.")
        }
    }
}

private struct ExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var coordinator: AuthenticatorCoordinator

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let uri = coordinator.activeExportURI {
                    if let image = QRCodeImage.make(from: uri) {
                        Image(nsImage: image)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 340, height: 340)
                            .padding(14)
                            .background(.white, in: .rect(cornerRadius: 8))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(.black.opacity(0.08), lineWidth: 1)
                            }
                            .accessibilityLabel("Migration QR Code")
                    } else {
                        ContentUnavailableView("Unable to Generate QR Code", systemImage: "exclamationmark.triangle")
                            .frame(width: 368, height: 368)
                    }
                }

                HStack(spacing: 18) {
                    IconActionButton("Previous QR Code", systemImage: "chevron.left") {
                        coordinator.previousExportBatch()
                    }
                    .disabled(coordinator.exportBatchIndex == 0)

                    Text("\(coordinator.activeExportNumber) of \(coordinator.exportBatchCount)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 56)

                    IconActionButton("Next QR Code", systemImage: "chevron.right") {
                        coordinator.nextExportBatch()
                    }
                    .disabled(coordinator.exportBatchIndex + 1 >= coordinator.exportBatchCount)
                }

                Button("Copy Migration URI", systemImage: "doc.on.doc") {
                    coordinator.copyActiveExportURI()
                }
                .buttonStyle(.bordered)
            }
            .padding(20)
            .navigationTitle("Export Accounts")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(width: 460, height: 560)
    }
}

private enum QRCodeImage {
    static func make(from value: String) -> NSImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(value.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let representation = NSCIImageRep(ciImage: output)
        let image = NSImage(size: output.extent.integral.size)
        image.addRepresentation(representation)
        return image
    }
}

public struct AuthenticatorMenuContent: View {
    @Environment(\.openWindow) private var openWindow

    private let mainWindowID: String
    private let coordinator: AuthenticatorCoordinator

    public init(mainWindowID: String, coordinator: AuthenticatorCoordinator) {
        self.mainWindowID = mainWindowID
        self.coordinator = coordinator
    }

    public var body: some View {
        MenuBarContent(enabledActions: enabledMenuActions) { action in
            switch action {
            case .openAuthenticator:
                openWindow(id: mainWindowID)
                NSApplication.shared.activate()
            case .scanWithCamera:
                openWindow(id: mainWindowID)
                coordinator.beginCameraScan()
            case .exportAccounts:
                openWindow(id: mainWindowID)
                coordinator.isPresentingExportConfirmation = true
            case .quit:
                NSApplication.shared.terminate(nil)
            case .selectScreenArea:
                coordinator.scanScreenArea()
            }
        }
    }

    private var enabledMenuActions: Set<MenuBarAction> {
        var actions = Set(MenuBarAction.allCases)
        if coordinator.accounts.isEmpty {
            actions.remove(.exportAccounts)
        }
        return actions
    }
}

#if DEBUG
extension AuthenticatorCoordinator {
    static func preview(
        route: AddAccountRoute,
        cameraState: CameraPresentationState = .active,
        migrationProgress: MigrationScanProgress? = nil,
        manualError: String? = nil,
        isSubmitting: Bool = false
    ) -> AuthenticatorCoordinator {
        let coordinator = AuthenticatorCoordinator(
            store: PreviewAccountStore(),
            generator: RFC6238TOTPGenerator(),
            decoder: QRPayloadDecoder(),
            notifications: PreviewNotificationPoster(),
            cameraScanner: PreviewCameraScanner(),
            cameraPreviewSession: AVCaptureSession(),
            screenCapture: PreviewScreenCapture()
        )
        coordinator.addAccountRoute = route
        coordinator.cameraPresentationState = cameraState
        coordinator.cameraMigrationProgress = migrationProgress
        coordinator.manualEntryErrorMessage = manualError
        coordinator.isAddingManualAccount = isSubmitting
        return coordinator
    }
}

private actor PreviewAccountStore: AccountStoring {
    func accounts() -> [OTPAccount] { [] }
    func save(_ account: OTPAccount) {}
    func create(_ request: AccountCreationRequest) throws -> OTPAccount { throw StorageError.transactionFailed }
    func create(_ requests: [AccountCreationRequest]) throws -> [OTPAccount] { throw StorageError.transactionFailed }
    func delete(id: UUID) {}
    func update(id: UUID, issuer: String, accountName: String) throws -> OTPAccount { throw StorageError.accountNotFound }
    func setFavorite(id: UUID, isFavorite: Bool) throws -> OTPAccount { throw StorageError.accountNotFound }
    func secret(for account: OTPAccount) throws -> SecretValue { throw StorageError.secretNotFound }
}

private struct PreviewCameraScanner: CameraScanning {
    func authorizationState() async -> CameraAuthorizationState { .authorized }
    func scan() async throws -> QRPayload { throw CameraScanError.cancelled }
    func stop() async {}
}

private struct PreviewNotificationPoster: NotificationPosting {
    func authorizationState() async -> NotificationAuthorizationState { .denied }
    func requestAuthorization() async throws -> Bool { false }
    func postScanSuccess(for account: OTPAccount) async throws {}
}

private struct PreviewScreenCapture: ScreenRegionCapturing {
    func selectRegion() async throws -> ScreenRegion { throw ScreenCaptureError.selectionCancelled }
    func captureAndDecode(_ region: ScreenRegion) async throws -> QRPayload { throw ScreenCaptureError.noQRCodeFound }
    func cancel() async {}
}
#endif
