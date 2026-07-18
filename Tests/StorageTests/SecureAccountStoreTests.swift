import Domain
import Foundation
import Storage
import Testing

@Suite("Secure account storage")
struct SecureAccountStoreTests {
    @Test("Uses separate development and release storage namespaces")
    func separatesBuildConfigurations() async throws {
        #expect(StorageNamespace.development.keychainService != StorageNamespace.release.keychainService)
        #expect(StorageNamespace.development.metadataKey != StorageNamespace.release.metadataKey)

        let suite = "AuthMyMacTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let developmentStore = SecureAccountStore(
            namespace: .development,
            suiteName: suite,
            secretStore: InMemorySecretStore()
        )
        let releaseStore = SecureAccountStore(
            namespace: .release,
            suiteName: suite,
            secretStore: InMemorySecretStore()
        )

        _ = try await developmentStore.create(
            issuer: "Development",
            accountName: "developer@example.com",
            secret: SecretValue(Data([0x01, 0x02, 0x03]))
        )

        #expect((try await developmentStore.accounts()).count == 1)
        #expect(try await releaseStore.accounts().isEmpty)
    }

    @Test("Selects the development namespace for debug builds")
    func selectsCurrentNamespace() {
#if DEBUG
        #expect(StorageNamespace.current == .development)
#else
        #expect(StorageNamespace.current == .release)
#endif
    }

    @Test("Updates account labels without changing identity or secret")
    func updatesAccountLabels() async throws {
        let suite = "AuthMyMacTests.\(UUID().uuidString)"
        let secretStore = InMemorySecretStore()
        let store = SecureAccountStore(suiteName: suite, metadataKey: "accounts", secretStore: secretStore)
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let secret = SecretValue(Data("rename-secret".utf8))
        let account = try await store.create(issuer: "Old Issuer", accountName: "old@example.com", secret: secret)

        let updated = try await store.update(
            id: account.id,
            issuer: "  New Issuer  ",
            accountName: "  new@example.com  "
        )

        #expect(updated.id == account.id)
        #expect(updated.issuer == "New Issuer")
        #expect(updated.accountName == "new@example.com")
        #expect(updated.secretKeychainID == account.secretKeychainID)
        #expect(try await store.accounts() == [updated])
        #expect(try await store.secret(for: updated) == secret)
    }

    @Test("Persists favorite metadata without changing the secret")
    func persistsFavoriteState() async throws {
        let suite = "AuthMyMacTests.\(UUID().uuidString)"
        let secretStore = InMemorySecretStore()
        let store = SecureAccountStore(suiteName: suite, metadataKey: "accounts", secretStore: secretStore)
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let secret = SecretValue(Data("favorite-secret".utf8))
        let account = try await store.create(issuer: "Example", accountName: "person@example.com", secret: secret)

        let favorite = try await store.setFavorite(id: account.id, isFavorite: true)

        #expect(favorite.isFavorite)
        #expect(try await store.accounts() == [favorite])
        #expect(try await store.secret(for: favorite) == secret)
    }

    @Test("Stores metadata separately from the injected secret store")
    func createsAndDeletesAccount() async throws {
        let suite = "AuthMyMacTests.\(UUID().uuidString)"
        let secretStore = InMemorySecretStore()
        let store = SecureAccountStore(suiteName: suite, metadataKey: "accounts", secretStore: secretStore)
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }

        let secret = SecretValue(Data("secret-data".utf8))
        let account = try await store.create(issuer: "Example", accountName: "person@example.com", secret: secret)
        #expect(try await store.accounts() == [account])
        #expect(try await store.secret(for: account) == secret)

        try await store.delete(id: account.id)
        #expect(try await store.accounts().isEmpty)
        await #expect(throws: StorageError.secretNotFound) { try await secretStore.read(id: account.secretKeychainID) }
    }

    @Test("Rejects duplicate secret material before writing metadata")
    func rejectsDuplicateSecrets() async throws {
        let suite = "AuthMyMacTests.\(UUID().uuidString)"
        let store = SecureAccountStore(suiteName: suite, metadataKey: "accounts", secretStore: InMemorySecretStore())
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }

        let secret = SecretValue(Data("same".utf8))
        _ = try await store.create(issuer: "One", accountName: "one", secret: secret)
        await #expect(throws: StorageError.duplicateAccount) {
            try await store.create(issuer: "Two", accountName: "two", secret: secret)
        }
        #expect((try await store.accounts()).count == 1)
    }

    @Test("Compares secrets with lengths beyond one byte without trapping")
    func acceptsDifferentLongSecret() async throws {
        let suite = "AuthMyMacTests.\(UUID().uuidString)"
        let store = SecureAccountStore(suiteName: suite, metadataKey: "accounts", secretStore: InMemorySecretStore())
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }

        _ = try await store.create(issuer: "Short", accountName: "short", secret: SecretValue(Data([0x01])))
        _ = try await store.create(
            issuer: "Long",
            accountName: "long",
            secret: SecretValue(Data(repeating: 0x01, count: 257))
        )

        #expect((try await store.accounts()).count == 2)
    }

    @Test("Rolls back every secret when a later write in a batch fails")
    func rollsBackFailedBatch() async throws {
        let suite = "AuthMyMacTests.\(UUID().uuidString)"
        let secretStore = FailingSecretStore()
        let store = SecureAccountStore(suiteName: suite, metadataKey: "accounts", secretStore: secretStore)
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }

        let existing = try await store.create(issuer: "Existing", accountName: "one", secret: SecretValue(Data("one".utf8)))
        await secretStore.failAfterSuccessfulWrites(1)

        await #expect(throws: StorageError.transactionFailed) {
            try await store.create([
                AccountCreationRequest(issuer: "Two", accountName: "two", secret: SecretValue(Data("two".utf8))),
                AccountCreationRequest(issuer: "Three", accountName: "three", secret: SecretValue(Data("three".utf8))),
            ])
        }

        #expect(try await store.accounts() == [existing])
        #expect(await secretStore.count() == 1)
    }

    @Test("Rejects duplicate material within a batch before any Keychain write")
    func preflightsDuplicateBatch() async throws {
        let suite = "AuthMyMacTests.\(UUID().uuidString)"
        let secretStore = FailingSecretStore()
        let store = SecureAccountStore(suiteName: suite, metadataKey: "accounts", secretStore: secretStore)
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let secret = SecretValue(Data("same".utf8))

        await #expect(throws: StorageError.duplicateAccount) {
            try await store.create([
                AccountCreationRequest(issuer: "One", accountName: "one", secret: secret),
                AccountCreationRequest(issuer: "Two", accountName: "two", secret: secret),
            ])
        }

        #expect(await secretStore.writeAttemptCount() == 0)
        #expect(try await store.accounts().isEmpty)
    }

    @Test("Reports corrupt metadata instead of treating it as an empty store")
    func reportsCorruptMetadata() async throws {
        let suite = "AuthMyMacTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set(Data("not-json".utf8), forKey: "accounts")
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SecureAccountStore(suiteName: suite, metadataKey: "accounts", secretStore: InMemorySecretStore())
        await #expect(throws: StorageError.corruptMetadata) {
            _ = try await store.accounts()
        }
    }
}

private actor FailingSecretStore: SecretStoring {
    private var secrets: [String: SecretValue] = [:]
    private var successfulWritesBeforeFailure: Int?
    private var writeAttempts = 0

    func read(id: String) throws -> SecretValue {
        guard let secret = secrets[id] else { throw StorageError.secretNotFound }
        return secret
    }

    func write(_ secret: SecretValue, id: String) throws {
        writeAttempts += 1
        if let successfulWritesBeforeFailure {
            guard successfulWritesBeforeFailure > 0 else {
                throw StorageError.transactionFailed
            }
            self.successfulWritesBeforeFailure = successfulWritesBeforeFailure - 1
        }
        guard secrets[id] == nil else { throw StorageError.duplicateAccount }
        secrets[id] = secret
    }

    func delete(id: String) {
        secrets[id] = nil
    }

    func failAfterSuccessfulWrites(_ count: Int) {
        successfulWritesBeforeFailure = count
    }

    func count() -> Int {
        secrets.count
    }

    func writeAttemptCount() -> Int {
        writeAttempts
    }
}
