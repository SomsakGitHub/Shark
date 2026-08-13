import Foundation

struct APIUser: Codable, Identifiable, Hashable {
    let id: String
    let username: String
    let email: String?
    let avatarUrl: String?
}

struct Video: Codable, Identifiable, Hashable {
    let id: String
    let key: String
    let caption: String
    let createdAt: Date
    let user: UserRef
    var likeCount: Int
    var commentCount: Int
    var likedByMe: Bool

    struct UserRef: Codable, Hashable {
        let id: String
        let username: String
        let avatarUrl: String?
    }

    var streamURL: URL {
        SharkConfig.baseURL.appending(path: "/api/file/\(key)")
    }

    var thumbnailURL: URL {
        SharkConfig.baseURL.appending(path: "/api/thumb/\(key)")
    }
}

struct Comment: Codable, Identifiable, Hashable {
    let id: String
    let text: String
    let createdAt: Date
    let user: Video.UserRef
}

struct FeedResponse: Codable {
    let videos: [Video]
    let nextCursor: String?
}

struct CommentsResponse: Codable {
    let comments: [Comment]
}

struct LikeResponse: Codable {
    let liked: Bool
    let likeCount: Int
}

struct AuthResponse: Codable {
    let token: String
    let user: APIUser
}

struct MeResponse: Codable {
    let user: APIUser
}

struct VideoCreateResponse: Codable {
    let video: Video
}

struct ProfileResponse: Codable {
    let user: APIUser
    let counts: Counts
    let videos: [Video]

    struct Counts: Codable {
        let videoCount: Int
        let followerCount: Int
        let followingCount: Int
    }
}

struct ErrorResponse: Codable {
    let error: String
}

struct VideoCreateRequest: Encodable {
    let key: String
    let caption: String
}

extension JSONDecoder {
    static func shark() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = SharkDateFormatter.shared.date(from: raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date string \(raw)"
            )
        }
        return decoder
    }
}

enum SharkDateFormatter {
    static let shared: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

extension JSONEncoder {
    static func shark() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }
}
