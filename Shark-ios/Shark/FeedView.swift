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
    @StateObject private var feed = FeedModel()
    @StateObject private var playerModel = PlayerModel()
    @State private var currentKey: String?

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(feed.videos.indices, id: \.self) { index in
                        GeometryReader { cell in
                            let midY = cell.frame(in: .global).midY
                            let centerY = proxy.size.height / 2
                            let isActive = abs(midY - centerY) < centerY

                            VideoCell(video: feed.videos[index], player: playerModel.player)
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
            playerModel.replace(with: video.streamURL)
        }
        playerModel.play()
    }
}

struct VideoCell: View {
    let video: Video
    let player: AVPlayer

    var body: some View {
        ZStack {
            Color.black
            PlayerLayerView(player: player)
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
        }
        .ignoresSafeArea()
    }
}
