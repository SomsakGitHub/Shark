//
//  SharkApp.swift
//  Shark
//
//  Created by tiscomacnb2486 on 5/8/2569 BE.
//

import SwiftUI
import AVFoundation

@main
struct SharkApp: App {
    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback)
    }

    var body: some Scene {
        WindowGroup {
            VideoFeedView()
        }
    }
}
