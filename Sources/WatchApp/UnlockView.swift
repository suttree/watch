import SwiftUI

struct UnlockView: View {
    let isCreatingPassword: Bool
    let isUnlocking: Bool
    let errorMessage: String?
    let unlock: (String) -> Void

    @Environment(\.readerTheme) private var theme
    @State private var password = ""
    @State private var confirmPassword = ""
    @FocusState private var isPasswordFocused: Bool

    private var canSubmit: Bool {
        guard !password.isEmpty else {
            return false
        }
        return isCreatingPassword ? password == confirmPassword : true
    }

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            // One mark, not two: the candle stands in for the book above the
            // wordmark, rather than the app showing a book here and a horse
            // down at the foot of the same screen.
            VStack(spacing: 10) {
                CandleMark(height: 54, opacity: 0.75)
                    Text("Read")
                        .font(BrandTypeface.wordmark(22))
                        .embossedText()
                    .foregroundStyle(theme.ink)
            }

            VStack(spacing: 10) {
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
                    .focused($isPasswordFocused)
                    .onSubmit {
                        if canSubmit {
                            unlock(password)
                        }
                    }

                if isCreatingPassword {
                    SecureField("Confirm Password", text: $confirmPassword)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                        .onSubmit {
                            if canSubmit {
                                unlock(password)
                            }
                        }
                }
            }
            .onAppear {
                isPasswordFocused = true
            }

            if let errorMessage {
                    Text(errorMessage)
                        .font(ReaderTheme.sans(13))
                        .embossedText()
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }

            Button {
                unlock(password)
            } label: {
                if isUnlocking {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 80)
                } else {
                    Text(isCreatingPassword ? "Create" : "Unlock").frame(width: 80)
                        .embossedText()
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canSubmit || isUnlocking)

            Spacer()
        }
        .padding(28)
        .frame(minWidth: 480, minHeight: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.texturedPaper)
        .preferredColorScheme(.light)
    }
}
