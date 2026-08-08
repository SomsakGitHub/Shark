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
    @EnvironmentObject private var locationManager: LocationManager

    @State private var mapData: MapData?
    @State private var loadState: LoadState = .loading
    @State private var position: MapCameraPosition = .region(defaultRegion)
    @State private var hasCenteredOnUser = false

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
        Map(position: $position) {
            if let spots = mapData?.spots {
                ForEach(spots) { spot in
                    Marker(spot.name, coordinate: spot.coordinate)
                }
            }
            UserAnnotation()
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
        .onChange(of: locationKey) {
            centerOnUserIfNeeded()
        }
    }

    private var locationKey: String? {
        guard let coordinate = locationManager.location?.coordinate else { return nil }
        return String(format: "%.5f,%.5f", coordinate.latitude, coordinate.longitude)
    }

    private func centerOnUserIfNeeded() {
        guard !hasCenteredOnUser,
              let coordinate = locationManager.location?.coordinate else { return }
        hasCenteredOnUser = true
        position = .region(MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        ))
    }

    private static var defaultRegion: MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 13.7367, longitude: 100.5231),
            span: MKCoordinateSpan(latitudeDelta: 0.25, longitudeDelta: 0.25)
        )
    }

    private func load() async {
        guard let token = auth.token else { return }
        loadState = .loading
        do {
            mapData = try await APIClient().fetchMap(token: token)
            if !hasCenteredOnUser, let center = mapData?.center {
                position = .region(MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude),
                    span: MKCoordinateSpan(latitudeDelta: 0.25, longitudeDelta: 0.25)
                ))
            }
            loadState = .loaded
            Logger.view.info("Map loaded")
        } catch let error as APIError where error.statusCode == 401 {
            auth.logout()
            Logger.view.info("Session expired, logged out")
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
        .environmentObject(LocationManager())
}
