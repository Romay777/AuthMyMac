# AuthMyMac Reference Redesign Plan

## Objective

Redesign AuthMyMac to match the user-provided macOS authenticator reference as
closely as possible while preserving the existing product name, native macOS
behavior, module boundaries, and security model.

The reference depicts three application states:

1. A persistent desktop vault window with a translucent sidebar and account
   cards.
2. A QR camera-scanning sheet.
3. A manual account-entry sheet.

The two sheets are alternate states. They must not be presented simultaneously
in the production application. The wallpaper, Dock, and overall desktop staging
in the reference are not part of the app implementation.

## Required Reading

Before editing code, read:

- `AGENTS.md`
- `Docs/ARCHITECTURE.md`
- `Docs/SECURITY.md`
- `Docs/TESTING.md`
- `Sources/UI/AuthenticatorRootView.swift`
- `Sources/Authenticator/AuthenticatorFeature.swift`
- `Sources/App/AuthMyMacApp.swift`

The package targets macOS 26 and Swift 6.2. Use native SwiftUI and macOS 26
Liquid Glass APIs. Do not introduce AppKit bridges unless a required behavior
cannot be implemented in SwiftUI; the existing camera preview bridge remains
appropriate.

## Scope Decisions

- Keep the product name `AuthMyMac`; do not copy the `VaultOTP` name from the
  reference.
- The sidebar has exactly two destinations: `All` and `Favorites`. Do not add
  Categories, Security, or Settings to the sidebar.
- Match the application windows, not the desktop wallpaper or Dock.
- Use SF Symbols for interface actions.
- Use official issuer artwork only when the asset is supplied or its use is
  license-cleared. Retain a generated issuer-initial fallback.
- Do not display an `iCloud Sync` status. The current product is local-only,
  Keychain items are non-synchronizable, and iCloud sync conflicts with
  `Docs/SECURITY.md`. Use `Local Vault` or `Vault Protected` in the same visual
  position.
- Favorites must be functional and persistent. Do not ship a decorative
  favorite button or an empty navigation destination disconnected from stored
  state.
- Do not ship a nonfunctional Lock control. Visual work may define its
  component, but it must either have real behavior or be omitted until its
  behavior is implemented.
- A flashlight button must only appear when the active capture device supports
  a torch. Most Mac cameras do not. Preserve screen-area scanning as the useful
  alternative.

## Reference Geometry

Use these dimensions as visual-comparison baselines, then retain sensible
minimum sizes for resizable macOS windows:

| State | Baseline size | Notes |
| --- | ---: | --- |
| Main vault | 880 x 750 pt | Approximately 220 pt sidebar and 660 pt content |
| QR scanner sheet | 410 x 440 pt | Large camera viewport below compact title area |
| Add account sheet | 450 x 350 pt | Compact form with full-width primary action |

The main window should remain resizable. Use relative layout constraints after
establishing the baseline rather than scaling the entire interface.

## Phase 1: Design System

Extend `Sources/UI/DesignSystem.swift` with semantic tokens for:

- Window, sheet, row, input, and selected-sidebar corner radii. Keep card
  corner radii at 8 pt or less.
- Sidebar width and header height.
- Account-row height, issuer-mark size, countdown size, and stable action-button
  frames.
- Content gutters, sidebar insets, row spacing, field spacing, and sheet
  spacing.
- Surface fills, strokes, selection fills, subdued text, and primary accent.
- Typography roles for window title, section title, account name, account
  identity, OTP code, captions, and form labels.

Keep system typography and semantic colors so Dynamic Type, light/dark mode,
Increase Contrast, and Reduce Transparency remain supported. Avoid a custom
font unless the user explicitly supplies one.

Update `Sources/UI/Components/GlassPanel.swift` so glass is applied after layout
and appearance modifiers. Put multiple sibling glass surfaces in a
`GlassEffectContainer` whose spacing matches the layout. Use interactive glass
only for controls that actually respond to pointer or click input.

## Phase 2: Window and Navigation Shell

Update `Sources/App/AuthMyMacApp.swift`:

- Change the default main-window size to approximately 880 x 750 pt.
- Preserve `.windowResizability(.contentMinSize)` with a practical minimum.
- Use unified macOS chrome with hidden title text so traffic lights visually sit
  over the sidebar like the reference.
- Keep `App` limited to scene and dependency composition.

Rebuild the main root with a two-column `NavigationSplitView`:

- Sidebar ideal width: 220 pt, with a narrow allowed resize range.
- Detail column owns the vault header, scrolling account collection, and bottom
  status strip.
- Use native selection and keyboard navigation while applying the compact
  selected-row appearance from the reference.

Define a stable navigation enum with exactly two cases: `all` and `favorites`.
The `All` destination displays every account, while `Favorites` filters the
same account collection using persisted favorite state.

## Phase 3: Sidebar

Create a dedicated `VaultSidebar` with:

- `AuthMyMac` brand title beneath the traffic-light area.
- Exactly two icon and text rows: `All` and `Favorites`.
- A compact selected state with subtle translucent fill.
- A bottom-aligned local-vault status surface with a green status indicator.

Both rows must use native list selection or another semantic SwiftUI navigation
control. Do not implement clickable rows with `onTapGesture`.

Do not add a Settings item to the sidebar. The existing macOS `Settings` scene
may remain accessible through the application menu for preferences such as the
menu-bar-extra toggle.

## Phase 4: Vault Header and Account Collection

Replace the current toolbar-dominant layout in
`Sources/UI/AuthenticatorRootView.swift` with a content header matching the
reference:

- Leading `All Codes` title and account count.
- Trailing search field with a stable width.
- Square glass add button with a plus symbol, tooltip, accessibility label, and
  Command-N shortcut where appropriate.
- Preserve camera scanning and screen-area scanning through the add flow or a
  compact menu; do not remove existing functionality.

Render the account collection as separate framed rows:

- Issuer mark.
- Issuer and account identity.
- Monospaced OTP grouped according to digit count.
- Circular remaining-time indicator.
- Functional favorite button backed by persisted favorite state.
- Context menu for copy and delete.
- Hover and keyboard-focus feedback without changing row dimensions.

Use each `OTPAccount.id` as `ForEach` identity. Keep the application-owned
one-second clock; account rows must not create timers. Extract the frequently
updating code and countdown portions into small subviews to limit invalidation.

Support these states:

- Loaded accounts.
- Empty vault.
- Search with no results.
- Copy feedback.
- Storage or generation failure.
- Locked vault, if lock behavior is included.

## Phase 5: Issuer Marks

Create a reusable `IssuerMark` resolver in `UI`:

- Normalize known issuer names.
- Resolve an optional bundled asset for known issuers.
- Fall back to the existing deterministic initial and color treatment.
- Keep decorative artwork out of the accessibility tree because adjacent text
  already identifies the issuer.

Do not fetch issuer artwork from the network. AuthMyMac is local-only.

## Phase 6: Unified Add-Account Flow

Replace the independent `isPresentingManualEntry` and `isPresentingCamera`
booleans in `AuthenticatorCoordinator` with a single item-driven presentation
route. A suitable shape is an `Identifiable` enum representing scan and manual
entry. Present it through one `.sheet(item:)` so conflicting sheets cannot be
active.

Move feature-specific sheet views out of the large
`Sources/Authenticator/AuthenticatorFeature.swift` file into focused files
under `Sources/Authenticator/Views/`. Reusable visual controls remain in `UI`.

The add-account flow should own:

- Scan/manual segmented selection.
- Back and dismiss actions.
- Camera lifecycle start and cancellation.
- Manual-entry draft state and validation.
- Successful import dismissal.

Preserve coordinator ownership of import, persistence, and error handling.

## Phase 7: Scanner Sheet

Restyle the existing camera preview without changing capture ownership:

- Compact centered `Scan QR Code` title and leading back button.
- Instruction text above the preview.
- Rounded camera viewport occupying most of the sheet.
- Four noninteractive corner guides framing the expected QR region.
- Camera permission, denied, unavailable, loading, and active states.
- Accessible preview label and actionable permission-denied message.
- Conditional torch control only when supported.

Continue using `Sources/CameraCapture/CameraCapturePreview.swift` for the
`AVCaptureVideoPreviewLayer`. The session must stop on success, cancellation,
dismissal, and loss of presentation.

## Phase 8: Manual Entry Sheet

Replace the grouped `Form` appearance with the compact reference layout:

- Centered `Add Account` title and leading back button.
- Scan/manual segmented control.
- Horizontally aligned labels and fields for account name, optional issuer, and
  Base32 secret.
- Secret visibility toggle implemented as an icon button with tooltip and
  accessibility label.
- Inline validation near the relevant field or above the primary action.
- Full-width prominent `Add Account` button.
- Default-action keyboard shortcut and predictable focus order.

Do not persist, log, snapshot, or expose the secret. Retain `SecureField` while
the secret is concealed. Keep paste support user-initiated.

## Phase 9: Favorite Persistence and Optional Locking

### Favorites (Required)

Add persistent favorite metadata through the storage boundary, expose a
coordinator toggle, and filter the Favorites destination. Do not derive
favorite state in the view.

### Vault Locking (Optional)

Define lock semantics before implementing the reference footer. At minimum,
locking must stop code refresh, remove secret-derived codes from in-memory UI
state, block copy/export, and require an approved unlock operation. Do not imply
that hidden SwiftUI views have cleared sensitive state.

iCloud synchronization is excluded unless `Docs/SECURITY.md`, Keychain policy,
storage architecture, conflict handling, and threat modeling are intentionally
revised in a separate change.

## Suggested File Layout

```text
Sources/UI/
  AuthenticatorRootView.swift
  DesignSystem.swift
  Components/
    AccountCard.swift
    CountdownIndicator.swift
    GlassPanel.swift
    IconActionButton.swift
    IssuerMark.swift
    VaultHeader.swift
    VaultSidebar.swift
    VaultStatusBar.swift

Sources/Authenticator/
  AuthenticatorFeature.swift
  Views/
    AddAccountSheet.swift
    CameraScannerSheet.swift
    ManualAccountEntryView.swift
```

Adapt names to the surrounding code if a smaller split is clearer. Do not add
an abstraction solely to mirror this proposed tree.

## Testing Plan

Start each behavior change with the smallest failing test in its owning target.

Add or update tests for:

- Design-system spacing, control sizes, and stable geometry.
- Sidebar filtering and selection if extracted into pure state.
- Search over issuer and account identity.
- Add-account route transitions and mutual exclusion.
- Manual validation and successful retry.
- Camera cancellation when the sheet dismisses.
- Favorite persistence, toggling, and filtering.
- Lock clearing and action blocking, if implemented.

Add self-contained SwiftUI previews using in-memory sample metadata and
synthetic display codes. Previews must not access Keychain, camera permissions,
screen capture, the network, or live storage.

Required preview states:

- Main vault with six representative accounts.
- Empty vault.
- Search with no results.
- Light and dark appearances.
- Reduced Transparency and Increased Contrast.
- Scanner active, permission denied, and unavailable.
- Manual entry empty, focused, invalid, and submitting.
- Long issuer/account strings and eight-digit OTP layout.

## Visual Acceptance Criteria

- The main window matches the reference hierarchy and proportions at 880 x 750
  pt without text truncation or overlapping controls.
- Sidebar, header, rows, and bottom status align on a consistent spacing grid.
- Account rows remain dimensionally stable when codes/countdowns update and
  controls hover or focus.
- Scanner and manual sheets match their baseline sizes and do not resize while
  validation or loading state changes.
- Glass remains legible in light and dark appearances and does not become an
  opaque gray stack when Reduce Transparency is enabled.
- All icon-only controls have tooltips and accessibility labels.
- Full keyboard navigation works for sidebar, search, account actions,
  segmented selection, form fields, and dismissal.
- No secret, OTP URI, migration payload, or Keychain material appears in logs,
  committed screenshots, snapshots, fixture names, or assertion text.

## Verification

Run from the repository root:

```sh
swift test
swift build -c release
OPEN_AFTER_BUILD=0 ./BUILD.sh
```

Then visually inspect the signed app at the baseline window sizes in:

- Light mode.
- Dark mode.
- Reduce Transparency.
- Increase Contrast.
- Minimum supported window size.
- A larger resized window.

Capture comparison screenshots only with synthetic, non-secret account data.

## Definition of Done

The redesign is complete when the three reference states are visually matched,
all visible controls are functional, current import/export/copy/delete behavior
still works, capture sessions cancel correctly, accessibility states are
present, the security boundary remains intact, and the complete test and
release build commands pass.
