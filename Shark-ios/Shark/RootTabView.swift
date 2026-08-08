//
//  RootTabView.swift
//  Shark
//
//  Created by tiscomacnb2486 on 7/8/2569 BE.
//

import SwiftUI

struct RootTabView: View {
    enum Tab: Hashable {
        case feed
        case map
    }

    @StateObject private var auth = AuthStore()
    @State private var selection: Tab = .feed

    var body: some View {
        TabView(selection: $selection) {
            VideoFeedView()
                .tabItem {
                    Label("Feed", systemImage: "play.rectangle")
                }
                .tag(Tab.feed)

            MapView()
                .environmentObject(auth)
                .tabItem {
                    Label("Map", systemImage: "map")
                }
                .tag(Tab.map)
        }
    }
}

#Preview {
    RootTabView()
}
