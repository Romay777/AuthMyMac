import Foundation
import Testing
@testable import Domain

@Suite("OTP account metadata")
struct OTPAccountTests {
    @Test("Decodes metadata written before favorites existed")
    func decodesLegacyMetadata() throws {
        let json = """
        {
          "id":"00000000-0000-0000-0000-000000000001",
          "issuer":"Example",
          "accountName":"person@example.com",
          "secretKeychainID":"reference",
          "algorithm":"SHA1",
          "digits":6,
          "period":30,
          "createdAt":0,
          "sortOrder":0
        }
        """

        let account = try JSONDecoder().decode(OTPAccount.self, from: Data(json.utf8))

        #expect(account.isFavorite == false)
    }

    @Test("Round-trips non-sensitive metadata")
    func roundTripsMetadata() throws {
        let account = try OTPAccount(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            issuer: "Example",
            accountName: "person@example.com",
            secretKeychainID: "keychain-reference",
            algorithm: .sha256,
            digits: .eight,
            period: 45,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            sortOrder: 3
        )

        let encoded = try JSONEncoder().encode(account)
        let decoded = try JSONDecoder().decode(OTPAccount.self, from: encoded)

        #expect(decoded == account)
        #expect(!String(decoding: encoded, as: UTF8.self).localizedCaseInsensitiveContains("secret="))
    }

    @Test("Rejects invalid periods", arguments: [0, -1, -30])
    func rejectsInvalidPeriod(_ period: Int) {
        #expect(throws: OTPAccount.ValidationError.invalidPeriod) {
            try OTPAccount(
                issuer: "Example",
                accountName: "person@example.com",
                secretKeychainID: "keychain-reference",
                period: period
            )
        }
    }

    @Test("Rejects an empty keychain reference")
    func rejectsEmptyKeychainReference() {
        #expect(throws: OTPAccount.ValidationError.missingSecretReference) {
            try OTPAccount(
                issuer: "Example",
                accountName: "person@example.com",
                secretKeychainID: "   "
            )
        }
    }
}
