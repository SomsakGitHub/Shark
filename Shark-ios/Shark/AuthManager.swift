import AuthenticationServices
import Combine
import Foundation

@MainActor
final class AuthManager: ObservableObject {
    @Published private(set) var user: APIUser?

    var isSignedIn: Bool {
        user != nil && AuthStore.token != nil
    }

    init() {
        guard AuthStore.token != nil else { return }
        Task { await refreshMe() }
    }

    func handleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8) else {
                return
            }
            var name: String?
            if let fullName = credential.fullName {
                let joined = [fullName.givenName, fullName.familyName]
                    .compactMap { $0 }
                    .joined(separator: " ")
                if !joined.isEmpty { name = joined }
            }
            Task {
                do {
                    try await exchange(identityToken: identityToken, name: name)
                } catch {
                    print("Sign in failed: \(error.localizedDescription)")
                }
            }
        case .failure(let error):
            print("Sign in cancelled: \(error.localizedDescription)")
        }
    }

    func signOut() {
        AuthStore.clear()
        user = nil
    }

    func refresh() async {
        await refreshMe()
    }

    private func exchange(identityToken: String, name: String?) async throws {
        var body: [String: String] = ["identityToken": identityToken]
        if let name { body["name"] = name }
        let payload = try JSONSerialization.data(withJSONObject: body)
        let response: AuthResponse = try await APIClient.shared.request(
            "/api/auth/apple",
            method: "POST",
            body: payload
        )
        AuthStore.save(response.token)
        user = response.user
    }

    private func refreshMe() async {
        if let response: MeResponse = try? await APIClient.shared.request("/api/me") {
            user = response.user
        }
    }
}
