import Foundation
import Testing
@testable import Domain

@Suite("Secret value")
struct SecretValueTests {
    @Test("Never exposes bytes through descriptions")
    func redactsDescriptions() {
        let secret = SecretValue(Data("sensitive-value".utf8))

        #expect(secret.description == "<redacted>")
        #expect(secret.debugDescription == "<redacted>")
        #expect(!String(reflecting: secret).contains("sensitive-value"))
    }

    @Test("Provides bytes only through an explicit accessor")
    func explicitAccess() {
        let expected = Data([1, 2, 3, 4])
        let secret = SecretValue(expected)

        #expect(secret.data() == expected)
    }
}
