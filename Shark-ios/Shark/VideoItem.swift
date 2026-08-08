//
//  VideoItem.swift
//  Shark
//
//  Created by tiscomacnb2486 on 6/8/2569 BE.
//

import Foundation

struct VideoItem: Identifiable, Codable {
    let id: String
    let fileName: String
    let videoUrl: String
    let username: String
    let caption: String
    let likes: Int
    let comments: Int
    let shares: Int
    let music: String
    let latitude: Double
    let longitude: Double

    var videoURL: URL {
        URL(string: videoUrl)!
    }
}

struct VideoFeedResponse: Codable {
    let videos: [VideoItem]
    let hasMore: Bool
}
