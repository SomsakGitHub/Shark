//
//  APIClient.swift
//  Shark
//
//  Created by tiscomacnb2486 on 5/8/2569 BE.
//

import Foundation

enum APIConfig {
    #if DEBUG
    static let baseURL = URL(string: "http://localhost:8080")!
    #else
    static let baseURL = URL(string: "https://shark-api.onrender.com")!
    #endif
}

struct APIError: LocalizedError {
    let statusCode: Int

    var errorDescription: String? {
        "API error (status \(statusCode))"
    }
}

struct APIClient {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = APIConfig.baseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func health() async throws -> Bool {
        let (_, response) = try await session.data(from: baseURL.appending(path: "health"))
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    func fetchItems() async throws -> [Item] {
        var request = URLRequest(url: baseURL.appending(path: "items"))
        request.httpMethod = "GET"
        return try await perform(request)
    }

    func createItem(timestamp: Date) async throws -> Item {
        var request = URLRequest(url: baseURL.appending(path: "items"))
        request.httpMethod = "POST"
        request.httpBody = try encode(["timestamp": timestamp])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await perform(request)
    }

    func deleteItem(id: String) async throws {
        var request = URLRequest(url: baseURL.appending(path: "items/\(id)"))
        request.httpMethod = "DELETE"
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200 || http.statusCode == 204 else {
            throw APIError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1)
        }
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError(statusCode: http.statusCode)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }
}
