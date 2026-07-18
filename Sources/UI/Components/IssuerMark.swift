import SwiftUI

public struct IssuerMark: View {
    private let issuer: String

    public init(issuer: String) {
        self.issuer = issuer
    }

    public var body: some View {
        Group {
            if let assetName = bundledAssetName {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
                    .padding(8)
            } else {
                Text(String(issuer.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased())
                    .font(.headline)
                    .foregroundStyle(tint)
            }
        }
        .frame(width: AuthMyMacMetrics.accountMarkSize, height: AuthMyMacMetrics.accountMarkSize)
        .background(tint.opacity(0.14), in: .rect(cornerRadius: 7))
        .accessibilityHidden(true)
    }

    private var bundledAssetName: String? {
        nil
    }

    private var tint: Color {
        let palette: [Color] = [.blue, .green, .orange, .red, .teal]
        let normalized = issuer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let value = normalized.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return palette[value % palette.count]
    }
}
