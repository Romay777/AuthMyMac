import AVFoundation
@testable import Authenticator
import CameraCapture
import Domain
import Notifications
import OTP
import QR
import ScreenCapture
import Storage
import Testing

@Suite("Authenticator coordinator")
struct AuthenticatorCoordinatorTests {
    @Test("Add account routes are mutually exclusive")
    @MainActor
    func addAccountRoutesAreMutuallyExclusive() async {
        let coordinator = makeCoordinator()

        coordinator.beginManualEntry()
        #expect(coordinator.addAccountRoute == .manual)

        coordinator.beginCameraScan()
        #expect(coordinator.addAccountRoute == .scan)

        coordinator.dismissAddAccount()
        #expect(coordinator.addAccountRoute == nil)
    }

    @Test("Toggles favorite state through persistent storage")
    @MainActor
    func togglesFavoriteState() async throws {
        let suite = "AuthMyMacTests.\(UUID().uuidString)"
        let store = SecureAccountStore(suiteName: suite, metadataKey: "accounts", secretStore: InMemorySecretStore())
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let account = try await store.create(
            issuer: "Example",
            accountName: "person@example.com",
            secret: SecretValue(Data("favorite".utf8))
        )
        let coordinator = makeCoordinator(store: store)
        await coordinator.load()

        coordinator.toggleFavorite(account)
        await waitForFavorite(coordinator, id: account.id)

        #expect(coordinator.accounts.first?.isFavorite == true)
        #expect((try await store.accounts()).first?.isFavorite == true)
    }

    @Test("Edits account labels through persistent storage")
    @MainActor
    func editsAccountLabels() async throws {
        let suite = "AuthMyMacTests.\(UUID().uuidString)"
        let store = SecureAccountStore(suiteName: suite, metadataKey: "accounts", secretStore: InMemorySecretStore())
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let account = try await store.create(
            issuer: "Old Issuer",
            accountName: "old@example.com",
            secret: SecretValue(Data("rename".utf8))
        )
        let coordinator = makeCoordinator(store: store)
        await coordinator.load()

        try await coordinator.updateAccount(account, issuer: "New Issuer", accountName: "new@example.com")

        #expect(coordinator.accounts.first?.issuer == "New Issuer")
        #expect(coordinator.accounts.first?.accountName == "new@example.com")
        #expect((try await store.accounts()).first == coordinator.accounts.first)
    }

    @Test("Imports a migration payload through one transactional store operation")
    @MainActor
    func importsMigrationPayload() async throws {
        let suite = "AuthMyMacTests.\(UUID().uuidString)"
        let store = SecureAccountStore(suiteName: suite, metadataKey: "accounts", secretStore: InMemorySecretStore())
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let coordinator = AuthenticatorCoordinator(
            store: store,
            generator: RFC6238TOTPGenerator(),
            decoder: QRPayloadDecoder(),
            notifications: NoopNotificationPoster(),
            cameraScanner: NoopCameraScanner(),
            cameraPreviewSession: AVCaptureSession(),
            screenCapture: NoopScreenCapture()
        )
        let payload = QRPayload.migration([
            account(issuer: "One", accountName: "one@example.com", secret: "one"),
            account(issuer: "Two", accountName: "two@example.com", secret: "two"),
        ])

        try await coordinator.importPayload(payload)

        #expect(coordinator.accounts.count == 2)
        #expect((try await store.accounts()).count == 2)
    }

    @Test("Caches authorized Keychain reads while generating codes")
    @MainActor
    func cachesSecretsBetweenRefreshes() async throws {
        let account = try OTPAccount(
            issuer: "Example",
            accountName: "person@example.com",
            secretKeychainID: "test-secret"
        )
        let store = CountingAccountStore(account: account)
        let coordinator = makeCoordinator(store: store)

        await coordinator.load()
        await coordinator.load()

        #expect(await store.secretReadCount() == 1)
    }

    @Test("Does not copy a missing code and exposes generation failures")
    @MainActor
    func doesNotCopyMissingCode() async throws {
        let account = try OTPAccount(
            issuer: "Example",
            accountName: "person@example.com",
            secretKeychainID: "test-secret"
        )
        let coordinator = AuthenticatorCoordinator(
            store: CountingAccountStore(account: account),
            generator: FailingTOTPGenerator(),
            decoder: QRPayloadDecoder(),
            notifications: NoopNotificationPoster(),
            cameraScanner: NoopCameraScanner(),
            cameraPreviewSession: AVCaptureSession(),
            screenCapture: NoopScreenCapture()
        )

        await coordinator.load()
        coordinator.copy(account)

        #expect(coordinator.codes[account.id] == nil)
        #expect(coordinator.copiedAccountID == nil)
        #expect(coordinator.errorMessage != nil)
    }

    @Test("Cancels the retained camera task when the sheet dismisses before scanning starts")
    @MainActor
    func cancelsCameraTaskBeforeScannerContinuation() async throws {
        let suite = "AuthMyMacTests.\(UUID().uuidString)"
        let store = SecureAccountStore(suiteName: suite, metadataKey: "accounts", secretStore: InMemorySecretStore())
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let scanner = DelayedCameraScanner()
        let coordinator = AuthenticatorCoordinator(
            store: store,
            generator: RFC6238TOTPGenerator(),
            decoder: QRPayloadDecoder(),
            notifications: NoopNotificationPoster(),
            cameraScanner: scanner,
            cameraPreviewSession: AVCaptureSession(),
            screenCapture: NoopScreenCapture()
        )

        coordinator.beginCameraScan()
        coordinator.cancelCameraScan()
        await scanner.waitUntilStopped()

        #expect(await scanner.stopCallCount() == 1)
        #expect(await scanner.scanCallCount() == 0)
        #expect((try await store.accounts()).isEmpty)
    }

    @Test("Publishes migration progress and clears it when scanning is cancelled")
    @MainActor
    func publishesMigrationScanProgress() async {
        let scanner = ProgressCameraScanner()
        let coordinator = AuthenticatorCoordinator(
            store: SecureAccountStore(
                suiteName: "AuthMyMacTests.\(UUID().uuidString)",
                metadataKey: "accounts",
                secretStore: InMemorySecretStore()
            ),
            generator: RFC6238TOTPGenerator(),
            decoder: QRPayloadDecoder(),
            notifications: NoopNotificationPoster(),
            cameraScanner: scanner,
            cameraPreviewSession: AVCaptureSession(),
            screenCapture: NoopScreenCapture()
        )

        coordinator.beginCameraScan()
        #expect(await waitForMigrationProgress(coordinator))
        #expect(coordinator.cameraMigrationProgress == MigrationScanProgress(scannedCount: 1, totalCount: 2))

        coordinator.cancelCameraScan()
        #expect(coordinator.cameraMigrationProgress == nil)
    }

    @Test("Restarts camera scanning after switching through manual entry")
    @MainActor
    func restartsCameraAfterManualEntry() async {
        let suite = "AuthMyMacTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let scanner = RestartableCameraScanner()
        let coordinator = AuthenticatorCoordinator(
            store: SecureAccountStore(
                suiteName: suite,
                metadataKey: "accounts",
                secretStore: InMemorySecretStore()
            ),
            generator: RFC6238TOTPGenerator(),
            decoder: QRPayloadDecoder(),
            notifications: NoopNotificationPoster(),
            cameraScanner: scanner,
            cameraPreviewSession: AVCaptureSession(),
            screenCapture: NoopScreenCapture()
        )

        coordinator.beginCameraScan()
        #expect(await scanner.waitForScanCallCount(1))

        coordinator.beginManualEntry()
        coordinator.beginCameraScan()

        #expect(await scanner.waitForScanCallCount(2))
        #expect(coordinator.addAccountRoute == .scan)
        coordinator.dismissAddAccount()
        #expect(await scanner.waitUntilStopped())
    }

    @Test("Waits for camera shutdown before restarting after manual entry")
    @MainActor
    func waitsForCameraShutdownBeforeRestarting() async {
        let suite = "AuthMyMacTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let scanner = ShutdownGatedCameraScanner()
        let coordinator = AuthenticatorCoordinator(
            store: SecureAccountStore(
                suiteName: suite,
                metadataKey: "accounts",
                secretStore: InMemorySecretStore()
            ),
            generator: RFC6238TOTPGenerator(),
            decoder: QRPayloadDecoder(),
            notifications: NoopNotificationPoster(),
            cameraScanner: scanner,
            cameraPreviewSession: AVCaptureSession(),
            screenCapture: NoopScreenCapture()
        )

        coordinator.beginCameraScan()
        #expect(await scanner.waitForScanCallCount(1))

        coordinator.beginManualEntry()
        coordinator.beginCameraScan()
        await scanner.waitUntilStopBegins()
        #expect(await scanner.scanCallCount() == 1)

        await scanner.finishStopping()
        #expect(await scanner.waitForScanCallCount(2))
        coordinator.dismissAddAccount()
    }

    @Test("A successful manual retry clears an earlier validation error")
    @MainActor
    func successfulManualRetryClearsValidationError() async throws {
        let suite = "AuthMyMacTests.\(UUID().uuidString)"
        let store = SecureAccountStore(suiteName: suite, metadataKey: "accounts", secretStore: InMemorySecretStore())
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let coordinator = AuthenticatorCoordinator(
            store: store,
            generator: RFC6238TOTPGenerator(),
            decoder: QRPayloadDecoder(),
            notifications: NoopNotificationPoster(),
            cameraScanner: NoopCameraScanner(),
            cameraPreviewSession: AVCaptureSession(),
            screenCapture: NoopScreenCapture()
        )
        coordinator.manualIssuer = "Example"
        coordinator.manualAccountName = "person@example.com"
        coordinator.manualSecret = "M"

        coordinator.addManualAccount()
        await waitForManualAdd(coordinator)

        #expect(coordinator.manualEntryErrorMessage == Base32Error.invalidPadding.errorDescription)

        coordinator.manualSecret = "JBSWY3DPEHPK3PXP"
        coordinator.addManualAccount()
        await waitForManualAdd(coordinator)

        #expect(coordinator.manualEntryErrorMessage == nil)
        #expect((try await store.accounts()).count == 1)
    }

    @Test("Camera scan errors provide actionable descriptions")
    func cameraErrorDescriptions() {
        #expect(CameraScanError.permissionDenied.errorDescription?.contains("System Settings") == true)
        #expect(CameraScanError.noDevice.errorDescription == "No available camera was found.")
        #expect(CameraScanError.invalidPayload.errorDescription?.contains("authenticator") == true)
    }

    @Test("Cancelling screen selection does not present an error")
    @MainActor
    func ignoresScreenSelectionCancellation() async {
        let screenCapture = CancellingScreenCapture()
        let coordinator = AuthenticatorCoordinator(
            store: SecureAccountStore(
                suiteName: "AuthMyMacTests.\(UUID().uuidString)",
                metadataKey: "accounts",
                secretStore: InMemorySecretStore()
            ),
            generator: RFC6238TOTPGenerator(),
            decoder: QRPayloadDecoder(),
            notifications: NoopNotificationPoster(),
            cameraScanner: NoopCameraScanner(),
            cameraPreviewSession: AVCaptureSession(),
            screenCapture: screenCapture
        )

        coordinator.scanScreenArea()
        await screenCapture.waitUntilSelected()
        for _ in 0..<100 { await Task.yield() }

        #expect(coordinator.errorMessage == nil)
    }

    @Test("Dismisses the scanner and explains a duplicate account")
    @MainActor
    func presentsDuplicateCameraImportError() async throws {
        let suite = "AuthMyMacTests.\(UUID().uuidString)"
        let store = SecureAccountStore(
            suiteName: suite,
            metadataKey: "accounts",
            secretStore: InMemorySecretStore()
        )
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let duplicate = account(
            issuer: "Example",
            accountName: "person@example.com",
            secret: "duplicate"
        )
        _ = try await store.create(
            issuer: duplicate.issuer,
            accountName: duplicate.accountName,
            secret: duplicate.secret
        )
        let coordinator = AuthenticatorCoordinator(
            store: store,
            generator: RFC6238TOTPGenerator(),
            decoder: QRPayloadDecoder(),
            notifications: NoopNotificationPoster(),
            cameraScanner: OneShotCameraScanner(payload: .account(duplicate)),
            cameraPreviewSession: AVCaptureSession(),
            screenCapture: NoopScreenCapture()
        )

        coordinator.beginCameraScan()
        while coordinator.errorMessage == nil { await Task.yield() }

        #expect(coordinator.addAccountRoute == nil)
        #expect(coordinator.errorMessage == "This authenticator account already exists.")
    }

    private func account(issuer: String, accountName: String, secret: String) -> ParsedOTPAccount {
        ParsedOTPAccount(
            issuer: issuer,
            accountName: accountName,
            secret: SecretValue(Data(secret.utf8)),
            algorithm: .sha1,
            digits: .six,
            period: 30
        )
    }

    @MainActor
    private func makeCoordinator(store: (any AccountStoring)? = nil) -> AuthenticatorCoordinator {
        AuthenticatorCoordinator(
            store: store ?? SecureAccountStore(
                suiteName: "AuthMyMacTests.\(UUID().uuidString)",
                metadataKey: "accounts",
                secretStore: InMemorySecretStore()
            ),
            generator: RFC6238TOTPGenerator(),
            decoder: QRPayloadDecoder(),
            notifications: NoopNotificationPoster(),
            cameraScanner: NoopCameraScanner(),
            cameraPreviewSession: AVCaptureSession(),
            screenCapture: NoopScreenCapture()
        )
    }

    @MainActor
    private func waitForFavorite(_ coordinator: AuthenticatorCoordinator, id: UUID) async {
        while coordinator.accounts.first(where: { $0.id == id })?.isFavorite != true {
            await Task.yield()
        }
    }

    @MainActor
    private func waitForManualAdd(_ coordinator: AuthenticatorCoordinator) async {
        while coordinator.isAddingManualAccount {
            await Task.yield()
        }
    }

    @MainActor
    private func waitForMigrationProgress(_ coordinator: AuthenticatorCoordinator) async -> Bool {
        for _ in 0..<10_000 {
            if coordinator.cameraMigrationProgress != nil { return true }
            await Task.yield()
        }
        return false
    }
}

private struct NoopCameraScanner: CameraScanning {
    func authorizationState() async -> CameraAuthorizationState { .unavailable }
    func scan() async throws -> QRPayload { throw CameraScanError.cancelled }
    func stop() async {}
}

private actor CountingAccountStore: AccountStoring {
    private let account: OTPAccount
    private var reads = 0

    init(account: OTPAccount) {
        self.account = account
    }

    func accounts() -> [OTPAccount] { [account] }
    func save(_ account: OTPAccount) {}
    func create(_ request: AccountCreationRequest) throws -> OTPAccount { throw StorageError.transactionFailed }
    func create(_ requests: [AccountCreationRequest]) throws -> [OTPAccount] { throw StorageError.transactionFailed }
    func delete(id: UUID) {}
    func update(id: UUID, issuer: String, accountName: String) throws -> OTPAccount { throw StorageError.accountNotFound }
    func setFavorite(id: UUID, isFavorite: Bool) throws -> OTPAccount { throw StorageError.accountNotFound }

    func secret(for account: OTPAccount) -> SecretValue {
        reads += 1
        return SecretValue(Data("secret".utf8))
    }

    func secretReadCount() -> Int { reads }
}

private struct FailingTOTPGenerator: TOTPGenerating {
    func code(for secret: SecretValue, account: OTPAccount, at date: Date) async throws -> String {
        throw TOTPGenerationError.invalidSecret
    }
}

private struct OneShotCameraScanner: CameraScanning {
    let payload: QRPayload

    func authorizationState() async -> CameraAuthorizationState { .authorized }
    func scan() async throws -> QRPayload { payload }
    func stop() async {}
}

private actor DelayedCameraScanner: CameraScanning {
    private var wasStopped = false
    private var wasScanned = false
    private var pendingScan: CheckedContinuation<QRPayload, Error>?
    private var stopWaiters: [CheckedContinuation<Void, Never>] = []

    func authorizationState() async -> CameraAuthorizationState { .authorized }

    func scan() async throws -> QRPayload {
        wasScanned = true
        guard !wasStopped else { throw CameraScanError.cancelled }
        return try await withCheckedThrowingContinuation { continuation in
            if wasStopped {
                continuation.resume(throwing: CameraScanError.cancelled)
            } else {
                pendingScan = continuation
            }
        }
    }

    func stop() async {
        wasStopped = true
        let scan = pendingScan
        pendingScan = nil
        scan?.resume(throwing: CameraScanError.cancelled)
        let waiters = stopWaiters
        stopWaiters = []
        waiters.forEach { $0.resume() }
    }

    func waitUntilStopped() async {
        guard !wasStopped else { return }
        await withCheckedContinuation { stopWaiters.append($0) }
    }

    func stopCallCount() -> Int {
        wasStopped ? 1 : 0
    }

    func scanCallCount() -> Int {
        wasScanned ? 1 : 0
    }
}

private actor ProgressCameraScanner: CameraScanning {
    private var pendingScan: CheckedContinuation<QRPayload, Error>?

    func authorizationState() async -> CameraAuthorizationState { .authorized }

    func scan() async throws -> QRPayload {
        throw CameraScanError.cancelled
    }

    func scan(
        onMigrationProgress: @escaping @Sendable (MigrationScanProgress) -> Void
    ) async throws -> QRPayload {
        onMigrationProgress(MigrationScanProgress(scannedCount: 1, totalCount: 2))
        return try await withCheckedThrowingContinuation { pendingScan = $0 }
    }

    func stop() async {
        let scan = pendingScan
        pendingScan = nil
        scan?.resume(throwing: CameraScanError.cancelled)
    }
}

private actor RestartableCameraScanner: CameraScanning {
    private var scanCalls = 0
    private var pendingScans: [CheckedContinuation<QRPayload, Error>] = []

    func authorizationState() async -> CameraAuthorizationState { .authorized }

    func scan() async throws -> QRPayload {
        scanCalls += 1
        return try await withCheckedThrowingContinuation { pendingScans.append($0) }
    }

    func stop() async {
        let scans = pendingScans
        pendingScans = []
        scans.forEach { $0.resume(throwing: CameraScanError.cancelled) }
    }

    func waitForScanCallCount(_ expectedCount: Int) async -> Bool {
        for _ in 0..<10_000 {
            if scanCalls >= expectedCount { return true }
            await Task.yield()
        }
        return false
    }

    func waitUntilStopped() async -> Bool {
        for _ in 0..<10_000 {
            if pendingScans.isEmpty { return true }
            await Task.yield()
        }
        return false
    }
}

private actor ShutdownGatedCameraScanner: CameraScanning {
    private var scanCalls = 0
    private var pendingScan: CheckedContinuation<QRPayload, Error>?
    private var stopWaiters: [CheckedContinuation<Void, Never>] = []
    private var hasStartedStopping = false
    private var isStopped = false
    private var stopStartWaiters: [CheckedContinuation<Void, Never>] = []

    func authorizationState() async -> CameraAuthorizationState { .authorized }

    func scan() async throws -> QRPayload {
        scanCalls += 1
        return try await withCheckedThrowingContinuation { pendingScan = $0 }
    }

    func stop() async {
        hasStartedStopping = true
        let startWaiters = stopStartWaiters
        stopStartWaiters = []
        startWaiters.forEach { $0.resume() }
        if !isStopped {
            await withCheckedContinuation { stopWaiters.append($0) }
        }
        let scan = pendingScan
        pendingScan = nil
        scan?.resume(throwing: CameraScanError.cancelled)
    }

    func waitForScanCallCount(_ expectedCount: Int) async -> Bool {
        for _ in 0..<10_000 {
            if scanCalls >= expectedCount { return true }
            await Task.yield()
        }
        return false
    }

    func scanCallCount() -> Int { scanCalls }

    func waitUntilStopBegins() async {
        guard !hasStartedStopping else { return }
        await withCheckedContinuation { stopStartWaiters.append($0) }
    }

    func finishStopping() {
        isStopped = true
        let waiters = stopWaiters
        stopWaiters = []
        waiters.forEach { $0.resume() }
    }
}

private struct NoopScreenCapture: ScreenRegionCapturing {
    func selectRegion() async throws -> ScreenRegion { throw ScreenCaptureError.selectionCancelled }
    func captureAndDecode(_ region: ScreenRegion) async throws -> QRPayload { throw ScreenCaptureError.noQRCodeFound }
    func cancel() async {}
}

private actor CancellingScreenCapture: ScreenRegionCapturing {
    private var didSelect = false

    func selectRegion() throws -> ScreenRegion {
        didSelect = true
        throw ScreenCaptureError.selectionCancelled
    }

    func captureAndDecode(_ region: ScreenRegion) throws -> QRPayload {
        throw ScreenCaptureError.noQRCodeFound
    }

    func cancel() {}

    func waitUntilSelected() async {
        while !didSelect { await Task.yield() }
    }
}

private struct NoopNotificationPoster: NotificationPosting {
    func authorizationState() async -> NotificationAuthorizationState { .denied }
    func requestAuthorization() async throws -> Bool { false }
    func postScanSuccess(for account: OTPAccount) async throws {}
}
