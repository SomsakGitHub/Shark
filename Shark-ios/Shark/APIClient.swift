import Foundation
import Security

enum SharkConfig {
    static var baseURL: URL {
        if let raw = ProcessInfo.processInfo.environment["SHARK_API_URL"],
           let url = URL(string: raw) {
            return url
        }
        return URL(string: "https://shark-api.js6ctz7gtj.workers.dev")!
    }
}

enum APIError: LocalizedError {
    case invalidResponse
    case unauthorized
    case server(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .unauthorized:
            return "Session expired, please sign in again"
        case .server(let code, let message):
            return message.isEmpty ? "Server error (\(code))" : message
        }
    }
}

enum AuthStore {
    private static let service = "com.somsak.Shark"
    private static let account = "auth-token"

    static func save(_ token: String) {
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static var token: String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate {
    var onProgress: ((Double) -> Void)?

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        let fraction = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        onProgress?(fraction)
    }
}

final class APIClient {
    static let shared = APIClient()
    private let decoder = JSONDecoder.shark()

    private init() {}

    func request<T: Decodable>(
        _ path: String,
        method: String = "GET",
        body: Data? = nil,
        authenticated: Bool = true
    ) async throws -> T {
        var request = URLRequest(url: SharkConfig.baseURL.appending(path: path))
        request.httpMethod = method
        if authenticated, let token = AuthStore.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? decoder.decode(ErrorResponse.self, from: data))?.error ?? ""
            if http.statusCode == 401 {
                AuthStore.clear()
                throw APIError.unauthorized
            }
            throw APIError.server(http.statusCode, message)
        }
        return try decoder.decode(T.self, from: data)
    }

    func uploadVideo(key: String, data: Data, progress: ((Double) -> Void)? = nil) async throws -> String {
        var request = URLRequest(url: SharkConfig.baseURL.appending(path: "/api/upload/\(key)"))
        request.httpMethod = "PUT"
        if let token = AuthStore.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("video/mp4", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        let delegate = UploadProgressDelegate()
        delegate.onProgress = progress
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: .main)
        defer { session.finishTasksAndInvalidate() }

        let (responseData, response) = try await session.upload(for: request, from: data)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw APIError.invalidResponse
        }
        struct UploadResponse: Codable { let key: String }
        return try decoder.decode(UploadResponse.self, from: responseData).key
    }

    func uploadThumbnail(key: String, data: Data) async throws {
        var request = URLRequest(url: SharkConfig.baseURL.appending(path: "/api/thumbnail/\(key)"))
        request.httpMethod = "PUT"
        if let token = AuthStore.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw APIError.invalidResponse
        }
    }
}
