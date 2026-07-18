import Foundation

public enum OTPAlgorithm: String, Codable, CaseIterable, Sendable {
    case sha1 = "SHA1"
    case sha256 = "SHA256"
    case sha512 = "SHA512"
}

public enum OTPDigits: Int, Codable, CaseIterable, Sendable {
    case six = 6
    case eight = 8
}

/// Non-sensitive account metadata. Secret material never belongs in this type.
public struct OTPAccount: Identifiable, Codable, Hashable, Sendable {
    public enum ValidationError: Error, Equatable, Sendable {
        case invalidPeriod
        case missingSecretReference
        case missingIssuer
        case missingAccountName
    }

    public let id: UUID
    public let issuer: String
    public let accountName: String
    public let secretKeychainID: String
    public let algorithm: OTPAlgorithm
    public let digits: OTPDigits
    public let period: Int
    public let createdAt: Date
    public let sortOrder: Int
    public let isFavorite: Bool

    public init(
        id: UUID = UUID(),
        issuer: String,
        accountName: String,
        secretKeychainID: String,
        algorithm: OTPAlgorithm = .sha1,
        digits: OTPDigits = .six,
        period: Int = 30,
        createdAt: Date = Date(),
        sortOrder: Int = 0,
        isFavorite: Bool = false
    ) throws {
        guard period > 0 else {
            throw ValidationError.invalidPeriod
        }

        let normalizedReference = secretKeychainID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedReference.isEmpty else {
            throw ValidationError.missingSecretReference
        }

        let normalizedIssuer = issuer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedIssuer.isEmpty else { throw ValidationError.missingIssuer }
        let normalizedAccountName = accountName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedAccountName.isEmpty else { throw ValidationError.missingAccountName }

        self.id = id
        self.issuer = normalizedIssuer
        self.accountName = normalizedAccountName
        self.secretKeychainID = normalizedReference
        self.algorithm = algorithm
        self.digits = digits
        self.period = period
        self.createdAt = createdAt
        self.sortOrder = sortOrder
        self.isFavorite = isFavorite
    }

    private enum CodingKeys: String, CodingKey {
        case id, issuer, accountName, secretKeychainID, algorithm, digits, period, createdAt, sortOrder, isFavorite
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(UUID.self, forKey: .id),
            issuer: container.decode(String.self, forKey: .issuer),
            accountName: container.decode(String.self, forKey: .accountName),
            secretKeychainID: container.decode(String.self, forKey: .secretKeychainID),
            algorithm: container.decode(OTPAlgorithm.self, forKey: .algorithm),
            digits: container.decode(OTPDigits.self, forKey: .digits),
            period: container.decode(Int.self, forKey: .period),
            createdAt: container.decode(Date.self, forKey: .createdAt),
            sortOrder: container.decode(Int.self, forKey: .sortOrder),
            isFavorite: container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        )
    }
}
