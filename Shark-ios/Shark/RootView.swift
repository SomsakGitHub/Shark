import SwiftUI

struct RootView: View {
    @EnvironmentObject private var auth: AuthManager

    var body: some View {
        Group {
            if auth.isSignedIn {
                AppTabView()
            } else {
                SignInView()
            }
        }
    }
}
