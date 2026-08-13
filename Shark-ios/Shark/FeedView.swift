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

    @StateObject private var feed: FeedModel
    @StateObject private var playerModel = PlayerModel()
    @State private var currentKey: String?

    init(mode: FeedMode) {
        self.mode = mode
        _feed = StateObject(wrappedValue: FeedModel(mode: mode))
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(feed.videos.indices, id: \.self) { index in
                        GeometryReader { cell in
                            let midY = cell.frame(in: .global).midY
                            let centerY = proxy.size.height / 2
                            let isActive = abs(midY - centerY) < centerY

                            VideoCell(video: feed.videos[index], playerModel: playerModel)
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
            .task {
                await feed.loadIfNeeded()
                if let first = feed.videos.first {
                    activate(0)
                }
            }
        }
    }

    private func activate(_ index: Int) {
        let video = feed.videos[index]
        if currentKey != video.key {
            currentKey = video.key
            playerModel.play(video)
        } else {
            playerModel.play()
        }
        let nextIndex = index + 1
        if feed.videos.indices.contains(nextIndex) {
            playerModel.prepare(feed.videos[nextIndex])
        }
    }
}

struct VideoCell: View {
    let video: Video
    @ObservedObject var playerModel: PlayerModel

    @State private var showHeart = false
    @State private var heartScale: CGFloat = 0.4

    var body: some View {
        ZStack {
            Color.black
            PlayerLayerView(player: playerModel.player)
                .clipped()

            VStack {
                Spacer()
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("@\(video.user.username)")
                            .font(.subheadline.bold())
                        if !video.caption.isEmpty {
                            Text(video.caption)
                                .font(.footnote)
                                .lineLimit(4)
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)

                    Spacer()

                    VideoActions(video: video)
                        .padding(.trailing, 12)
                        .padding(.bottom, 10)
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
                .padding(.top, 8)
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
        withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) {
            showHeart = true
            heartScale = 1
        }
        likeVideo()
        Task {
            try? await Task.sleep(for: .seconds(0.9))
            withAnimation(.easeOut(duration: 0.25)) {
                showHeart = false
                heartScale = 0.4
            }
        }
    }

    private func likeVideo() {
        Task {
            do {
                let _: LikeResponse = try await APIClient.shared.request(
                    "/api/videos/\(video.id)/like",
                    method: "POST"
                )
            } catch {
                print("Double-tap like failed: \(error.localizedDescription)")
            }
        }
    }
}

struct FeedRootView: View {
    @State private var mode: FeedMode = .forYou

    var body: some View {
        ZStack {
            FeedView(mode: mode)
                .id(mode)

            VStack {
                HStack(spacing: 0) {
                    feedTab("Following", .following)
                    feedTab("For You", .forYou)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .background(.black.opacity(0.45), in: Capsule())
                .padding(.top, 12)
                Spacer()
            }
        }
        .ignoresSafeArea()
    }

    private func feedTab(_ title: String, _ tab: FeedMode) -> some View {
        Button {
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
