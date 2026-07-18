# Security Boundaries

AuthMyMac is local-only. Network access, telemetry, remote accounts, and secret synchronization are outside the base product scope.

## Secrets

- `OTPAccount` stores only a Keychain reference.
- Base32 secrets and migration payloads must use `SecretValue` or another explicitly redacted type at module boundaries.
- Secret-bearing types must not conform to `Codable`, `CustomDumpRepresentable`, or interpolation protocols that expose bytes.
- Keychain items use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and are not synchronizable.
- Debug and release builds use separate Keychain services and matching metadata namespaces. The historical namespace belongs to debug builds because `BUILD.sh` defaults to debug.
- Deleting an account deletes its Keychain item as part of the same coordinated operation.

## Logging

`DiagnosticsMetadata` rejects keys associated with secrets, OTP values, URIs, payloads, and account names. Do not bypass it by embedding values in event names. Allowed metadata should be operational and bounded, such as duration, result, count, permission state, or error category.

Never log:

- Base32 secrets
- generated OTP codes
- provisioning or migration URIs
- protobuf payloads
- issuer or account display names

## Permissions

Camera, screen recording, and notification permission requests are user-initiated. Denial is a normal application state. Capture sessions stop immediately after success, cancellation, dismissal, or loss of visibility.

## Export

Exports contain every selected credential and require explicit confirmation. Export screens must not take screenshots for diagnostics, persist migration URIs, or place an export on the clipboard without a direct user action.
