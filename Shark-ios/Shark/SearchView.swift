import AVKit
import SwiftUI

struct SearchView: View {
    @State private var query = ""
    @State private var users: [UserSummary] = []
    @State private var videos: [Video] = []
    @State private var isLoading = false
    @State private var selectedVideo: Video?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if query.isEmpty {
                        discoverHeader
                        userSection
                        videoSection
                    } else if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    } else {
                        if users.isEmpty && videos.isEmpty {
                            Text("No results for \"\(query)\"")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 60)
                        } else {
                            userSection
                            videoSection
                        }
                    }
                }
                .padding(.horizontal)
            }
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Users, videos")
            .onChange(of: query) { _, newValue in
                searchDebounced(newValue)
            }
            .task { await loadExplore() }
            .onDisappear {
                searchTask?.cancel()
            }
        }
        .fullScreenCover(item: $selectedVideo) { video in
            VideoPreviewSheet(video: video)
        }
    }

    private var discoverHeader: some View {
        Text("Discover")
            .font(.title2.bold())
            .padding(.top, 4)
    }

    @ViewBuilder
    private var userSection: some View {
        if !users.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(query.isEmpty ? "Suggested for you" : "Users")
                    .font(.headline)
                ForEach(users) { user in
                    NavigationLink {
                        ProfileView(userId: user.id)
                    } label: {
                        UserRow(user: user)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var videoSection: some View {
        if !videos.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(query.isEmpty ? "Latest videos" : "Videos")
                    .font(.headline)
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3),
                    spacing: 2
                ) {
                    ForEach(videos) { video in
                        Button {
                            selectedVideo = video
                        } label: {
                            AsyncImage(url: video.thumbnailURL) { phase in
                                switch phase {
                                case .success(let image):
                                    image.resizable().aspectRatio(9.0 / 16.0, contentMode: .fill)
                                default:
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.3))
                                        .aspectRatio(9.0 / 16.0, contentMode: .fill)
                                }
                            }
                            .clipped()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func searchDebounced(_ text: String) {
        searchTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            Task { await loadExplore() }
            return
        }
        let task = Task {
            do {
                try await Task.sleep(for: .milliseconds(300))
                isLoading = true
                defer { isLoading = false }
                let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
                let response: SearchResponse = try await APIClient.shared.request(
                    "/api/search?q=\(encoded)"
                )
                guard !Task.isCancelled else { return }
                users = response.users
                videos = response.videos
            } catch {
                if error is CancellationError { return }
                print("Search failed: \(error.localizedDescription)")
            }
        }
        searchTask = task
    }

    private func loadExplore() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response: ExploreResponse = try await APIClient.shared.request("/api/explore")
            users = response.users
            videos = response.videos
        } catch {
            print("Explore load failed: \(error.localizedDescription)")
        }
    }
}

struct UserRow: View {
    @State var user: UserSummary
    @EnvironmentObject private var auth: AuthManager

    var body: some View {
        HStack(spacing: 12) {
            avatarView

            VStack(alignment: .leading, spacing: 2) {
                Text("@\(user.username)")
                    .font(.subheadline.bold())
                Text("\(user.followerCount) followers")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                toggleFollow()
            } label: {
                Text(user.followedByMe ? "Following" : "Follow")
                    .font(.footnote.bold())
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        user.followedByMe ? Color.gray.opacity(0.2) : Color.accentColor,
                        in: Capsule()
                    )
                    .foregroundStyle(user.followedByMe ? Color.primary : Color.white)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var avatarView: some View {
        if let path = user.avatarUrl, let url = URL.shark(path) {
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                } else {
                    letterAvatar
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())
        } else {
            letterAvatar
        }
    }

    private var letterAvatar: some View {
        Circle()
            .fill(Color.accentColor.opacity(0.85))
            .frame(width: 44, height: 44)
            .overlay {
                Text(String(user.username.prefix(1)).uppercased())
                    .font(.headline.bold())
                    .foregroundStyle(.white)
            }
    }

    private func toggleFollow() {
        if auth.requireSignIn() { return }
        Task {
            do {
                let response: FollowResponse = try await APIClient.shared.request(
                    "/api/users/\(user.id)/follow",
                    method: "POST"
                )
                user.followedByMe = response.following
                user.followerCount = response.followerCount
                Haptics.success()
            } catch {
                print("Follow failed: \(error.localizedDescription)")
            }
        }
    }
}

struct VideoPreviewSheet: View {
    let video: Video
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            VideoPlayer(player: player)
                .ignoresSafeArea()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.black.opacity(0.4), in: Circle())
            }
            .padding(.top, 8)
            .padding(.leading, 12)
        }
        .onAppear {
            player.play()
        }
        .onDisappear {
            player.pause()
        }
    }

    private let player: AVPlayer = AVPlayer()

    init(video: Video) {
        self.video = video
        player.replaceCurrentItem(with: AVPlayerItem(url: video.streamURL))
    }
}
