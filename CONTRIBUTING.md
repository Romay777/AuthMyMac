# Contributing

1. Choose the target that owns the behavior and add a failing test there.
2. Keep the implementation inside that target. Add a dependency only when data must cross an existing boundary.
3. Use Swift 6 concurrency annotations; do not silence `Sendable` diagnostics with unchecked conformance without documenting the invariant.
4. Keep secrets out of source, fixtures, logs, test names, snapshots, and assertion messages.
5. Run `swift test` and `swift build -c release` before handoff.

Prefer native macOS controls and semantic colors. Use shared values from `UI` rather than local spacing constants. Liquid Glass belongs on interactive chrome and hierarchy-bearing surfaces, not every row or nested container.
