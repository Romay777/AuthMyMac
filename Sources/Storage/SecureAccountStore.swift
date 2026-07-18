import Domain
import Foundation
import Security

public actor SecureAccountStore: AccountStoring {
    private let metadataStore: UserDefaults
    private let metadataKey: String
    private let secretStore: any SecretStoring
    private var cachedAccounts: [OTPAccount]
    private let metadataLoadError: StorageError?

    public init(
        namespace: StorageNamespace = .current,
        suiteName: String? = nil,
        metadataKey: String? = nil,
        secretStore: (any SecretStoring)? = nil
    ) {
        self.metadataStore = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        self.metadataKey = metadataKey ?? namespace.metadataKey
        self.secretStore = secretStore ?? KeychainSecretStore(service: namespace.keychainService)
        if let storedData = self.metadataStore.data(forKey: self.metadataKey) {
            do {
                self.cachedAccounts = try JSONDecoder().decode([OTPAccount].self, from: storedData)
                self.metadataLoadError = nil
            } catch {
                self.cachedAccounts = []
                self.metadataLoadError = .corruptMetadata
            }
        } else {
            self.cachedAccounts = []
            self.metadataLoadError = nil
        }
    }

    public func accounts() throws -> [OTPAccount] {
        try ensureMetadataIsAvailable()
        return cachedAccounts.sorted { lhs, rhs in
            lhs.sortOrder == rhs.sortOrder ? lhs.createdAt < rhs.createdAt : lhs.sortOrder < rhs.sortOrder
        }
    }

    public func save(_ account: OTPAccount) async throws {
        try ensureMetadataIsAvailable()
        guard !cachedAccounts.contains(where: { $0.id == account.id }) else {
            throw StorageError.duplicateAccount
        }
        cachedAccounts.append(account)
        try persist()
    }

    public func create(
        issuer: String,
        accountName: String,
        secret: SecretValue,
        algorithm: OTPAlgorithm = .sha1,
        digits: OTPDigits = .six,
        period: Int = 30
    ) async throws -> OTPAccount {
        try await create(AccountCreationRequest(
            issuer: issuer,
            accountName: accountName,
            secret: secret,
            algorithm: algorithm,
            digits: digits,
            period: period
        ))
    }

    public func create(_ request: AccountCreationRequest) async throws -> OTPAccount {
        guard let account = try await create([request]).first else {
            throw StorageError.transactionFailed
        }
        return account
    }

    /// Writes every secret and the corresponding metadata set as one coordinated operation.
    public func create(_ requests: [AccountCreationRequest]) async throws -> [OTPAccount] {
        try ensureMetadataIsAvailable()
        guard !requests.isEmpty else { throw StorageError.transactionFailed }

        let accounts = try makeAccounts(for: requests)
        try await preflight(requests)

        let previousAccounts = cachedAccounts
        var writtenSecretIDs: [String] = []
        do {
            for (request, account) in zip(requests, accounts) {
                try await secretStore.write(request.secret, id: account.secretKeychainID)
                writtenSecretIDs.append(account.secretKeychainID)
            }
            cachedAccounts.append(contentsOf: accounts)
            try persist()
            return accounts
        } catch {
            cachedAccounts = previousAccounts
            try? persist()
            for secretID in writtenSecretIDs.reversed() {
                try? await secretStore.delete(id: secretID)
            }
            throw error
        }
    }

    public func delete(id: UUID) async throws {
        try ensureMetadataIsAvailable()
        guard let index = cachedAccounts.firstIndex(where: { $0.id == id }) else {
            throw StorageError.accountNotFound
        }
        let account = cachedAccounts.remove(at: index)
        do {
            try persist()
        } catch {
            cachedAccounts.insert(account, at: index)
            throw error
        }
        do {
            try await secretStore.delete(id: account.secretKeychainID)
        } catch {
            // Metadata is restored so an inaccessible secret is never silently forgotten.
            cachedAccounts.insert(account, at: index)
            try? persist()
            throw error
        }
    }

    public func setFavorite(id: UUID, isFavorite: Bool) async throws -> OTPAccount {
        try ensureMetadataIsAvailable()
        guard let index = cachedAccounts.firstIndex(where: { $0.id == id }) else {
            throw StorageError.accountNotFound
        }
        let previous = cachedAccounts[index]
        let updated = try OTPAccount(
            id: previous.id,
            issuer: previous.issuer,
            accountName: previous.accountName,
            secretKeychainID: previous.secretKeychainID,
            algorithm: previous.algorithm,
            digits: previous.digits,
            period: previous.period,
            createdAt: previous.createdAt,
            sortOrder: previous.sortOrder,
            isFavorite: isFavorite
        )
        cachedAccounts[index] = updated
        do {
            try persist()
            return updated
        } catch {
            cachedAccounts[index] = previous
            throw error
        }
    }

    public func update(id: UUID, issuer: String, accountName: String) async throws -> OTPAccount {
        try ensureMetadataIsAvailable()
        guard let index = cachedAccounts.firstIndex(where: { $0.id == id }) else {
            throw StorageError.accountNotFound
        }
        let previous = cachedAccounts[index]
        let updated = try OTPAccount(
            id: previous.id,
            issuer: issuer,
            accountName: accountName,
            secretKeychainID: previous.secretKeychainID,
            algorithm: previous.algorithm,
            digits: previous.digits,
            period: previous.period,
            createdAt: previous.createdAt,
            sortOrder: previous.sortOrder,
            isFavorite: previous.isFavorite
        )
        cachedAccounts[index] = updated
        do {
            try persist()
            return updated
        } catch {
            cachedAccounts[index] = previous
            throw error
        }
    }

    public func secret(for account: OTPAccount) async throws -> SecretValue {
        try ensureMetadataIsAvailable()
        return try await secretStore.read(id: account.secretKeychainID)
    }

    private func contains(secret: SecretValue) async throws -> Bool {
        for account in cachedAccounts {
            let existing = try await secretStore.read(id: account.secretKeychainID)
            if constantTimeEqual(existing.data(), secret.data()) {
                return true
            }
        }
        return false
    }

    private func makeAccounts(for requests: [AccountCreationRequest]) throws -> [OTPAccount] {
        let nextSortOrder = (cachedAccounts.map(\.sortOrder).max() ?? -1) + 1
        return try requests.enumerated().map { offset, request in
            guard !request.secret.data().isEmpty else { throw StorageError.transactionFailed }
            let id = UUID()
            return try OTPAccount(
                id: id,
                issuer: request.issuer,
                accountName: request.accountName,
                secretKeychainID: id.uuidString,
                algorithm: request.algorithm,
                digits: request.digits,
                period: request.period,
                sortOrder: nextSortOrder + offset
            )
        }
    }

    private func preflight(_ requests: [AccountCreationRequest]) async throws {
        for index in requests.indices {
            if try await contains(secret: requests[index].secret) {
                throw StorageError.duplicateAccount
            }
            for candidate in requests[requests.index(after: index)...] {
                if constantTimeEqual(requests[index].secret.data(), candidate.secret.data()) {
                    throw StorageError.duplicateAccount
                }
            }
        }
    }

    private func ensureMetadataIsAvailable() throws {
        if let metadataLoadError { throw metadataLoadError }
    }

    private func persist() throws {
        metadataStore.set(try JSONEncoder().encode(cachedAccounts), forKey: metadataKey)
    }
}

public struct KeychainSecretStore: SecretStoring {
    private let service: String

    public init(service: String = StorageNamespace.current.keychainService) {
        self.service = service
    }

    public func read(id: String) throws -> SecretValue {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: id,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            throw status == errSecItemNotFound ? StorageError.secretNotFound : StorageError.transactionFailed
        }
        return SecretValue(data)
    }

    public func write(_ secret: SecretValue, id: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: id,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable: false,
            kSecValueData: secret.data(),
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw status == errSecDuplicateItem ? StorageError.duplicateAccount : StorageError.transactionFailed
        }
    }

    public func delete(id: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: id,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StorageError.transactionFailed
        }
    }
}

public actor InMemorySecretStore: SecretStoring {
    private var secrets: [String: SecretValue] = [:]

    public init() {}

    public func read(id: String) throws -> SecretValue {
        guard let secret = secrets[id] else { throw StorageError.secretNotFound }
        return secret
    }

    public func write(_ secret: SecretValue, id: String) throws {
        guard secrets[id] == nil else { throw StorageError.duplicateAccount }
        secrets[id] = secret
    }

    public func delete(id: String) {
        secrets[id] = nil
    }
}

private func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
    let count = max(lhs.count, rhs.count)
    var difference = UInt(lhs.count ^ rhs.count)
    for index in 0..<count {
        let left = index < lhs.count ? lhs[index] : 0
        let right = index < rhs.count ? rhs[index] : 0
        difference |= UInt(left ^ right)
    }
    return difference == 0
}
