//
//  VideoItem.swift
//  Shark
//
//  Created by tiscomacnb2486 on 6/8/2569 BE.
//

import Foundation

struct VideoItem: Identifiable {
    let id: String
    let fileName: String
    let username: String
    let caption: String
    let likes: Int
    let comments: Int
    let shares: Int
    let music: String

    var videoURL: URL {
        URL(string: "\(APIConfig.baseURL)/videos/\(fileName).mp4")!
    }

    static let mockData: [VideoItem] = [
        VideoItem(
            id: "1",
            fileName: "fireworks",
            username: "@somsak",
            caption: "Happy New Year from Bangkok",
            likes: 123400,
            comments: 2340,
            shares: 890,
            music: "original sound - som"
        ),
        VideoItem(
            id: "2",
            fileName: "oneDancing",
            username: "@kate_beat",
            caption: "Day one of dancing",
            likes: 45200,
            comments: 670,
            shares: 250,
            music: "sure thing - miguel"
        ),
        VideoItem(
            id: "3",
            fileName: "selfie",
            username: "@proud_pearl",
            caption: "Golden hour selfie",
            likes: 89000,
            comments: 1120,
            shares: 340,
            music: "sunset drive - playlist"
        ),
        VideoItem(
            id: "4",
            fileName: "twoDancing",
            username: "@dao_squad",
            caption: "Us after two coffee shots",
            likes: 67000,
            comments: 890,
            shares: 410,
            music: "Snooze - sza"
        ),
        VideoItem(
            id: "5",
            fileName: "threeDancing",
            username: "@bank_bounce",
            caption: "The crew never misses",
            likes: 215000,
            comments: 3200,
            shares: 1450,
            music: "Gata Only - FloyyMenor"
        ),
    ]
}
