import CryptoKit
import Domain
import Foundation

public struct RFC6238TOTPGenerator: TOTPGenerating {
    public init() {}

    public func code(for secret: SecretValue, account: OTPAccount, at date: Date) async throws -> String {
        guard !secret.data().isEmpty, account.period > 0 else {
            throw TOTPGenerationError.invalidSecret
        }

        let seconds = date.timeIntervalSince1970
        guard seconds >= 0 else { throw TOTPGenerationError.unsupportedConfiguration }
        let counter = UInt64(seconds / Double(account.period))
        var counterBigEndian = counter.bigEndian
        let message = withUnsafeBytes(of: &counterBigEndian) { Data($0) }
        let key = SymmetricKey(data: secret.data())
        let digest: Data

        switch account.algorithm {
        case .sha1:
            digest = Data(HMAC<Insecure.SHA1>.authenticationCode(for: message, using: key))
        case .sha256:
            digest = Data(HMAC<SHA256>.authenticationCode(for: message, using: key))
        case .sha512:
            digest = Data(HMAC<SHA512>.authenticationCode(for: message, using: key))
        }

        let offset = Int(digest.last! & 0x0f)
        guard offset + 4 <= digest.count else { throw TOTPGenerationError.unsupportedConfiguration }
        let binary = (UInt32(digest[offset] & 0x7f) << 24)
            | (UInt32(digest[offset + 1]) << 16)
            | (UInt32(digest[offset + 2]) << 8)
            | UInt32(digest[offset + 3])
        let modulus = UInt32(pow(10.0, Double(account.digits.rawValue)))
        return String(format: "%0*u", account.digits.rawValue, binary % modulus)
    }

    public func validates(
        _ code: String,
        secret: SecretValue,
        account: OTPAccount,
        at date: Date,
        allowedTimeSteps: Int = 1
    ) async throws -> Bool {
        guard allowedTimeSteps >= 0 else { return false }
        for step in -allowedTimeSteps...allowedTimeSteps {
            let candidateDate = date.addingTimeInterval(Double(step * account.period))
            if try await self.code(for: secret, account: account, at: candidateDate) == code {
                return true
            }
        }
        return false
    }
}
