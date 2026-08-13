import SwiftUI

struct RootView: View {
    @EnvironmentObject private var auth: AuthManager
    @StateObject private var deepLink = DeepLinkHandler()

    var body: some View {
        Group {
            if auth.isSignedIn {
                AppTabView()
            } else {
                SignInView()
            }
        }
        .onOpenURL { url in
            guard auth.isSignedIn else { return }
            deepLink.handle(url)
        }
        .fullScreenCover(item: $deepLink.pendingVideo) { video in
            VideoPreviewSheet(video: video)
        }
    }
}
