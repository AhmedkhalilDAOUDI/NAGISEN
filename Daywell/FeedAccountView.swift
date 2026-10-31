import AuthenticationServices
import CryptoKit
import SwiftUI

/// Sign in, create an account, or choose a username, depending on where the member is.
/// Closes itself once they are signed in with a username; Settings → Account manages the rest.
struct FeedAccountView: View {
    @EnvironmentObject private var feed: FeedService
    @Environment(\.dismiss) private var dismiss
    @State private var creating = false
    @State private var email = ""
    @State private var password = ""
    @State private var username = ""
    @State private var appleNonce = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch feed.state {
                    case .notConfigured:
                        Text("Feed isn't set up in this build.")
                            .font(.subheadline).foregroundStyle(Theme.muted)
                    case .signedOut:
                        signIn
                    case .needsUsername:
                        chooseUsername
                    case .ready:
                        Text("You're signed in.").font(.subheadline).foregroundStyle(Theme.muted)
                    }
                    if let message = feed.message {
                        Text(message)
                            .font(.subheadline).foregroundStyle(Theme.accentText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .foregroundStyle(Theme.ink)
                .padding(20)
            }
            .background(NagisenBackdrop())
            .nagisenSheetBar(title, onClose: { dismiss() })
            .onChange(of: feed.state) { _, state in
                if state == .ready { dismiss() }
            }
        }
    }

    private var title: String {
        switch feed.state {
        case .ready: "Signed in"
        case .needsUsername: "Choose a username"
        default: creating ? "Create account" : "Sign in"
        }
    }

    private var signIn: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(creating ? "Join the NAGISEN community" : "Welcome back")
                .font(.system(size: 25, design: .serif))
            #if !NAGISEN_NO_ICLOUD
            SignInWithAppleButton(.continue) { request in
                appleNonce = Self.randomNonce()
                request.nonce = Self.sha256(appleNonce)
            } onCompletion: { result in
                guard case .success(let authorization) = result,
                      let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                      let token = credential.identityToken.flatMap({ String(data: $0, encoding: .utf8) }) else {
                    if case .failure(let error) = result,
                       (error as? ASAuthorizationError)?.code != .canceled {
                        feed.message = "Sign in with Apple didn't finish. \(error.localizedDescription)"
                    }
                    return
                }
                Task { await feed.signInWithApple(idToken: token, nonce: appleNonce) }
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            Text("or with email")
                .font(.caption2.weight(.semibold)).tracking(2)
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity)
            #endif
            VStack(spacing: 0) {
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .frame(minHeight: 54)
                Divider()
                SecureField(creating ? "Password (8 characters or more)" : "Password", text: $password)
                    .textContentType(creating ? .newPassword : .password)
                    .frame(minHeight: 54)
            }
            .padding(.horizontal, 16)
            .nagisenGlass(in: RoundedRectangle(cornerRadius: 15), tint: Theme.surface.opacity(0.18))
            NagisenPrimaryButton(creating ? "Create account" : "Sign in",
                                 enabled: email.contains("@") && password.count >= (creating ? 8 : 1) && !feed.isBusy) {
                Task {
                    if creating {
                        if await feed.signUp(email: email, password: password) {
                            creating = false
                            password = ""
                        }
                    } else {
                        await feed.signIn(email: email, password: password)
                    }
                }
            }
            Button(creating ? "I already have an account" : "Create an account") {
                creating.toggle()
                feed.message = nil
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.accentText)
            .frame(maxWidth: .infinity)
        }
    }

    private var chooseUsername: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("How should members see you?")
                .font(.system(size: 25, design: .serif))
            Text("Up to 30 letters, numbers, periods or underscores. It is shown with every post.")
                .font(.subheadline).foregroundStyle(Theme.muted)
            TextField("username", text: $username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .frame(minHeight: 54)
                .padding(.horizontal, 16)
                .nagisenGlass(in: RoundedRectangle(cornerRadius: 15), tint: Theme.surface.opacity(0.18))
            NagisenPrimaryButton("Continue",
                                 enabled: FeedRules.isValidUsername(FeedRules.normalizedUsername(username)) && !feed.isBusy) {
                Task { _ = await feed.claimUsername(username) }
            }
            Button("Sign out") { Task { await feed.signOut() } }
                .font(.subheadline).foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity)
        }
    }

    private static func randomNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
