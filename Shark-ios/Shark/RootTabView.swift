//
//  RootTabView.swift
//  Shark
//
//  Created by tiscomacnb2486 on 7/8/2569 BE.
//

import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            VideoFeedView()
                .tabItem {
                    Label("Feed", systemImage: "play.rectangle")
                }
            MapView()
                .tabItem {
                    Label("Map", systemImage: "map")
                }
        }
    }
}

#Preview {
    RootTabView()
}
