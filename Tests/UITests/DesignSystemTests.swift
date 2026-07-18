import Testing
@testable import UI
import Domain
import Foundation

@Suite("Design system")
struct DesignSystemTests {
    @Test("Uses a compact, monotonic spacing scale")
    func spacingScale() {
        let values = AuthMyMacSpacing.allCases.map(\.value)

        #expect(values == values.sorted())
        #expect(Set(values).count == values.count)
        #expect(AuthMyMacSpacing.compact.value <= 8)
    }

    @Test("Keeps interactive controls at an accessible size")
    func controlSize() {
        #expect(AuthMyMacMetrics.minimumControlSize >= 28)
        #expect(AuthMyMacMetrics.accountRowHeight == 82)
        #expect(AuthMyMacMetrics.accountListRowSpacing == 2)
        #expect(AuthMyMacMetrics.accountDeleteTriggerDistance < AuthMyMacMetrics.accountDeleteRevealWidth)
        #expect(AuthMyMacMetrics.accountMarkSize > AuthMyMacMetrics.minimumControlSize)
        #expect(AuthMyMacMetrics.countdownSize >= AuthMyMacMetrics.minimumControlSize)
        #expect(AuthMyMacMetrics.panelCornerRadius <= 8)
        #expect(AuthMyMacMetrics.sidebarIdealWidth == 220)
        #expect(AuthMyMacMetrics.actionButtonSize >= AuthMyMacMetrics.minimumControlSize)
        #expect(AuthMyMacMetrics.headerActionWidth == AuthMyMacMetrics.headerControlHeight)
        #expect(AuthMyMacMetrics.headerControlHeight == 36)
        #expect(AuthMyMacMetrics.headerTopInset == AuthMyMacMetrics.headerControlHeight / 20)
        #expect(AuthMyMacMetrics.sidebarNavigationFontSize == 13)
        #expect(AuthMyMacMetrics.sidebarNavigationIconScale == 1.25)
    }

    @Test("Reveals delete only for a deliberate left drag")
    func accountCardDeleteGesture() {
        #expect(AccountCardSwipe.offset(for: CGSize(width: -24, height: 2)) == -24)
        #expect(
            AccountCardSwipe.offset(for: CGSize(width: -100, height: 2))
                == -AuthMyMacMetrics.accountDeleteRevealWidth
        )
        #expect(AccountCardSwipe.offset(for: CGSize(width: 24, height: 2)) == 0)
        #expect(AccountCardSwipe.offset(for: CGSize(width: -24, height: 30)) == 0)
        #expect(AccountCardSwipe.requestsDeletion(for: CGSize(width: -48, height: 2)))
        #expect(!AccountCardSwipe.requestsDeletion(for: CGSize(width: -30, height: 2)))
        #expect(!AccountCardSwipe.requestsDeletion(for: CGSize(width: -48, height: 60)))
    }

    @Test("Filters favorites and searches issuer or identity")
    func filtersAccounts() throws {
        let favorite = try OTPAccount(
            issuer: "Example Cloud",
            accountName: "person@example.com",
            secretKeychainID: "favorite-reference",
            isFavorite: true
        )
        let other = try OTPAccount(
            issuer: "Acme",
            accountName: "admin@acme.test",
            secretKeychainID: "other-reference"
        )

        #expect(VaultAccountFilter.accounts([favorite, other], destination: .favorites, query: "") == [favorite])
        #expect(VaultAccountFilter.accounts([favorite, other], destination: .all, query: "cloud") == [favorite])
        #expect(VaultAccountFilter.accounts([favorite, other], destination: .all, query: "ADMIN") == [other])
    }

    @Test("Provides a sidebar destination for settings")
    func sidebarDestinations() {
        #expect(VaultDestination.allCases == [.all, .favorites, .settings])
    }

    @Test("Keeps the menu bar extra available when the Dock icon is hidden")
    func menuBarVisibilityInvariant() {
        #expect(MenuBarVisibilityPreferences.isMenuBarExtraInserted(
            showMenuBarExtra: false,
            hideAppFromDock: true
        ))
        #expect(MenuBarVisibilityPreferences.updatedMenuBarExtraVisibility(
            false,
            hideAppFromDock: true
        ))
        #expect(!MenuBarVisibilityPreferences.updatedMenuBarExtraVisibility(
            false,
            hideAppFromDock: false
        ))
    }
}
