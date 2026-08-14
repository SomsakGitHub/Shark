import SwiftUI

struct ProfileView: View {
    var userId: String?

    @EnvironmentObject private var auth: AuthManager
    @State private var profile: ProfileResponse?
    @State private var isLoading = false
    @State private var isFollowing = false
    @State private var showEditProfile = false
    @State private var videoToDelete: Video?
    @State private var listMode: UserListMode?
    @State private var confirmSignOut = false

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
                        AvatarView(url: user.avatarUrl, username: user.username, size: 96)

                        Text("@\(user.username)")
                            .font(.title3.bold())

                        if let bio = user.bio, !bio.isEmpty {
                            Text(bio)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }

                        if let counts = profile?.counts {
                            HStack(spacing: 32) {
                                stat(value: counts.videoCount, label: "Videos")
                                Button {
                                    guard auth.isSignedIn else {
                                        auth.showSignInPrompt = true
                                        return
                                    }
                                    listMode = .followers(profileId)
                                } label: {
                                    stat(value: counts.followerCount, label: "Followers")
                                }
                                .buttonStyle(.plain)
                                Button {
                                    guard auth.isSignedIn else {
                                        auth.showSignInPrompt = true
                                        return
                                    }
                                    listMode = .following(profileId)
                                } label: {
                                    stat(value: counts.followingCount, label: "Following")
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if isOwnProfile {
                            editProfileButton
                        } else {
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
                                    .contextMenu {
                                        if isOwnProfile {
                                            Button(role: .destructive) {
                                                videoToDelete = video
                                            } label: {
                                                Label("Delete Video", systemImage: "trash")
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
                        Button("Sign Out", role: .destructive) {
                            confirmSignOut = true
                        }
                    }
                }
            }
            .refreshable { await load() }
            .task { await load() }
            .onChange(of: userId) { _, _ in
                Task { await load() }
            }
            .sheet(isPresented: $showEditProfile) {
                EditProfileView(user: user) {
                    Task { await load() }
                }
            }
            .alert(item: $videoToDelete) { video in
                Alert(
                    title: Text("Delete video?"),
                    message: Text("This video will be removed permanently."),
                    primaryButton: .destructive(Text("Delete")) {
                        Task { await deleteVideo(video) }
                    },
                    secondaryButton: .cancel()
                )
            }
            .sheet(item: $listMode) { mode in
                UserListView(mode: mode)
            }
            .alert("Sign Out?", isPresented: $confirmSignOut) {
                Button("Sign Out", role: .destructive) { auth.signOut() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You'll need to sign in again to continue.")
            }
        }
    }

    private var editProfileButton: some View {
        Button {
            showEditProfile = true
        } label: {
            Text("Edit Profile")
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.gray.opacity(0.2), in: Capsule())
                .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 48)
    }

    private var followButton: some View {
        Button {
            if auth.requireSignIn() { return }
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

    private func deleteVideo(_ video: Video) async {
        do {
            let _: DeletedResponse = try await APIClient.shared.request(
                "/api/videos/\(video.id)",
                method: "DELETE"
            )
            await load()
        } catch {
            print("Delete video failed: \(error.localizedDescription)")
        }
    }
}
