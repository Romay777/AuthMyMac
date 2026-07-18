import Domain
import Foundation
import UserNotifications

public actor UserNotificationPoster: NotificationPosting {
    private let center = UNUserNotificationCenter.current()

    public init() {}

    public func authorizationState() async -> NotificationAuthorizationState {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return NotificationAuthorizationState.authorized
        case .denied: return NotificationAuthorizationState.denied
        case .notDetermined: return NotificationAuthorizationState.notDetermined
        @unknown default: return NotificationAuthorizationState.denied
        }
    }

    public func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert])
    }

    public func postScanSuccess(for account: OTPAccount) async throws {
        let content = UNMutableNotificationContent()
        content.title = "QR code successfully scanned"
        content.body = "Added \(account.issuer)"
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try await center.add(request)
    }
}
