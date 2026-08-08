//
//  MapView.swift
//  Shark
//
//  Created by tiscomacnb2486 on 7/8/2569 BE.
//

import SwiftUI
import MapKit
import os

struct MapView: View {
    enum LoadState {
        case loading
        case loaded
        case failed(String)
    }

    @EnvironmentObject private var auth: AuthStore

    @State private var mapData: MapData?
    @State private var loadState: LoadState = .loading

    var body: some View {
        Group {
            if auth.isAuthenticated {
                content
            } else {
                LoginView()
            }
        }
        .task(id: auth.token) {
            await load()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch loadState {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            VStack(spacing: 12) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 44))
                Text("Couldn't load the map")
                    .font(.headline)
                Text(message)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                Button("Retry") {
                    Task { await load() }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(24)
        case .loaded:
            map
        }
    }

    private var map: some View {
        Map(initialPosition: cameraPosition) {
            if let spots = mapData?.spots {
                ForEach(spots) { spot in
                    Marker(spot.name, coordinate: spot.coordinate)
                }
            }
        }
        .mapStyle(.standard)
        .mapControls {
            MapCompass()
            MapScaleView()
            MapUserLocationButton()
        }
        .ignoresSafeArea(edges: .top)
        .safeAreaInset(edge: .bottom) {
            if let username = auth.username {
                HStack {
                    Text("Logged in as \(username)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Log Out") {
                        auth.logout()
                    }
                    .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.thinMaterial)
            }
        }
    }

    private var cameraPosition: MapCameraPosition {
        guard let center = mapData?.center else {
            return .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 13.7367, longitude: 100.5231),
                span: MKCoordinateSpan(latitudeDelta: 0.25, longitudeDelta: 0.25)
            ))
        }
        return .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude),
            span: MKCoordinateSpan(latitudeDelta: 0.25, longitudeDelta: 0.25)
        ))
    }

    private func load() async {
        guard let token = auth.token else { return }
        loadState = .loading
        do {
            mapData = try await APIClient().fetchMap(token: token)
            loadState = .loaded
            Logger.view.info("Map loaded")
        } catch {
            loadState = .failed(error.localizedDescription)
            Logger.view.error("Failed to load map: \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension MapSpot {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

#Preview {
    MapView()
        .environmentObject(AuthStore())
}
