import Domain
import Foundation

public struct ParsedOTPAccount: Equatable, Sendable {
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
        algorithm: OTPAlgorithm,
        digits: OTPDigits,
        period: Int
    ) {
        self.issuer = issuer
        self.accountName = accountName
        self.secret = secret
        self.algorithm = algorithm
        self.digits = digits
        self.period = period
    }
}

public protocol OTPURIParsing: Sendable {
    func parse(_ url: URL) throws -> ParsedOTPAccount
}

public enum QRPayload: Equatable, Sendable {
    case account(ParsedOTPAccount)
    case migration([ParsedOTPAccount])
}

public protocol QRPayloadDecoding: Sendable {
    func decode(_ payload: String) throws -> QRPayload
}

public enum QRPayloadError: Error, Equatable, Sendable {
    case invalidURL
    case unsupportedType
    case malformedPayload
    case duplicateParameter
    case missingSecret
    case invalidIssuer
    case unsupportedAlgorithm
    case unsupportedDigits
    case invalidPeriod
    case issuerMismatch
    case incompleteMigration
    case payloadTooLarge
    case unsupportedMigrationPeriod
}

/// Metadata and accounts carried by one Google Authenticator migration QR code.
public struct MigrationPayloadBatch: Equatable, Sendable {
    public let accounts: [ParsedOTPAccount]
    public let batchSize: Int
    public let batchIndex: Int
    public let batchID: Int

    public init(accounts: [ParsedOTPAccount], batchSize: Int, batchIndex: Int, batchID: Int) {
        self.accounts = accounts
        self.batchSize = batchSize
        self.batchIndex = batchIndex
        self.batchID = batchID
    }
}

/// Stateful reassembly for a sequential scan of a multi-code migration export.
public struct MigrationPayloadReassembler: Sendable {
    private var batches: [Int: MigrationPayloadBatch] = [:]
    private var batchID: Int?
    private var expectedBatchSize: Int?

    public init() {}

    public var receivedBatchCount: Int { batches.count }

    public mutating func append(_ batch: MigrationPayloadBatch) throws -> [ParsedOTPAccount]? {
        guard batch.batchSize > 0, batch.batchIndex >= 0, batch.batchIndex < batch.batchSize else {
            throw QRPayloadError.malformedPayload
        }
        if let batchID, batchID != batch.batchID {
            throw QRPayloadError.malformedPayload
        }
        if let expectedBatchSize, expectedBatchSize != batch.batchSize {
            throw QRPayloadError.malformedPayload
        }

        batchID = batch.batchID
        expectedBatchSize = batch.batchSize
        if let existing = batches[batch.batchIndex], existing != batch {
            throw QRPayloadError.malformedPayload
        }
        batches[batch.batchIndex] = batch

        guard batches.count == batch.batchSize else { return nil }
        let complete = try MigrationPayloadCodec().reassemble(Array(batches.values))
        reset()
        return complete
    }

    public mutating func reset() {
        batches = [:]
        batchID = nil
        expectedBatchSize = nil
    }
}

public protocol MigrationBatchDecoding: Sendable {
    func decodeMigrationBatch(_ payload: String) throws -> MigrationPayloadBatch?
}
