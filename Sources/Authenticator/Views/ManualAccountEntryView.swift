import SwiftUI
import UI

struct ManualAccountEntryView: View {
    private enum Field: Hashable {
        case accountName
        case issuer
        case secret
    }

    @Bindable var coordinator: AuthenticatorCoordinator
    @State private var isSecretVisible = false
    @FocusState private var focusedField: Field?

    var body: some View {
        VStack(spacing: AuthMyMacSpacing.roomy.value) {
            AddAccountModePicker(coordinator: coordinator)
                .frame(width: 220)

            Grid(alignment: .leading, horizontalSpacing: AuthMyMacSpacing.standard.value, verticalSpacing: AuthMyMacSpacing.standard.value) {
                formRow("Account Name") {
                    TextField("Account Name", text: $coordinator.manualAccountName, prompt: Text("name@example.com"))
                        .focused($focusedField, equals: .accountName)
                        .textContentType(.username)
                        .authMyMacInputStyle()
                }
                formRow("Issuer") {
                    TextField("Issuer", text: $coordinator.manualIssuer, prompt: Text("Optional"))
                        .focused($focusedField, equals: .issuer)
                        .authMyMacInputStyle()
                }
                formRow("Secret") {
                    HStack(spacing: AuthMyMacSpacing.compact.value) {
                        Group {
                            if isSecretVisible {
                                TextField("Secret", text: $coordinator.manualSecret, prompt: Text("Base32 secret"))
                            } else {
                                SecureField("Secret", text: $coordinator.manualSecret, prompt: Text("Base32 secret"))
                            }
                        }
                        .focused($focusedField, equals: .secret)
                        .authMyMacInputStyle()

                        Button {
                            isSecretVisible.toggle()
                        } label: {
                            Image(systemName: isSecretVisible ? "eye.slash" : "eye")
                                .frame(width: AuthMyMacMetrics.minimumControlSize, height: AuthMyMacMetrics.minimumControlSize)
                        }
                        .buttonStyle(.borderless)
                        .help(isSecretVisible ? "Hide Secret" : "Show Secret")
                        .accessibilityLabel(isSecretVisible ? "Hide Secret" : "Show Secret")

                        PasteButton(payloadType: String.self) { values in
                            if let value = values.first {
                                coordinator.manualSecret = value
                            }
                        }
                        .labelStyle(.iconOnly)
                        .help("Paste Secret")
                        .accessibilityLabel("Paste Secret")
                    }
                }
            }

            Text(coordinator.manualEntryErrorMessage ?? " ")
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(coordinator.manualEntryErrorMessage == nil)

            Button {
                coordinator.addManualAccount()
            } label: {
                Group {
                    if coordinator.isAddingManualAccount {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Add Account")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(
                coordinator.isAddingManualAccount
                    || coordinator.manualAccountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || coordinator.manualSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
        }
        .padding(.horizontal, AuthMyMacSpacing.section.value)
        .padding(.bottom, AuthMyMacSpacing.section.value)
        .defaultFocus($focusedField, .accountName)
    }

    private func formRow<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        GridRow {
            Text(title)
                .font(AuthMyMacTypography.formLabel)
                .frame(width: 96, alignment: .trailing)
            content()
                .frame(minWidth: 260)
        }
    }
}
