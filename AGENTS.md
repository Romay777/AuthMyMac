# Repository Guidelines

## Project Structure & Module Organization

AuthMyMac is a Swift 6.2 macOS package targeting macOS 26. Production code is
grouped by feature in `Sources/<Target>`; `App` is the composition root and
`Domain` holds dependency-free account types. Keep parsing in `QR`, OTP logic
in `OTP`, persistence in `Storage`, and reusable views and design tokens in
`UI`. Tests mirror targets under `Tests/<Target>Tests`; configuration is in
`Configuration/` and supporting guidance is in `Docs/`.

Respect `Docs/ARCHITECTURE.md`: `App` only wires scenes and dependencies, and
`Domain` must not import UI, platform, or storage frameworks. Put
cross-feature workflows in an owning coordinator, not in `App` or a view.

## Build, Test, and Development Commands

Run these from the repository root:

```sh
swift build                 # Compile the debug package
swift build -c release      # Verify the optimized build
swift test                  # Run the complete Swift Testing suite
swift test --filter OTPTests # Run one target's tests
./BUILD.sh                  # Create and open dist/AuthMyMac.app
OPEN_AFTER_BUILD=0 ./BUILD.sh release # Build an optimized app bundle only
```

`BUILD.sh` ad-hoc signs with `Configuration/AuthMyMac.entitlements` for macOS
privacy prompts.

## Coding Style & Naming Conventions

Use four-space indentation and the surrounding Swift formatting. Name types
in `UpperCamelCase`, members in `lowerCamelCase`, and protocols by capability
(`AccountStoring`, `TOTPGenerating`). Prefer small `Sendable` protocols at
module boundaries. Do not add unchecked `Sendable` conformance without a
documented invariant. Reuse `UI` design-system values and native macOS
controls instead of local constants.

## Testing Guidelines

Start each behavior change with the smallest failing test in its owning target.
Use `Testing` and descriptive `*Tests.swift` files, such as
`OTPAccountTests.swift`. Keep unit tests deterministic: inject clocks, UUIDs,
and captures; use target-local fakes; do not depend on Keychain, permissions,
camera, screen capture, locale, or wall-clock time. Integration tests must
clean up in `defer` and skip with a stated reason when unavailable. Run
`swift test` and `swift build -c release` before handoff.

## Commits, Pull Requests, and Security

History uses short, lowercase summaries, sometimes with a conventional prefix
(for example, `feat: qr scan and screenshots`). Use a concise imperative
subject. Pull requests should describe the change, name test coverage, link an
issue when available, and include screenshots for visual changes.

Never commit provisioning URIs, TOTP secrets, Keychain data, or secrets in
fixtures, logs, snapshots, test names, or assertion text. Follow
`Docs/SECURITY.md` for any security-sensitive change.
