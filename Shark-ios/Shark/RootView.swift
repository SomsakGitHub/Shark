import SwiftUI

struct RootView: View {
    @EnvironmentObject private var auth: AuthManager
    @StateObject private var deepLink = DeepLinkHandler()

    var body: some View {
        AppTabView()
            .preferredColorScheme(.dark)
            .onOpenURL { url in
                guard auth.isSignedIn else { return }
                deepLink.handle(url)
            }
            .fullScreenCover(item: $deepLink.pendingVideo) { video in
                VideoPreviewSheet(video: video)
            }
            .sheet(isPresented: $auth.showSignInPrompt) {
                SignInView()
            }
    }
}
