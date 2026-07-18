import Domain
import Foundation
import QR
import Testing

@Suite("otpauth URI parsing")
struct OTPURIParserTests {
    @Test("Parses percent-encoded labels and normalizes secrets")
    func parsesProvisioningURI() throws {
        let url = try #require(URL(string: "otpauth://totp/Example%20Inc%3Aperson%40example.com?secret=jbsw-y3dp&issuer=Example%20Inc&algorithm=SHA256&digits=8&period=45"))
        let account = try OTPURIParser().parse(url)
        #expect(account.issuer == "Example Inc")
        #expect(account.accountName == "person@example.com")
        #expect(account.algorithm.rawValue == "SHA256")
        #expect(account.digits.rawValue == 8)
        #expect(account.period == 45)
    }

    @Test("Uses the manual-entry fallback when a provisioning URI omits its issuer")
    func parsesProvisioningURIWithoutIssuer() throws {
        let url = try #require(URL(string: "otpauth://totp/person%40example.com?secret=JBSWY3DP"))

        let account = try OTPURIParser().parse(url)

        #expect(account.issuer == "Other")
        #expect(account.accountName == "person@example.com")
    }

    @Test("Rejects issuer mismatches and HOTP")
    func rejectsInvalidURIs() throws {
        let mismatch = try #require(URL(string: "otpauth://totp/One:user?secret=JBSWY3DP&issuer=Two"))
        #expect(throws: QRPayloadError.issuerMismatch) { try OTPURIParser().parse(mismatch) }
        let hotp = try #require(URL(string: "otpauth://hotp/Example:user?secret=JBSWY3DP&issuer=Example"))
        #expect(throws: QRPayloadError.unsupportedType) { try OTPURIParser().parse(hotp) }
    }

    @Test("Rejects duplicate query parameters")
    func rejectsDuplicateParameters() throws {
        let uri = try #require(URL(string: "otpauth://totp/Example:user?secret=JBSWY3DP&secret=KRUGS4ZANFZSAYJA&issuer=Example"))
        #expect(throws: QRPayloadError.duplicateParameter) { try OTPURIParser().parse(uri) }
    }

    @Test("Round-trips migration payloads without exposing a provisioning URI")
    func migrationRoundTrip() throws {
        let single = try OTPURIParser().parse(#require(URL(string: "otpauth://totp/Example:user?secret=JBSWY3DP&issuer=Example")))
        let codec = MigrationPayloadCodec()
        let url = try codec.encode([single], batchID: 42)
        let decoded = try codec.decode(url)
        #expect(decoded == [single])
    }

    @Test("Decodes a version 2 Google migration record without issuer or batch ID")
    func decodesVersionTwoGoogleMigration() throws {
        let accountBytes = Data([
            0x0a, 0x04, 0x01, 0x02, 0x03, 0x04,
            0x12, 0x12,
        ]) + Data("person@example.com".utf8) + Data([
            0x20, 0x01,
            0x28, 0x01,
            0x30, 0x02,
        ])
        let migrationBytes = Data([0x0a, UInt8(accountBytes.count)]) + accountBytes + Data([
            0x10, 0x02,
            0x18, 0x02,
            0x20, 0x00,
        ])
        var components = URLComponents()
        components.scheme = "otpauth-migration"
        components.host = "offline"
        components.queryItems = [
            URLQueryItem(name: "data", value: migrationBytes.base64EncodedString()),
        ]

        let decoder = QRPayloadDecoder()
        let uri = try #require(components.string)
        let decodedBatch = try decoder.decodeMigrationBatch(uri)
        let batch = try #require(decodedBatch)
        let account = try #require(batch.accounts.first)
        var reassembler = MigrationPayloadReassembler()
        #expect(batch.accounts.count == 1)
        #expect(batch.batchSize == 2)
        #expect(batch.batchIndex == 0)
        #expect(batch.batchID == 0)
        #expect(try reassembler.append(batch) == nil)
        #expect(account.issuer == "Other")
        #expect(account.accountName == "person@example.com")
        #expect(account.algorithm == .sha1)
        #expect(account.digits == .six)
        #expect(account.period == 30)
    }

    @Test("Accepts a zero migration batch identifier")
    func acceptsZeroMigrationBatchID() throws {
        let account = ParsedOTPAccount(
            issuer: "Example",
            accountName: "person@example.com",
            secret: SecretValue(Data([1, 2, 3, 4])),
            algorithm: .sha1,
            digits: .six,
            period: 30
        )
        let url = try MigrationPayloadCodec().encode([account], batchID: 0)
        let batch = try MigrationPayloadCodec().decodeBatch(url)
        #expect(batch.batchID == 0)
    }

    @Test("Decodes signed Google migration batch identifiers")
    func acceptsNegativeMigrationBatchID() throws {
        let account = ParsedOTPAccount(
            issuer: "Example",
            accountName: "person@example.com",
            secret: SecretValue(Data([1, 2, 3, 4])),
            algorithm: .sha1,
            digits: .six,
            period: 30
        )
        let url = try MigrationPayloadCodec().encode([account], batchID: -42)
        let batch = try MigrationPayloadCodec().decodeBatch(url)
        #expect(batch.batchID == -42)
    }

    @Test("Splits migration exports within the QR payload budget and reassembles them")
    func migrationBatchesRoundTrip() throws {
        let accounts = (0..<5).map { index in
            ParsedOTPAccount(
                issuer: "Example \(index)",
                accountName: "person-\(index)@example.com",
                secret: SecretValue(Data(repeating: UInt8(index + 1), count: 32)),
                algorithm: .sha1,
                digits: .six,
                period: 30
            )
        }
        let codec = MigrationPayloadCodec()
        let urls = try codec.encodeBatches(accounts, maximumURILength: 250, batchID: 42)
        let batches = try urls.map(codec.decodeBatch)

        #expect(urls.count > 1)
        #expect(urls.allSatisfy { $0.absoluteString.lengthOfBytes(using: String.Encoding.utf8) <= 250 })
        #expect(try codec.reassemble(batches) == accounts)
        #expect(throws: QRPayloadError.incompleteMigration) {
            try codec.reassemble(Array(batches.dropFirst()))
        }
    }

    @Test("Rejects migration exports that would change a custom TOTP period")
    func rejectsCustomPeriodMigrationExport() throws {
        let account = ParsedOTPAccount(
            issuer: "Example",
            accountName: "person@example.com",
            secret: SecretValue(Data("secret".utf8)),
            algorithm: .sha1,
            digits: .six,
            period: 45
        )

        #expect(throws: QRPayloadError.unsupportedMigrationPeriod) {
            try MigrationPayloadCodec().encode([account], batchID: 42)
        }
    }

    @Test("Reports one account that cannot fit in the QR payload budget")
    func rejectsOversizedMigrationAccount() throws {
        let account = ParsedOTPAccount(
            issuer: "Example",
            accountName: "person@example.com",
            secret: SecretValue(Data(repeating: 0x01, count: 64)),
            algorithm: .sha1,
            digits: .six,
            period: 30
        )
        #expect(throws: QRPayloadError.payloadTooLarge) {
            try MigrationPayloadCodec().encodeBatches([account], maximumURILength: 40, batchID: 42)
        }
    }
}
