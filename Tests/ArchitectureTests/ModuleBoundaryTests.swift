import CameraCapture
import Diagnostics
import Domain
import Authenticator
import MenuBar
import Notifications
import OTP
import QR
import ScreenCapture
import Storage
import Testing
import UI

@Suite("Module boundaries")
struct ModuleBoundaryTests {
    @Test("Every planned feature exposes a stable boundary")
    func exposesFeatureContracts() {
        let contractNames = [
            String(describing: (any TOTPGenerating).self),
            String(describing: (any AccountStoring).self),
            String(describing: (any OTPURIParsing).self),
            String(describing: (any CameraScanning).self),
            String(describing: (any ScreenRegionCapturing).self),
            String(describing: (any NotificationPosting).self),
            String(describing: (any DiagnosticsRecording).self),
            String(describing: AuthenticatorCoordinator.self),
        ]

        #expect(contractNames.count == 8)
        #expect(contractNames.allSatisfy { !$0.isEmpty })
    }

    @Test("Menu actions remain stable composition identifiers")
    func menuActionsAreStable() {
        #expect(Set(MenuBarAction.allCases.map(\.id)).count == MenuBarAction.allCases.count)
    }
}
