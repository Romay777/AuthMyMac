import Domain
import Foundation
import OTP

/// A minimal, wire-compatible codec for Google Authenticator's migration protobuf.
/// Keeping it local avoids accepting an arbitrary protobuf schema at this trust boundary.
public struct MigrationPayloadCodec: Sendable {
    /// A conservative byte budget that Core Image can render reliably at QR error correction level M.
    public static let defaultMaximumURILength = 1_200

    public init() {}

    public func decode(_ url: URL) throws -> [ParsedOTPAccount] {
        try decodeBatch(url).accounts
    }

    public func decodeBatch(_ url: URL) throws -> MigrationPayloadBatch {
        guard url.scheme?.lowercased() == "otpauth-migration", url.host?.lowercased() == "offline",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            throw QRPayloadError.malformedPayload
        }
        let queryItems = components.queryItems ?? []
        var queryNames = Set<String>()
        guard queryItems.allSatisfy({ queryNames.insert($0.name).inserted }) else {
            throw QRPayloadError.duplicateParameter
        }
        let dataParameters = queryItems.filter { $0.name == "data" }
        guard dataParameters.count == 1,
              let value = dataParameters[0].value,
              let data = Data(base64Encoded: value) ?? Data(base64URLEncoded: value)
        else {
            throw QRPayloadError.malformedPayload
        }

        var reader = ProtobufReader(data: data)
        var accounts: [ParsedOTPAccount] = []
        var version: UInt64?
        var batchSize: Int?
        var batchIndex: Int?
        var batchID: Int?
        while let field = try reader.nextField() {
            switch (field.number, field.value) {
            case (1, let .bytes(bytes)):
                accounts.append(try decodeAccount(bytes))
            case (2, let .varint(value)):
                guard version == nil else { throw QRPayloadError.malformedPayload }
                version = value
            case (3, let .varint(value)):
                guard batchSize == nil, let converted = Int(exactly: value) else {
                    throw QRPayloadError.malformedPayload
                }
                batchSize = converted
            case (4, let .varint(value)):
                guard batchIndex == nil, let converted = Int(exactly: value) else {
                    throw QRPayloadError.malformedPayload
                }
                batchIndex = converted
            case (5, let .varint(value)):
                guard batchID == nil, let converted = signedInt32(from: value) else {
                    throw QRPayloadError.malformedPayload
                }
                batchID = converted
            default:
                continue
            }
        }
        guard !accounts.isEmpty,
              version == 1 || version == 2,
              let batchSize,
              let batchIndex,
              batchSize > 0,
              batchIndex >= 0,
              batchIndex < batchSize
        else {
            throw QRPayloadError.malformedPayload
        }
        guard version == 2 || batchID != nil else {
            throw QRPayloadError.malformedPayload
        }
        return MigrationPayloadBatch(
            accounts: accounts,
            batchSize: batchSize,
            batchIndex: batchIndex,
            batchID: batchID ?? 0
        )
    }

    public func encode(
        _ accounts: [ParsedOTPAccount],
        batchSize: Int? = nil,
        batchIndex: Int = 0,
        batchID: Int = Int.random(in: 1...Int(Int32.max))
    ) throws -> URL {
        guard !accounts.isEmpty else { throw QRPayloadError.malformedPayload }
        guard accounts.allSatisfy({ $0.period == 30 }) else {
            throw QRPayloadError.unsupportedMigrationPeriod
        }
        let size = batchSize ?? accounts.count
        guard size > 0, batchIndex >= 0, batchIndex < size,
              Int32(exactly: batchID) != nil
        else {
            throw QRPayloadError.malformedPayload
        }

        var data = Data()
        for account in accounts {
            let encodedAccount = try encodeAccount(account)
            ProtobufWriter.appendLengthDelimited(field: 1, value: encodedAccount, to: &data)
        }
        ProtobufWriter.appendVarint(field: 2, value: 1, to: &data)
        ProtobufWriter.appendVarint(field: 3, value: UInt64(size), to: &data)
        ProtobufWriter.appendVarint(field: 4, value: UInt64(batchIndex), to: &data)
        ProtobufWriter.appendVarint(
            field: 5,
            value: UInt64(bitPattern: Int64(batchID)),
            to: &data
        )

        var components = URLComponents()
        components.scheme = "otpauth-migration"
        components.host = "offline"
        components.queryItems = [URLQueryItem(name: "data", value: data.base64EncodedString())]
        guard let url = components.url else { throw QRPayloadError.malformedPayload }
        return url
    }

    /// Greedily partitions an export so every migration URI fits within the requested QR payload budget.
    public func encodeBatches(
        _ accounts: [ParsedOTPAccount],
        maximumURILength: Int = Self.defaultMaximumURILength,
        batchID: Int = Int.random(in: 1...Int(Int32.max))
    ) throws -> [URL] {
        guard !accounts.isEmpty, maximumURILength > 0, Int32(exactly: batchID) != nil else {
            throw QRPayloadError.malformedPayload
        }

        var groups: [[ParsedOTPAccount]] = []
        for account in accounts {
            if var current = groups.popLast() {
                let candidate = current + [account]
                let candidateURL = try encode(
                    candidate,
                    batchSize: accounts.count,
                    batchIndex: groups.count,
                    batchID: batchID
                )
                if uriLength(candidateURL) <= maximumURILength {
                    current.append(account)
                    groups.append(current)
                    continue
                }
                groups.append(current)
            }

            let singleURL = try encode(
                [account],
                batchSize: accounts.count,
                batchIndex: groups.count,
                batchID: batchID
            )
            guard uriLength(singleURL) <= maximumURILength else {
                throw QRPayloadError.payloadTooLarge
            }
            groups.append([account])
        }

        let batchSize = groups.count
        let urls = try groups.enumerated().map { index, group in
            try encode(group, batchSize: batchSize, batchIndex: index, batchID: batchID)
        }
        guard urls.allSatisfy({ uriLength($0) <= maximumURILength }) else {
            throw QRPayloadError.payloadTooLarge
        }
        return urls
    }

    public func reassemble(_ batches: [MigrationPayloadBatch]) throws -> [ParsedOTPAccount] {
        guard let first = batches.first, batches.count == first.batchSize else {
            throw QRPayloadError.incompleteMigration
        }
        guard batches.allSatisfy({ $0.batchSize == first.batchSize && $0.batchID == first.batchID }) else {
            throw QRPayloadError.malformedPayload
        }
        let sorted = batches.sorted { $0.batchIndex < $1.batchIndex }
        guard sorted.enumerated().allSatisfy({ $0.offset == $0.element.batchIndex }) else {
            throw QRPayloadError.incompleteMigration
        }
        return sorted.flatMap(\.accounts)
    }

    private func uriLength(_ url: URL) -> Int {
        url.absoluteString.lengthOfBytes(using: .utf8)
    }

    private func signedInt32(from value: UInt64) -> Int? {
        let signed = Int64(bitPattern: value)
        guard let converted = Int32(exactly: signed) else { return nil }
        return Int(converted)
    }

    private func decodeAccount(_ data: Data) throws -> ParsedOTPAccount {
        var reader = ProtobufReader(data: data)
        var secret: Data?
        var name: String?
        var issuer: String?
        var algorithm = OTPAlgorithm.sha1
        var digits = OTPDigits.six
        var type: UInt64 = 0

        while let field = try reader.nextField() {
            switch (field.number, field.value) {
            case (1, let .bytes(value)): secret = value
            case (2, let .bytes(value)): name = String(data: value, encoding: .utf8)
            case (3, let .bytes(value)): issuer = String(data: value, encoding: .utf8)
            case (4, let .varint(value)):
                switch value {
                case 1: algorithm = .sha1
                case 2: algorithm = .sha256
                case 3: algorithm = .sha512
                default: throw QRPayloadError.unsupportedAlgorithm
                }
            case (5, let .varint(value)):
                switch value {
                case 1: digits = .six
                case 2: digits = .eight
                default: throw QRPayloadError.unsupportedDigits
                }
            case (6, let .varint(value)): type = value
            default: continue
            }
        }

        guard type == 2, let secret, !secret.isEmpty,
              let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty
        else {
            throw QRPayloadError.malformedPayload
        }
        let normalizedIssuer = issuer?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedIssuer = normalizedIssuer.flatMap { $0.isEmpty ? nil : $0 } ?? "Other"
        return ParsedOTPAccount(
            issuer: resolvedIssuer,
            accountName: name,
            secret: SecretValue(secret),
            algorithm: algorithm,
            digits: digits,
            period: 30
        )
    }

    private func encodeAccount(_ account: ParsedOTPAccount) throws -> Data {
        guard !account.secret.data().isEmpty, !account.issuer.isEmpty, !account.accountName.isEmpty else {
            throw QRPayloadError.malformedPayload
        }
        var data = Data()
        ProtobufWriter.appendLengthDelimited(field: 1, value: account.secret.data(), to: &data)
        ProtobufWriter.appendLengthDelimited(field: 2, value: Data(account.accountName.utf8), to: &data)
        ProtobufWriter.appendLengthDelimited(field: 3, value: Data(account.issuer.utf8), to: &data)
        ProtobufWriter.appendVarint(field: 4, value: algorithmValue(account.algorithm), to: &data)
        ProtobufWriter.appendVarint(field: 5, value: account.digits == .six ? 1 : 2, to: &data)
        ProtobufWriter.appendVarint(field: 6, value: 2, to: &data)
        return data
    }

    private func algorithmValue(_ algorithm: OTPAlgorithm) -> UInt64 {
        switch algorithm {
        case .sha1: 1
        case .sha256: 2
        case .sha512: 3
        }
    }
}

private enum ProtobufValue {
    case varint(UInt64)
    case bytes(Data)
}

private struct ProtobufField {
    let number: UInt64
    let value: ProtobufValue
}

private struct ProtobufReader {
    private let data: Data
    private var offset = 0

    init(data: Data) { self.data = data }

    mutating func nextField() throws -> ProtobufField? {
        guard offset < data.count else { return nil }
        let key = try readVarint()
        let number = key >> 3
        guard number > 0 else { throw QRPayloadError.malformedPayload }
        switch key & 7 {
        case 0: return ProtobufField(number: number, value: .varint(try readVarint()))
        case 2:
            let length = try readVarint()
            guard length <= UInt64(data.count - offset) else { throw QRPayloadError.malformedPayload }
            let end = offset + Int(length)
            defer { offset = end }
            return ProtobufField(number: number, value: .bytes(Data(data[offset..<end])))
        case 1:
            try skip(8)
        case 5:
            try skip(4)
        default:
            throw QRPayloadError.malformedPayload
        }
        return try nextField()
    }

    private mutating func readVarint() throws -> UInt64 {
        var result: UInt64 = 0
        for index in 0..<10 {
            guard offset < data.count else { throw QRPayloadError.malformedPayload }
            let byte = data[offset]
            offset += 1
            result |= UInt64(byte & 0x7f) << UInt64(index * 7)
            if byte & 0x80 == 0 { return result }
        }
        throw QRPayloadError.malformedPayload
    }

    private mutating func skip(_ count: Int) throws {
        guard count <= data.count - offset else { throw QRPayloadError.malformedPayload }
        offset += count
    }
}

private enum ProtobufWriter {
    static func appendVarint(field: UInt64, value: UInt64, to data: inout Data) {
        append(value: field << 3, to: &data)
        append(value: value, to: &data)
    }

    static func appendLengthDelimited(field: UInt64, value: Data, to data: inout Data) {
        append(value: (field << 3) | 2, to: &data)
        append(value: UInt64(value.count), to: &data)
        data.append(value)
    }

    private static func append(value: UInt64, to data: inout Data) {
        var remaining = value
        repeat {
            var byte = UInt8(remaining & 0x7f)
            remaining >>= 7
            if remaining != 0 { byte |= 0x80 }
            data.append(byte)
        } while remaining != 0
    }
}

private extension Data {
    init?(base64URLEncoded value: String) {
        let standard = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padded = standard + String(repeating: "=", count: (4 - standard.count % 4) % 4)
        self.init(base64Encoded: padded)
    }
}
