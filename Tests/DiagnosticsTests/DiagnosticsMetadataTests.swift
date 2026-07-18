import Testing
@testable import Diagnostics

@Suite("Diagnostics privacy")
struct DiagnosticsMetadataTests {
    @Test("Accepts allow-listed operational metadata")
    func acceptsOperationalMetadata() throws {
        let metadata = try DiagnosticsMetadata([
            "duration_ms": "42",
            "result": "success",
        ])

        #expect(metadata.values["duration_ms"] == "42")
        #expect(metadata.values["result"] == "success")
    }

    @Test(
        "Rejects sensitive metadata keys",
        arguments: ["secret", "otp_code", "provisioning_uri", "migration_payload", "account_name"]
    )
    func rejectsSensitiveKey(_ key: String) {
        #expect(throws: DiagnosticsMetadata.ValidationError.sensitiveKey(key)) {
            try DiagnosticsMetadata([key: "must-not-be-logged"])
        }
    }
}
