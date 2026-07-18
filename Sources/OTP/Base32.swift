import Domain
import Foundation

public enum Base32Error: LocalizedError, Equatable, Sendable {
    case empty
    case invalidCharacter
    case invalidPadding

    public var errorDescription: String? {
        switch self {
        case .empty:
            "Enter a Base32 secret."
        case .invalidCharacter:
            "The secret contains characters that are not valid Base32."
        case .invalidPadding:
            "The secret has invalid Base32 padding."
        }
    }
}

/// RFC 4648 Base32 support for authenticator secrets.
public enum Base32 {
    public static func decode(_ value: String) throws -> SecretValue {
        let normalized = try normalized(value)
        var output = Data()
        var buffer = 0
        var bitsInBuffer = 0

        for scalar in normalized.unicodeScalars where scalar.value != 61 {
            let value = try decodedValue(for: scalar)
            buffer = (buffer << 5) | value
            bitsInBuffer += 5

            while bitsInBuffer >= 8 {
                bitsInBuffer -= 8
                output.append(UInt8((buffer >> bitsInBuffer) & 0xff))
            }
            buffer &= (1 << bitsInBuffer) - 1
        }

        guard bitsInBuffer == 0 || (buffer & ((1 << bitsInBuffer) - 1)) == 0 else {
            throw Base32Error.invalidPadding
        }
        return SecretValue(output)
    }

    public static func normalized(_ value: String) throws -> String {
        let compact = value.uppercased().filter { !$0.isWhitespace && $0 != "-" }
        guard !compact.isEmpty else { throw Base32Error.empty }

        let paddingStart = compact.firstIndex(of: "=")
        if let paddingStart {
            guard compact[paddingStart...].allSatisfy({ $0 == "=" }) else {
                throw Base32Error.invalidPadding
            }
            let unpaddedCount = compact.distance(from: compact.startIndex, to: paddingStart)
            guard unpaddedCount % 8 != 1, compact.count % 8 == 0 else {
                throw Base32Error.invalidPadding
            }
        } else if compact.count % 8 == 1 {
            throw Base32Error.invalidPadding
        }

        for scalar in compact.unicodeScalars where scalar.value != 61 {
            _ = try decodedValue(for: scalar)
        }
        return compact
    }

    public static func encode(_ secret: SecretValue) -> String {
        var output = ""
        var buffer = 0
        var bitsInBuffer = 0
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

        for byte in secret.data() {
            buffer = (buffer << 8) | Int(byte)
            bitsInBuffer += 8
            while bitsInBuffer >= 5 {
                bitsInBuffer -= 5
                output.append(alphabet[(buffer >> bitsInBuffer) & 31])
            }
            buffer &= (1 << bitsInBuffer) - 1
        }
        if bitsInBuffer > 0 {
            output.append(alphabet[(buffer << (5 - bitsInBuffer)) & 31])
        }
        return output
    }

    private static func decodedValue(for scalar: UnicodeScalar) throws -> Int {
        switch scalar.value {
        case 65...90: return Int(scalar.value - 65)
        case 50...55: return Int(scalar.value - 24)
        default: throw Base32Error.invalidCharacter
        }
    }
}
