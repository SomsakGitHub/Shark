//
//  LoginView.swift
//  Shark
//
//  Created by tiscomacnb2486 on 7/8/2569 BE.
//

import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @EnvironmentObject private var auth: AuthStore

    @State private var errorMessage: String?
    @State private var isSigningIn = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "map")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            Text("Sign in to unlock the map")
                .font(.title2.bold())

            Text("Use your Apple ID to continue.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                handle(result)
            }
            .frame(height: 48)
            .frame(maxWidth: 400)
            .padding(.horizontal)

            if isSigningIn {
                ProgressView()
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()
            Spacer()
        }
        .padding()
    }

    private func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8) else {
                errorMessage = "Couldn't get Apple identity token"
                return
            }
            isSigningIn = true
            Task {
                do {
                    try await auth.signInWithApple(identityToken: identityToken)
                } catch {
                    errorMessage = error.localizedDescription
                }
                isSigningIn = false
            }
        case .failure(let error):
            if let authError = error as? ASAuthorizationError,
               authError.code == .canceled {
                return
            }
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthStore())
}
