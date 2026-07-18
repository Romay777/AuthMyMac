// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "AuthMyMac",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .executable(name: "AuthMyMac", targets: ["App"]),
        .library(name: "Domain", targets: ["Domain"]),
        .library(name: "OTP", targets: ["OTP"]),
        .library(name: "Storage", targets: ["Storage"]),
        .library(name: "QR", targets: ["QR"]),
        .library(name: "CameraCapture", targets: ["CameraCapture"]),
        .library(name: "ScreenCapture", targets: ["ScreenCapture"]),
        .library(name: "MenuBar", targets: ["MenuBar"]),
        .library(name: "Notifications", targets: ["Notifications"]),
        .library(name: "UI", targets: ["UI"]),
        .library(name: "Authenticator", targets: ["Authenticator"]),
        .library(name: "Diagnostics", targets: ["Diagnostics"]),
    ],
    targets: [
        .target(name: "Domain"),
        .target(name: "Diagnostics"),
        .target(name: "OTP", dependencies: ["Domain"]),
        .target(name: "Storage", dependencies: ["Domain"]),
        .target(name: "QR", dependencies: ["Domain", "OTP"]),
        .target(name: "CameraCapture", dependencies: ["QR"]),
        .target(name: "ScreenCapture", dependencies: ["QR"]),
        .target(name: "Notifications", dependencies: ["Domain"]),
        .target(name: "UI", dependencies: ["Domain"]),
        .target(name: "MenuBar", dependencies: ["UI"]),
        .target(
            name: "Authenticator",
            dependencies: [
                "CameraCapture",
                "Domain",
                "MenuBar",
                "Notifications",
                "OTP",
                "QR",
                "ScreenCapture",
                "Storage",
                "UI",
            ]
        ),
        .executableTarget(
            name: "App",
            dependencies: [
                "Authenticator",
                "UI",
            ]
        ),
        .testTarget(
            name: "DomainTests",
            dependencies: ["Domain"]
        ),
        .testTarget(
            name: "OTPTests",
            dependencies: ["OTP", "Domain"]
        ),
        .testTarget(
            name: "QRTests",
            dependencies: ["QR", "Domain"]
        ),
        .testTarget(
            name: "StorageTests",
            dependencies: ["Storage", "Domain"]
        ),
        .testTarget(
            name: "ScreenCaptureTests",
            dependencies: ["ScreenCapture", "QR"]
        ),
        .testTarget(
            name: "DiagnosticsTests",
            dependencies: ["Diagnostics"]
        ),
        .testTarget(
            name: "UITests",
            dependencies: ["UI"]
        ),
        .testTarget(
            name: "AuthenticatorTests",
            dependencies: [
                "Authenticator",
                "CameraCapture",
                "Domain",
                "Notifications",
                "OTP",
                "QR",
                "ScreenCapture",
                "Storage",
            ]
        ),
        .testTarget(
            name: "ArchitectureTests",
            dependencies: [
                "Domain",
                "OTP",
                "Storage",
                "QR",
                "CameraCapture",
                "ScreenCapture",
                "MenuBar",
                "Notifications",
                "UI",
                "Authenticator",
                "Diagnostics",
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
