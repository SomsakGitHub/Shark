import SwiftUI

struct RootView: View {
    @EnvironmentObject private var auth: AuthManager
    @StateObject private var deepLink = DeepLinkHandler()
    @State private var showSplash = true

    var body: some View {
        AppTabView()
            .preferredColorScheme(.dark)
            .onOpenURL { url in
                deepLink.handle(url)
            }
            .fullScreenCover(item: $deepLink.pendingVideo) { video in
                VideoPreviewSheet(video: video)
            }
            .sheet(isPresented: $auth.showSignInPrompt) {
                SignInView()
            }
            .overlay {
                if showSplash {
                    SplashView {
                        showSplash = false
                    }
                    .transition(.opacity)
                }
            }
    }
}
