import Domain
import Foundation

/// Serializes account metadata operations. Implementations should be actors.
public protocol AccountStoring: Actor {
    func accounts() async throws -> [OTPAccount]
    func save(_ account: OTPAccount) async throws
    func create(_ request: AccountCreationRequest) async throws -> OTPAccount
    func create(_ requests: [AccountCreationRequest]) async throws -> [OTPAccount]
    func delete(id: UUID) async throws
    func update(id: UUID, issuer: String, accountName: String) async throws -> OTPAccount
    func setFavorite(id: UUID, isFavorite: Bool) async throws -> OTPAccount
    func secret(for account: OTPAccount) async throws -> SecretValue
}

/// Validated account material supplied to the atomic import operation.
public struct AccountCreationRequest: Sendable {
    public let issuer: String
    public let accountName: String
    public let secret: SecretValue
    public let algorithm: OTPAlgorithm
    public let digits: OTPDigits
    public let period: Int

    public init(
        issuer: String,
        accountName: String,
        secret: SecretValue,
        algorithm: OTPAlgorithm = .sha1,
        digits: OTPDigits = .six,
        period: Int = 30
    ) {
        self.issuer = issuer
        self.accountName = accountName
        self.secret = secret
        self.algorithm = algorithm
        self.digits = digits
        self.period = period
    }
}

/// Keychain boundary kept separate from the metadata repository.
public protocol SecretStoring: Sendable {
    func read(id: String) async throws -> SecretValue
    func write(_ secret: SecretValue, id: String) async throws
    func delete(id: String) async throws
}

public enum StorageError: LocalizedError, Equatable, Sendable {
    case accountNotFound
    case secretNotFound
    case duplicateAccount
    case corruptMetadata
    case transactionFailed

    public var errorDescription: String? {
        switch self {
        case .accountNotFound:
            "The authenticator account could not be found."
        case .secretNotFound:
            "The authenticator secret could not be found in Keychain."
        case .duplicateAccount:
            "This authenticator account already exists."
        case .corruptMetadata:
            "The saved account metadata is damaged and could not be loaded."
        case .transactionFailed:
            "The account could not be saved securely."
        }
    }
}
