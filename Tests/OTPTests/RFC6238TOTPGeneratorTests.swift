import Domain
import Foundation
import OTP
import Testing

@Suite("RFC 6238 TOTP generation")
struct RFC6238TOTPGeneratorTests {
    @Test("Matches the published SHA1, SHA256, and SHA512 vectors")
    func publishedVectors() async throws {
        let generator = RFC6238TOTPGenerator()
        let vectors: [(OTPAlgorithm, String, String)] = [
            (.sha1, "12345678901234567890", "94287082"),
            (.sha256, "12345678901234567890123456789012", "46119246"),
            (.sha512, "1234567890123456789012345678901234567890123456789012345678901234", "90693936"),
        ]
        for (algorithm, key, expected) in vectors {
            let account = try OTPAccount(
                issuer: "RFC",
                accountName: "vector",
                secretKeychainID: "test",
                algorithm: algorithm,
                digits: .eight
            )
            let code = try await generator.code(
                for: SecretValue(Data(key.utf8)),
                account: account,
                at: Date(timeIntervalSince1970: 59)
            )
            #expect(code == expected)
        }
    }

    @Test("Base32 accepts lowercase separators and rejects invalid characters")
    func base32Normalization() throws {
        let secret = try Base32.decode("jbsw-y3dp ehpk3pxp")
        #expect(Base32.encode(secret) == "JBSWY3DPEHPK3PXP")
        #expect(throws: Base32Error.invalidCharacter) { try Base32.decode("JBSW!3DP") }
    }

    @Test("Base32 errors provide actionable descriptions")
    func base32ErrorDescriptions() {
        #expect(Base32Error.empty.errorDescription == "Enter a Base32 secret.")
        #expect(Base32Error.invalidCharacter.errorDescription?.contains("valid Base32") == true)
        #expect(Base32Error.invalidPadding.errorDescription?.contains("padding") == true)
    }

    @Test("Validation permits one configured time step of clock skew")
    func skewValidation() async throws {
        let generator = RFC6238TOTPGenerator()
        let account = try OTPAccount(issuer: "Example", accountName: "user", secretKeychainID: "test")
        let secret = try Base32.decode("JBSWY3DPEHPK3PXP")
        let at = Date(timeIntervalSince1970: 1_700_000_000)
        let code = try await generator.code(for: secret, account: account, at: at.addingTimeInterval(-30))
        #expect(try await generator.validates(code, secret: secret, account: account, at: at))
    }
}
