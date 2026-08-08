//
//  AuthStore.swift
//  Shark
//
//  Created by tiscomacnb2486 on 7/8/2569 BE.
//

import Foundation
import Combine
import os

@MainActor
final class AuthStore: ObservableObject {
    @Published private(set) var token: String?
    @Published private(set) var username: String?

    private let client: APIClient
    private let keychain: KeychainStore

    init(client: APIClient? = nil, keychain: KeychainStore? = nil) {
        self.client = client ?? APIClient()
        self.keychain = keychain ?? KeychainStore(service: "com.somsak.Shark.auth")
        self.token = self.keychain.string(forKey: "token")
        self.username = self.keychain.string(forKey: "username")
    }

    var isAuthenticated: Bool {
        token != nil
    }

    func login(username: String, password: String) async throws {
        let session = try await client.login(username: username, password: password)
        store(session)
    }

    func signInWithApple(identityToken: String) async throws {
        let session = try await client.appleLogin(identityToken: identityToken)
        store(session)
    }

    func logout() {
        token = nil
        username = nil
        keychain.delete("token")
        keychain.delete("username")
        Logger.view.info("Logged out")
    }

    private func store(_ session: AuthSession) {
        token = session.token
        username = session.username
        keychain.set(session.token, forKey: "token")
        keychain.set(session.username, forKey: "username")
        Logger.view.info("Authenticated as \(session.username, privacy: .public)")
    }
}
