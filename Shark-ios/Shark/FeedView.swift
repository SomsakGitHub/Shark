import AVKit
import SwiftUI

struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerUIView {
        PlayerLayerUIView(player: player)
    }

    func updateUIView(_ uiView: PlayerLayerUIView, context: Context) {
        uiView.update(player: player)
    }
}

final class PlayerLayerUIView: UIView {
    private let playerLayer = AVPlayerLayer()

    init(player: AVPlayer) {
        super.init(frame: .zero)
        backgroundColor = .black
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.player = player
        layer.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }

    func update(player: AVPlayer) {
        playerLayer.player = player
    }
}

struct FeedView: View {
    let mode: FeedMode
    var onGoToSearch: (() -> Void)? = nil

    @StateObject private var feed: FeedModel
    @StateObject private var playerModel = PlayerModel()
    @State private var currentKey: String?
    @State private var currentIndex = 0
    @State private var profileTarget: ProfileTarget?
    @Environment(\.scenePhase) private var scenePhase

    init(mode: FeedMode, onGoToSearch: (() -> Void)? = nil) {
        self.mode = mode
        self.onGoToSearch = onGoToSearch
        _feed = StateObject(wrappedValue: FeedModel(mode: mode))
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(feed.videos.indices, id: \.self) { index in
                            GeometryReader { cell in
                                let midY = cell.frame(in: .global).midY
                                let centerY = proxy.size.height / 2
                                let isActive = abs(midY - centerY) < centerY

                                VideoCell(video: feed.videos[index], playerModel: playerModel) {
                                    profileTarget = ProfileTarget(id: feed.videos[index].user.id)
                                } onLikeChanged: { liked, count in
                                    feed.applyLike(
                                        videoID: feed.videos[index].id,
                                        liked: liked,
                                        likeCount: count
                                    )
                                } onCommentCountChanged: { count in
                                    feed.applyCommentCount(
                                        videoID: feed.videos[index].id,
                                        count: count
                                    )
                                }
                                .onChange(of: isActive) { _, active in
                                    if active {
                                        activate(index)
                                    } else {
                                        playerModel.pause()
                                    }
                                }
                            }
                            .frame(height: proxy.size.height)
                            .onAppear {
                                if index >= feed.videos.count - 2 {
                                    Task { await feed.loadMore() }
                                }
                            }
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .ignoresSafeArea()
                .refreshable {
                    await feed.refresh()
                    if !feed.videos.isEmpty {
                        let target = min(currentIndex, feed.videos.count - 1)
                        activate(target)
                    }
                }
                .task {
                    await feed.loadIfNeeded()
                    if !feed.videos.isEmpty {
                        activate(0)
                    }
                }
                .onAppear {
                    if !feed.videos.isEmpty {
                        activate(min(currentIndex, feed.videos.count - 1))
                    }
                }
                .onDisappear {
                    playerModel.pause()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active {
                        playerModel.pause()
                    } else if !feed.videos.isEmpty {
                        activate(min(currentIndex, feed.videos.count - 1))
                    }
                }

                if mode == .following && feed.videos.isEmpty && !feed.isLoading {
                    followingEmptyState
                }
            }
            .sheet(item: $profileTarget) { target in
                ProfileView(userId: target.id)
            }
            .alert("Couldn't load feed", isPresented: Binding(
                get: { feed.errorMessage != nil },
                set: { if !$0 { feed.errorMessage = nil } }
            )) {
                Button("Retry") {
                    Task { await feed.loadIfNeeded() }
                }
                Button("Cancel", role: .cancel) {
                    feed.errorMessage = nil
                }
            } message: {
                Text(feed.errorMessage ?? "")
            }
        }
    }

    private var followingEmptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Nothing here yet")
                .font(.title3.bold())
                .foregroundStyle(.white)
            Text("Follow people to see their videos in this feed.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let onGoToSearch {
                Button(action: onGoToSearch) {
                    Text("Find People")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(.white, in: Capsule())
                        .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 32)
    }

    private func activate(_ index: Int) {
        currentIndex = index
        let video = feed.videos[index]
        if currentKey != video.key {
            currentKey = video.key
            playerModel.play(video)
        } else {
            playerModel.play()
        }
        preloadWindow(around: index)
    }

    private func preloadWindow(around index: Int) {
        for offset in 1...2 {
            let next = index + offset
            if feed.videos.indices.contains(next) {
                playerModel.cache(feed.videos[next])
            }
        }
    }
}

private struct ProfileTarget: Identifiable {
    let id: String
}

struct VideoCell: View {
    let video: Video
    @ObservedObject var playerModel: PlayerModel
    var onUserTap: (() -> Void)? = nil
    var onLikeChanged: ((Bool, Int) -> Void)? = nil
    var onCommentCountChanged: ((Int) -> Void)? = nil

    @State private var showHeart = false
    @State private var heartScale: CGFloat = 0.4
    @State private var liked: Bool
    @State private var likeCount: Int
    @EnvironmentObject private var auth: AuthManager

    init(
        video: Video,
        playerModel: PlayerModel,
        onUserTap: (() -> Void)? = nil,
        onLikeChanged: ((Bool, Int) -> Void)? = nil,
        onCommentCountChanged: ((Int) -> Void)? = nil
    ) {
        self.video = video
        self.playerModel = playerModel
        self.onUserTap = onUserTap
        self.onLikeChanged = onLikeChanged
        self.onCommentCountChanged = onCommentCountChanged
        _liked = State(initialValue: video.likedByMe)
        _likeCount = State(initialValue: video.likeCount)
    }

    var body: some View {
        ZStack {
            Color.black
            PlayerLayerView(player: playerModel.player)
                .clipped()

            if playerModel.isLoading {
                ProgressView()
                    .tint(.white)
            }

            VStack {
                Spacer()
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            AvatarView(url: video.user.avatarUrl, username: video.user.username, size: 30)
                            Button {
                                onUserTap?()
                            } label: {
                                Text("@\(video.user.username)")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)
                        }
                        if !video.caption.isEmpty {
                            Text(video.caption)
                                .font(.footnote)
                                .lineLimit(4)
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 88)

                    Spacer()

                    VideoActions(
                        video: video,
                        liked: $liked,
                        likeCount: $likeCount,
                        onLikeChanged: onLikeChanged,
                        onCommentCountChanged: onCommentCountChanged
                    )
                        .padding(.trailing, 12)
                        .padding(.bottom, 88)
                }
            }
            .background(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.6)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            if showHeart {
                Image(systemName: "heart.fill")
                    .font(.system(size: 90))
                    .foregroundStyle(.white)
                    .shadow(radius: 12)
                    .scaleEffect(heartScale)
                    .opacity(showHeart ? 1 : 0)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .topTrailing) {
            muteButton
                .padding(.top, 56)
                .padding(.trailing, 12)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            triggerLikeHeart()
        }
        .onTapGesture(count: 1) {
            playerModel.togglePlay()
        }
        .ignoresSafeArea()
    }

    private var muteButton: some View {
        Button {
            playerModel.toggleMute()
        } label: {
            Image(systemName: playerModel.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .padding(10)
                .background(.black.opacity(0.35), in: Circle())
        }
    }

    private func triggerLikeHeart() {
        guard !showHeart else { return }
        if auth.requireSignIn() { return }
        Haptics.impact(.rigid)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) {
            showHeart = true
            heartScale = 1
        }
        let previousLiked = liked
        let previousCount = likeCount
        withAnimation(.spring(response: 0.4)) {
            liked.toggle()
            likeCount += liked ? 1 : -1
        }
        Task {
            do {
                let response: LikeResponse = try await APIClient.shared.request(
                    "/api/videos/\(video.id)/like",
                    method: "POST"
                )
                liked = response.liked
                likeCount = response.likeCount
                onLikeChanged?(response.liked, response.likeCount)
            } catch {
                withAnimation(.spring(response: 0.4)) {
                    liked = previousLiked
                    likeCount = previousCount
                }
                print("Double-tap like failed: \(error.localizedDescription)")
            }
        }
        Task {
            try? await Task.sleep(for: .seconds(0.9))
            withAnimation(.easeOut(duration: 0.25)) {
                showHeart = false
                heartScale = 0.4
            }
        }
    }
}

struct FeedRootView: View {
    var onGoToSearch: (() -> Void)? = nil
    @State private var mode: FeedMode = .forYou
    @EnvironmentObject private var auth: AuthManager

    var body: some View {
        ZStack {
            FeedView(mode: mode, onGoToSearch: onGoToSearch)
                .id(mode)

            VStack {
                HStack(spacing: 0) {
                    feedTab("Following", .following)
                    feedTab("For You", .forYou)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .background(.black.opacity(0.45), in: Capsule())
                .padding(.top, 54)
                Spacer()
            }
        }
        .ignoresSafeArea()
    }

    private func feedTab(_ title: String, _ tab: FeedMode) -> some View {
        Button {
            if tab == .following && auth.requireSignIn() { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                mode = tab
            }
        } label: {
            Text(title)
                .font(.subheadline.bold())
                .foregroundStyle(mode == tab ? .black : .white)
                .padding(.horizontal, 18)
                .padding(.vertical, 6)
                .background(mode == tab ? Color.white : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
