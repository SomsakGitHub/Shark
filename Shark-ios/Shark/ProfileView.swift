import SwiftUI

struct ProfileView: View {
    var userId: String?

    @EnvironmentObject private var auth: AuthManager
    @State private var profile: ProfileResponse?
    @State private var isLoading = false
    @State private var isFollowing = false

    private var user: APIUser? {
        profile?.user ?? auth.user
    }

    private var profileId: String {
        userId ?? auth.user?.id ?? ""
    }

    private var isOwnProfile: Bool {
        userId == nil || userId == auth.user?.id
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

                        if !isOwnProfile {
                            followButton
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
            .navigationTitle(isOwnProfile ? "Profile" : "@\(user?.username ?? "")")
            .toolbar {
                if isOwnProfile {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Sign Out") { auth.signOut() }
                    }
                }
            }
            .task { await load() }
            .onChange(of: userId) { _, _ in
                Task { await load() }
            }
        }
    }

    private var followButton: some View {
        Button {
            toggleFollow()
        } label: {
            Text(isFollowing ? "Following" : "Follow")
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    isFollowing ? Color.gray.opacity(0.2) : Color.accentColor,
                    in: Capsule()
                )
                .foregroundStyle(isFollowing ? Color.primary : Color.white)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 48)
    }

    private func stat(value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.headline)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func load() async {
        guard !profileId.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let response: ProfileResponse = try await APIClient.shared.request("/api/users/\(profileId)")
            profile = response
            isFollowing = response.counts.followedByMe
        } catch {
            print("Profile load failed: \(error.localizedDescription)")
        }
    }

    private func toggleFollow() {
        Task {
            do {
                let response: FollowResponse = try await APIClient.shared.request(
                    "/api/users/\(profileId)/follow",
                    method: "POST"
                )
                isFollowing = response.following
                profile?.counts.followerCount = response.followerCount
            } catch {
                print("Follow failed: \(error.localizedDescription)")
            }
        }
    }
}
