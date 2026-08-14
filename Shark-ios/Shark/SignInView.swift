import AuthenticationServices
import SwiftUI

struct SignInView: View {
    @EnvironmentObject private var auth: AuthManager

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                Image(systemName: "fish.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.white)

                Text("Shark")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(.white)

                Text("Videos worth scrolling for")
                    .foregroundStyle(.gray)

                Spacer()

                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    auth.handleSignIn(result)
                }
                .frame(height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
            }
        }
    }
}

struct SignInPromptView: View {
    let message: String
    @EnvironmentObject private var auth: AuthManager

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "fish.fill")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                auth.handleSignIn(result)
            }
            .frame(height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 40)
            .padding(.bottom, 32)
        }
        .padding()
    }
}

struct AppTabView: View {
    @State private var selectedTab = 0
    @EnvironmentObject private var auth: AuthManager

    var body: some View {
        TabView(selection: $selectedTab) {
            FeedRootView(onGoToSearch: { selectedTab = 1 })
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(0)
            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(1)
            Group {
                if auth.isSignedIn {
                    UploadView()
                } else {
                    SignInPromptView(message: "Sign in to upload your videos")
                }
            }
            .tabItem { Label("Upload", systemImage: "plus.app.fill") }
            .tag(2)
            Group {
                if auth.isSignedIn {
                    ProfileView()
                } else {
                    SignInPromptView(message: "Sign in to manage your profile")
                }
            }
            .tabItem { Label("Profile", systemImage: "person.fill") }
            .tag(3)
        }
        .onChange(of: selectedTab) { _, newValue in
            if newValue != 0 {
                NotificationCenter.default.post(name: .sharkPauseFeedPlayback, object: nil)
            }
        }
    }
}
