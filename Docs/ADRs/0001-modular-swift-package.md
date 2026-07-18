# ADR 0001: Modular Swift Package Core

- Status: accepted
- Date: 2026-07-17

## Context

The plan spans cryptography, secure persistence, parsing, multiple capture frameworks, menu bar presentation, and SwiftUI. Those areas require different system permissions and test strategies. A single application target would make pure logic depend on framework-heavy code and would encourage integration tests where unit tests should suffice.

## Decision

Use one Swift package with a small executable composition target and library targets aligned with the plan. Keep `Domain` dependency-light, expose feature boundaries as protocols, and put concrete Apple-framework adapters in their owning targets. A future release-only Xcode host target consumes the same products for signing, entitlements, archiving, and UI testing.

## Consequences

- Feature work can proceed independently with target-local tests.
- Cryptography and parsing remain testable without an app bundle or permissions.
- The dependency graph is explicit in `Package.swift`.
- Release packaging requires a thin Xcode host target later.
- Cross-feature orchestration must be deliberately placed rather than emerging through imports.
