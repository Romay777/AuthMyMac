import Domain
import Foundation
import OTP

public struct OTPURIParser: OTPURIParsing {
    public init() {}

    public func parse(_ url: URL) throws -> ParsedOTPAccount {
        guard url.scheme?.lowercased() == "otpauth", url.host?.lowercased() == "totp" else {
            throw QRPayloadError.unsupportedType
        }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw QRPayloadError.invalidURL
        }
        var values: [String: String] = [:]
        for item in components.queryItems ?? [] {
            let name = item.name.lowercased()
            guard values[name] == nil else { throw QRPayloadError.duplicateParameter }
            values[name] = item.value ?? ""
        }
        guard let encodedSecret = values["secret"], !encodedSecret.isEmpty else {
            throw QRPayloadError.missingSecret
        }
        let secret: SecretValue
        do {
            secret = try Base32.decode(encodedSecret)
        } catch {
            throw QRPayloadError.malformedPayload
        }

        let label = try decodedLabel(from: components)
        let labelParts = label.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let labelIssuer = labelParts.count == 2 ? String(labelParts[0]).trimmingCharacters(in: .whitespacesAndNewlines) : nil
        let accountName = (labelParts.count == 2 ? String(labelParts[1]) : label)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let parameterIssuer = values["issuer"]?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !accountName.isEmpty else { throw QRPayloadError.malformedPayload }
        if let labelIssuer, labelIssuer.isEmpty { throw QRPayloadError.invalidIssuer }
        if let labelIssuer, let parameterIssuer, !parameterIssuer.isEmpty,
           labelIssuer.caseInsensitiveCompare(parameterIssuer) != .orderedSame {
            throw QRPayloadError.issuerMismatch
        }
        let issuer = (parameterIssuer?.isEmpty == false ? parameterIssuer : labelIssuer) ?? "Other"

        let algorithm: OTPAlgorithm
        switch values["algorithm"]?.uppercased() ?? "SHA1" {
        case "SHA1": algorithm = .sha1
        case "SHA256": algorithm = .sha256
        case "SHA512": algorithm = .sha512
        default: throw QRPayloadError.unsupportedAlgorithm
        }
        let digits: OTPDigits
        switch values["digits"] ?? "6" {
        case "6": digits = .six
        case "8": digits = .eight
        default: throw QRPayloadError.unsupportedDigits
        }
        let period: Int
        if let specifiedPeriod = values["period"] {
            guard let parsed = Int(specifiedPeriod), parsed > 0 else { throw QRPayloadError.invalidPeriod }
            period = parsed
        } else {
            period = 30
        }

        return ParsedOTPAccount(
            issuer: issuer,
            accountName: accountName,
            secret: secret,
            algorithm: algorithm,
            digits: digits,
            period: period
        )
    }

    private func decodedLabel(from components: URLComponents) throws -> String {
        let path = components.percentEncodedPath.drop(while: { $0 == "/" })
        guard let label = String(path).removingPercentEncoding, !label.isEmpty else {
            throw QRPayloadError.malformedPayload
        }
        return label
    }
}

public struct QRPayloadDecoder: QRPayloadDecoding, MigrationBatchDecoding {
    private let otpURIParser: OTPURIParser

    public init(otpURIParser: OTPURIParser = OTPURIParser()) {
        self.otpURIParser = otpURIParser
    }

    public func decode(_ payload: String) throws -> QRPayload {
        guard let url = URL(string: payload) else { throw QRPayloadError.invalidURL }
        switch url.scheme?.lowercased() {
        case "otpauth":
            return .account(try otpURIParser.parse(url))
        case "otpauth-migration":
            let batch = try MigrationPayloadCodec().decodeBatch(url)
            guard batch.batchSize == 1 else { throw QRPayloadError.incompleteMigration }
            return .migration(batch.accounts)
        default:
            throw QRPayloadError.unsupportedType
        }
    }

    public func decodeMigrationBatch(_ payload: String) throws -> MigrationPayloadBatch? {
        guard let url = URL(string: payload), url.scheme?.lowercased() == "otpauth-migration" else {
            return nil
        }
        return try MigrationPayloadCodec().decodeBatch(url)
    }
}
