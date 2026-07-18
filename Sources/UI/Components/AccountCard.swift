import Domain
import SwiftUI

public struct AccountCard: View {
    private let account: OTPAccount
    private let code: String
    private let remainingSeconds: Int
    private let isCopied: Bool
    private let isCopyAvailable: Bool
    private let onEdit: () -> Void
    private let onFavorite: () -> Void
    private let onCopy: () -> Void
    private let onDelete: () -> Void
    @State private var isHovered = false
    @State private var deleteDragOffset: CGFloat = 0

    public init(
        account: OTPAccount,
        code: String,
        remainingSeconds: Int,
        isCopied: Bool,
        isCopyAvailable: Bool,
        onEdit: @escaping () -> Void,
        onFavorite: @escaping () -> Void,
        onCopy: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.account = account
        self.code = code
        self.remainingSeconds = remainingSeconds
        self.isCopied = isCopied
        self.isCopyAvailable = isCopyAvailable
        self.onEdit = onEdit
        self.onFavorite = onFavorite
        self.onCopy = onCopy
        self.onDelete = onDelete
    }

    public var body: some View {
        ZStack(alignment: .trailing) {
            deleteAction
            cardContent
                .offset(x: deleteDragOffset)
                .simultaneousGesture(deleteDragGesture)
        }
        .frame(height: AuthMyMacMetrics.accountRowHeight)
        .compositingGroup()
        .clipShape(.rect(cornerRadius: AuthMyMacMetrics.rowCornerRadius))
        .shadow(color: AuthMyMacColors.ink.opacity(0.025), radius: 5, y: 2)
        .contentShape(.rect)
        .onHover { isHovered = $0 }
        .accessibilityAction(named: "Delete Account", onDelete)
        .contextMenu {
            Button("Edit Account", systemImage: "pencil", action: onEdit)
            Button("Copy Code", systemImage: "doc.on.doc", action: onCopy)
                .disabled(!isCopyAvailable)
            Button(
                account.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                systemImage: account.isFavorite ? "star.slash" : "star",
                action: onFavorite
            )
            Divider()
            Button("Delete Account", systemImage: "trash", role: .destructive, action: onDelete)
        }
        .accessibilityElement(children: .contain)
    }

    private var cardContent: some View {
        HStack(spacing: AuthMyMacSpacing.standard.value) {
            IssuerMark(issuer: account.issuer)

            VStack(alignment: .leading, spacing: AuthMyMacSpacing.hairline.value) {
                Text(account.issuer)
                    .font(AuthMyMacTypography.accountName)
                    .lineLimit(1)
                Text(account.accountName)
                    .font(AuthMyMacTypography.accountIdentity)
                    .foregroundStyle(AuthMyMacColors.subduedText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VerificationCodeText(code: code)
                .frame(minWidth: account.digits == .eight ? 124 : 104, alignment: .trailing)

            CountdownIndicator(remainingSeconds: remainingSeconds, period: account.period)

            HStack(spacing: 0) {
                actionButton(title: "Edit Account", systemImage: "pencil", action: onEdit)
                    .foregroundStyle(Color.secondary)

                actionButton(
                    title: account.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                    systemImage: account.isFavorite ? "star.fill" : "star",
                    action: onFavorite
                )
                .foregroundStyle(account.isFavorite ? AuthMyMacColors.accent : Color.secondary)

                actionButton(
                    title: isCopied ? "Copied" : "Copy Code",
                    systemImage: isCopied ? "checkmark" : "doc.on.doc",
                    action: onCopy
                )
                .foregroundStyle(isCopied ? AuthMyMacColors.accent : Color.secondary)
                .disabled(!isCopyAvailable)
            }
        }
        .padding(.horizontal, AuthMyMacSpacing.roomy.value)
        .frame(height: AuthMyMacMetrics.accountRowHeight)
        .background(isHovered ? AuthMyMacColors.elevatedSurface : AuthMyMacColors.surface)
        .overlay {
            RoundedRectangle(cornerRadius: AuthMyMacMetrics.rowCornerRadius)
                .stroke(AuthMyMacColors.stroke, lineWidth: 1)
        }
    }

    private var deleteAction: some View {
        Button(action: requestDelete) {
            Image(systemName: "trash.fill")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .frame(width: AuthMyMacMetrics.accountDeleteRevealWidth)
        .background(Color.red.opacity(0.82))
        .opacity(deleteDragOffset < 0 ? 1 : 0)
        .allowsHitTesting(deleteDragOffset < 0)
        .accessibilityLabel("Delete Account")
        .accessibilityHidden(deleteDragOffset == 0)
        .help("Delete Account")
    }

    private var deleteDragGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                deleteDragOffset = AccountCardSwipe.offset(for: value.translation)
            }
            .onEnded { value in
                let requestsDeletion = AccountCardSwipe.requestsDeletion(for: value.translation)
                withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                    deleteDragOffset = 0
                }
                if requestsDeletion {
                    onDelete()
                }
            }
    }

    private func requestDelete() {
        withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
            deleteDragOffset = 0
        }
        onDelete()
    }

    private func actionButton(
        title: LocalizedStringKey,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: AuthMyMacMetrics.actionButtonSize, height: AuthMyMacMetrics.actionButtonSize)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.borderless)
        .help(Text(title))
        .accessibilityLabel(Text(title))
    }
}

enum AccountCardSwipe {
    static func offset(for translation: CGSize) -> CGFloat {
        guard abs(translation.width) > abs(translation.height) else { return 0 }
        return min(0, max(-AuthMyMacMetrics.accountDeleteRevealWidth, translation.width))
    }

    static func requestsDeletion(for translation: CGSize) -> Bool {
        abs(translation.width) > abs(translation.height)
            && translation.width <= -AuthMyMacMetrics.accountDeleteTriggerDistance
    }
}

private struct VerificationCodeText: View {
    let code: String

    var body: some View {
        Text(groupedCode)
            .font(AuthMyMacTypography.otpCode)
            .contentTransition(.numericText())
            .monospacedDigit()
            .lineLimit(1)
            .accessibilityLabel("Verification code")
            .accessibilityValue(code)
    }

    private var groupedCode: String {
        let compact = code.replacingOccurrences(of: " ", with: "")
        let split = compact.count == 8 ? 4 : compact.count / 2
        guard split > 0, compact.count > split else { return compact }
        let index = compact.index(compact.startIndex, offsetBy: split)
        return "\(compact[..<index]) \(compact[index...])"
    }
}
