# Testing

AuthMyMac follows red-green-refactor. Every behavior change starts with the smallest failing test in the target that owns the behavior.

## Local loop

```sh
swift test
swift test --filter DomainTests
swift test --filter ArchitectureTests
```

Use deterministic clocks, UUIDs, capture inputs, and in-memory fakes. Tests must not depend on the user's Keychain, camera, screen, notification settings, locale, or wall clock unless they are explicitly integration tests.

## Test layers

| Layer | Location | Purpose |
| --- | --- | --- |
| Contract/unit | `Tests/<Target>Tests` | Pure algorithms, validation, state transitions, protocol adapters |
| Architecture | `Tests/ArchitectureTests` | Every planned module imports and exposes its public boundary |
| Integration | Target-specific integration suite | Keychain, SwiftData, Vision, ScreenCaptureKit, and AVFoundation adapters |
| UI | Future Xcode UI-test target | Scene behavior, permissions, keyboard, accessibility, and appearances |

Integration tests that touch system services must use unique identifiers, clean up in `defer`, and skip with a stated reason when the required service is unavailable. Unit suites may never request permissions.

## Feature test order

1. OTP: RFC 6238 vectors, Base32 normalization, algorithms, digits, periods, and skew.
2. QR: URI validation, percent encoding, issuer resolution, migration fixtures, and batching.
3. Storage: Keychain CRUD, SwiftData mapping, duplicate behavior, rollback, and deletion.
4. Capture: authorization-state mapping, cancellation, lifecycle, and prerecorded QR inputs.
5. Import/export: end-to-end round trips with fixed fixtures.
6. UI: empty, loading, populated, denied, error, duplicate, and export-confirmation states.

## Test doubles

Prefer small target-local actors or structs that conform to public protocols. Avoid a shared mocking framework: compile-time protocol conformance is clearer, concurrency-safe fakes are easy to audit, and each suite should expose only the behavior it needs.

## Definition of green

- `swift test` passes.
- `swift build -c release` passes.
- New public contracts have direct tests.
- Security-sensitive failure paths are tested without putting real secrets or provisioning URIs in failure messages.
