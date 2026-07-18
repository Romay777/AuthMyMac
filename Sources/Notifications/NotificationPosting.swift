import Domain

public enum NotificationAuthorizationState: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
}

public protocol NotificationPosting: Sendable {
    func authorizationState() async -> NotificationAuthorizationState
    func requestAuthorization() async throws -> Bool
    func postScanSuccess(for account: OTPAccount) async throws
}
