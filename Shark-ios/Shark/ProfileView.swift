import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var auth: AuthManager
    @State private var profile: ProfileResponse?
    @State private var isLoading = false

    private var user: APIUser? {
        profile?.user ?? auth.user
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let user {
                    VStack(spacing: 16) {
                        Circle()
                            .fill(Color.accentColor.opacity(0.85))
                            .frame(width: 96, height: 96)
                            .overlay {
                                Text(String(user.username.prefix(1)).uppercased())
                                    .font(.system(size: 40, weight: .bold))
                                    .foregroundStyle(.white)
                            }

                        Text("@\(user.username)")
                            .font(.title3.bold())

                        if let counts = profile?.counts {
                            HStack(spacing: 32) {
                                stat(value: counts.videoCount, label: "Videos")
                                stat(value: counts.followerCount, label: "Followers")
                                stat(value: counts.followingCount, label: "Following")
                            }
                        }

                        if let videos = profile?.videos, !videos.isEmpty {
                            LazyVGrid(
                                columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3),
                                spacing: 2
                            ) {
                                ForEach(videos) { video in
                                    AsyncImage(url: video.thumbnailURL) { phase in
                                        switch phase {
                                        case .success(let image):
                                            image
                                                .resizable()
                                                .aspectRatio(9.0 / 16.0, contentMode: .fit)
                                        default:
                                            Rectangle()
                                                .fill(Color.gray.opacity(0.3))
                                                .aspectRatio(9.0 / 16.0, contentMode: .fit)
                                                .overlay {
                                                    Image(systemName: "play.fill")
                                                        .foregroundStyle(.white)
                                                }
                                        }
                                    }
                                }
                            }
                            .padding(.top, 8)
                        } else if !isLoading {
                            Text("No videos yet")
                                .foregroundStyle(.secondary)
                                .padding(.top, 24)
                        }
                    }
                    .padding(.horizontal)
                } else {
                    ProgressView()
                        .padding(.top, 80)
                }
            }
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sign Out") { auth.signOut() }
                }
            }
            .task { await load() }
        }
    }

    private func stat(value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.headline)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func load() async {
        guard let id = auth.user?.id else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            profile = try await APIClient.shared.request("/api/users/\(id)")
        } catch {
            print("Profile load failed: \(error.localizedDescription)")
        }
    }
}
