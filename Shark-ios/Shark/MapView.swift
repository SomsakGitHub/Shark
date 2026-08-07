//
//  MapView.swift
//  Shark
//
//  Created by tiscomacnb2486 on 7/8/2569 BE.
//

import SwiftUI
import MapKit

struct CreatorSpot: Identifiable {
    let id: Int
    let name: String
    let coordinate: CLLocationCoordinate2D
}

struct MapView: View {
    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 13.7367, longitude: 100.5231),
            span: MKCoordinateSpan(latitudeDelta: 0.25, longitudeDelta: 0.25)
        )
    )

    private let spots: [CreatorSpot] = [
        CreatorSpot(id: 1, name: "@somsak", coordinate: CLLocationCoordinate2D(latitude: 13.7510, longitude: 100.4924)),
        CreatorSpot(id: 2, name: "@kate_beat", coordinate: CLLocationCoordinate2D(latitude: 13.7244, longitude: 100.5105)),
        CreatorSpot(id: 3, name: "@proud_pearl", coordinate: CLLocationCoordinate2D(latitude: 13.7461, longitude: 100.5395)),
        CreatorSpot(id: 4, name: "@dao_squad", coordinate: CLLocationCoordinate2D(latitude: 13.8001, longitude: 100.5501)),
        CreatorSpot(id: 5, name: "@bank_bounce", coordinate: CLLocationCoordinate2D(latitude: 13.7279, longitude: 100.5342)),
    ]

    var body: some View {
        Map(position: $position) {
            ForEach(spots) { spot in
                Annotation(spot.name, coordinate: spot.coordinate) {
                    spotMarker(spot)
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
    }

    private func spotMarker(_ spot: CreatorSpot) -> some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(Color.pink)
                    .frame(width: 34, height: 34)
                Text(initial(spot.name))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
            }
            Text(spot.name)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.thinMaterial, in: Capsule())
        }
    }

    private func initial(_ username: String) -> String {
        let trimmed = username.hasPrefix("@") ? String(username.dropFirst()) : username
        return String(trimmed.prefix(1)).uppercased()
    }
}

#Preview {
    MapView()
}
