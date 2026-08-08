//
//  SharkApp.swift
//  Shark
//
//  Created by tiscomacnb2486 on 5/8/2569 BE.
//

import SwiftUI
import AVFoundation
import UIKit
import CoreLocation

@main
struct SharkApp: App {
    @StateObject private var locationManager = LocationManager()
    @State private var showDeniedAlert = false
    @Environment(\.scenePhase) private var scenePhase

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback)
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(locationManager)
                .onAppear {
                    presentForCurrentLocationStatus()
                }
                .onChange(of: locationManager.authorizationStatus) {
                    presentForCurrentLocationStatus()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        presentForCurrentLocationStatus()
                    }
                }
                .alert("Location permission needed", isPresented: $showDeniedAlert) {
                    Button("Open Settings") {
                        openSettings()
                    }
                    Button("Not Now", role: .cancel) {}
                } message: {
                    Text("Shark uses your location to show you on the map. Enable location access in Settings.")
                }
        }
    }

    private func presentForCurrentLocationStatus() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            break
        default:
            showDeniedAlert = true
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}
