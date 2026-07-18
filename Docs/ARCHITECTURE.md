# Architecture

## Dependency direction

Dependencies point toward stable contracts and never back toward the application target.

```text
App --> Authenticator
         |-- MenuBar ----------> UI ---------+
         |-- OTP ----------------------------|
         |-- Storage ------------------------+--> Domain
         |-- Notifications ------------------|
         |-- CameraCapture --> QR -----------|
         +-- ScreenCapture --> QR -----------+

Diagnostics is standalone.
```

Feature implementations receive a `DiagnosticsRecording` value from the composition root rather than importing concrete logging into domain types.

## Rules

1. `App` assembles scenes and concrete dependencies. It contains no parsing, persistence, cryptography, or capture logic.
2. `Domain` imports Foundation only. It never imports SwiftUI, SwiftData, Security, AVFoundation, ScreenCaptureKit, Vision, or OSLog.
3. Feature targets own their framework adapters and expose small `Sendable` protocols.
4. `UI` renders values and emits user intent through closures. It does not access Keychain, SwiftData, capture sessions, or global singletons.
5. `MenuBar`, camera, and screen capture remain thin delivery mechanisms. Decoded payloads flow through `QR` and persistence flows through `Storage`.
6. Secret bytes use `SecretValue`, which is non-Codable and redacts textual output. `OTPAccount` contains only a Keychain reference.
7. Cross-feature orchestration belongs in a dedicated coordinator inside the owning feature, never in `App` or `Domain`.

## Ownership

- Add RFC 6238 tests and implementation under `Tests/OTPTests` and `Sources/OTP`.
- Add metadata and Keychain adapters under `Tests/StorageTests` and `Sources/Storage`.
- Add URI and protobuf fixtures under `Tests/QRTests/Fixtures` and implementations under `Sources/QR`.
- Add prerecorded image fixtures only to the capture target that consumes them.
- Put reusable visual primitives in `UI`; feature screens stay with the feature unless more than one feature consumes them.
- Keep AppKit bridges private to `ScreenCapture`, `CameraCapture`, or `MenuBar`.
- Keep import, export, timing, and capture-presentation state in `AuthenticatorCoordinator`, with direct tests in `Tests/AuthenticatorTests`.

## Data flow

```text
Camera / selected region
        -> raw QR observation
        -> QRPayloadDecoding
        -> validated ParsedOTPAccount
        -> AuthenticatorCoordinator
        -> duplicate check and transactional AccountStoring batch operation
        -> Keychain secret + SwiftData metadata
        -> UI refresh
        -> success notification
```

No capture target writes storage directly. This keeps prerecorded inputs usable in tests and ensures every import path applies the same validation and duplicate policy.

## Concurrency

- All targets compile in Swift 6 language mode.
- Mutable repositories and import coordination are actors.
- UI state is isolated to `@MainActor` and uses Observation when state is introduced.
- Camera and screen sessions expose async lifecycle methods and must stop after completion or cancellation.
- The application-owned OTP clock drives visible countdowns; account rows do not create timers.

## Application packaging

The Swift package is the development workspace and module source of truth. `BUILD.sh` creates a development bundle and embeds `Configuration/AuthMyMac.entitlements` during ad-hoc signing. When release packaging begins, create a thin Xcode macOS application target that consumes these package products and applies the files in `Configuration/`. Do not duplicate source files in the host target.
