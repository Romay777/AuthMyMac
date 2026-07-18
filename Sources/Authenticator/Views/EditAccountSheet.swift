import Domain
import SwiftUI
import UI

struct EditAccountSheet: View {
    private enum Field: Hashable {
        case issuer
        case accountName
    }

    @Environment(\.dismiss) private var dismiss
    let coordinator: AuthenticatorCoordinator
    let account: OTPAccount
    @State private var issuer: String
    @State private var accountName: String
    @State private var errorMessage: String?
    @State private var isSaving = false
    @FocusState private var focusedField: Field?

    init(account: OTPAccount, coordinator: AuthenticatorCoordinator) {
        self.account = account
        self.coordinator = coordinator
        _issuer = State(initialValue: account.issuer)
        _accountName = State(initialValue: account.accountName)
    }

    var body: some View {
        NavigationStack {
            Grid(
                alignment: .leading,
                horizontalSpacing: AuthMyMacSpacing.standard.value,
                verticalSpacing: AuthMyMacSpacing.standard.value
            ) {
                formRow("Issuer") {
                    TextField("Issuer", text: $issuer)
                        .focused($focusedField, equals: .issuer)
                        .authMyMacInputStyle()
                }
                formRow("Account Name") {
                    TextField("Account Name", text: $accountName)
                        .focused($focusedField, equals: .accountName)
                        .textContentType(.username)
                        .authMyMacInputStyle()
                }
            }
            .padding(AuthMyMacSpacing.section.value)
            .navigationTitle("Edit Account")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(isSaveDisabled)
                }
            }
        }
        .frame(width: 450, height: 190)
        .background(AuthMyMacColors.sheet)
        .foregroundStyle(AuthMyMacColors.ink)
        .tint(AuthMyMacColors.accent)
        .preferredColorScheme(.light)
        .defaultFocus($focusedField, .issuer)
        .alert("Unable to Save Account", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "An unexpected error occurred.")
        }
    }

    private var isSaveDisabled: Bool {
        isSaving
            || issuer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || accountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        guard !isSaveDisabled else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await coordinator.updateAccount(account, issuer: issuer, accountName: accountName)
                dismiss()
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func formRow<Content: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GridRow {
            Text(title)
                .font(AuthMyMacTypography.formLabel)
                .frame(width: 96, alignment: .trailing)
            content()
                .frame(minWidth: 260)
        }
    }
}
