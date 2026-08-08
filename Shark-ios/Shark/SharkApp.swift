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
    @StateObject private var locationManager = LocationManager()

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback)
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(locationManager)
                .task {
                    locationManager.requestAuthorization()
                }
        }
    }
}
