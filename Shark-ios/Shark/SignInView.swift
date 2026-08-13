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

struct AppTabView: View {
    var body: some View {
        TabView {
            FeedView()
                .tabItem { Label("Home", systemImage: "house.fill") }
            UploadView()
                .tabItem { Label("Upload", systemImage: "plus.app.fill") }
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.fill") }
        }
    }
}
