//
//  APIClient.swift
//  Shark
//
//  Created by tiscomacnb2486 on 5/8/2569 BE.
//

import Foundation
import os

enum APIConfig {
    static let baseURL = URL(string: "https://shark-api-bd4f.onrender.com")!
}

extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.somsak.Shark"

    static let api = Logger(subsystem: subsystem, category: "API")
    static let view = Logger(subsystem: subsystem, category: "UI")
}

struct APIError: LocalizedError {
    let statusCode: Int

    var errorDescription: String? {
        "API error (status \(statusCode))"
    }
}

struct AuthSession: Codable {
    let token: String
    let username: String
}

struct MapCenter: Codable {
    let latitude: Double
    let longitude: Double
}

struct MapSpot: Codable, Identifiable {
    let id: Int
    let name: String
    let latitude: Double
    let longitude: Double
}

struct MapData: Codable {
    let center: MapCenter
    let spots: [MapSpot]
}

struct APIClient {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = APIConfig.baseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func health() async throws -> Bool {
        let url = baseURL.appending(path: "health")
        Logger.api.info("GET \(url.absoluteString, privacy: .public)")
        let (_, response) = try await session.data(from: url)
        let ok = (response as? HTTPURLResponse)?.statusCode == 200
        Logger.api.info("GET \(url.absoluteString, privacy: .public) -> \(ok)")
        return ok
    }

    func fetchItems() async throws -> [Item] {
        var request = URLRequest(url: baseURL.appending(path: "items"))
        request.httpMethod = "GET"
        return try await perform(request)
    }

    func fetchVideos(offset: Int = 0, limit: Int = 20) async throws -> VideoFeedResponse {
        var components = URLComponents(
            url: baseURL.appending(path: "videos"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        return try await perform(request)
    }

    func createItem(timestamp: Date) async throws -> Item {
        var request = URLRequest(url: baseURL.appending(path: "items"))
        request.httpMethod = "POST"
        request.httpBody = try encode(["timestamp": timestamp])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(to: &request)
        return try await perform(request)
    }

    func login(username: String, password: String) async throws -> AuthSession {
        var request = URLRequest(url: baseURL.appending(path: "login"))
        request.httpMethod = "POST"
        request.httpBody = try encode(["username": username, "password": password])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await perform(request)
    }

    func appleLogin(identityToken: String) async throws -> AuthSession {
        var request = URLRequest(url: baseURL.appending(path: "auth/apple"))
        request.httpMethod = "POST"
        request.httpBody = try encode(["identityToken": identityToken])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await perform(request)
    }

    func fetchMap(token: String) async throws -> MapData {
        var request = URLRequest(url: baseURL.appending(path: "map"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await perform(request)
    }

    func deleteItem(id: String) async throws {
        var request = URLRequest(url: baseURL.appending(path: "items/\(id)"))
        request.httpMethod = "DELETE"
        applyAuth(to: &request)
        Logger.api.info("DELETE \(request.url?.absoluteString ?? "?", privacy: .public)")
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200 || http.statusCode == 204 else {
            throw APIError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        Logger.api.info("DELETE \(request.url?.absoluteString ?? "?", privacy: .public) -> \(http.statusCode)")
    }

    private func applyAuth(to request: inout URLRequest) {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SharkAPIKey") as? String,
              !key.isEmpty else { return }
        request.setValue(key, forHTTPHeaderField: "X-API-Key")
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        Logger.api.info("\(request.httpMethod ?? "?", privacy: .public) \(request.url?.absoluteString ?? "?", privacy: .public)")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            Logger.api.error("\(request.httpMethod ?? "?", privacy: .public) \(request.url?.absoluteString ?? "?", privacy: .public) -> no HTTP response")
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            Logger.api.error("\(request.httpMethod ?? "?", privacy: .public) \(request.url?.absoluteString ?? "?", privacy: .public) -> status \(http.statusCode)")
            throw APIError(statusCode: http.statusCode)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let value = try decoder.decode(T.self, from: data)
        Logger.api.info("\(request.httpMethod ?? "?", privacy: .public) \(request.url?.absoluteString ?? "?", privacy: .public) -> status \(http.statusCode)")
        return value
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }
}
