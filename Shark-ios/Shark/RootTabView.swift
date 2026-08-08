//
//  RootTabView.swift
//  Shark
//
//  Created by tiscomacnb2486 on 7/8/2569 BE.
//

import SwiftUI

struct RootTabView: View {
    @StateObject private var auth = AuthStore()

    var body: some View {
        MapView()
            .environmentObject(auth)
    }
}

#Preview {
    RootTabView()
}
