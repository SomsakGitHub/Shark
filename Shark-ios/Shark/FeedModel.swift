import AVFoundation
import Combine
import Foundation

@MainActor
final class FeedModel: ObservableObject {
    @Published private(set) var videos: [Video] = []
    @Published private(set) var isLoading = false

    private let mode: FeedMode
    private var nextCursor: String?
    private var hasLoaded = false

    init(mode: FeedMode = .forYou) {
        self.mode = mode
    }

    func loadIfNeeded() async {
        guard !hasLoaded, !isLoading else { return }
        await loadMore()
    }

    func refresh() async {
        guard !isLoading else { return }
        videos = []
        nextCursor = nil
        hasLoaded = false
        await loadMore()
    }

    func loadMore() async {
        guard !isLoading else { return }
        if nextCursor == "" { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let base = mode == .following ? "/api/videos/following" : "/api/videos"
            let path: String
            if let cursor = nextCursor {
                let encoded = cursor.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cursor
                path = "\(base)?cursor=\(encoded)"
            } else {
                path = base
            }
            let response: FeedResponse = try await APIClient.shared.request(path)
            videos.append(contentsOf: response.videos)
            nextCursor = response.nextCursor
            hasLoaded = true
        } catch {
            print("Feed load error: \(error.localizedDescription)")
        }
    }
}

enum FeedMode: Hashable {
    case forYou
    case following
}

@MainActor
final class PlayerModel: ObservableObject {
    let player = AVPlayer()
    @Published var isMuted = false {
        didSet { player.isMuted = isMuted }
    }
    @Published private(set) var isPlaying = false

    private var preparedItem: AVPlayerItem?
    private var preparedKey: String?
    private var endObserver: NSObjectProtocol?

    init() {
        player.actionAtItemEnd = .none
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self,
                  let item = note.object as? AVPlayerItem,
                  item === self.player.currentItem else { return }
            self.player.seek(to: .zero)
            self.player.play()
        }
    }

    deinit {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }

    func play() {
        player.play()
        isPlaying = true
    }

    func play(_ video: Video) {
        let url = video.streamURL.absoluteString
        if let preparedItem, preparedKey == url {
            player.replaceCurrentItem(with: preparedItem)
        } else {
            let item = AVPlayerItem(url: video.streamURL)
            item.preferredForwardBufferDuration = 4
            player.replaceCurrentItem(with: item)
        }
        preparedItem = nil
        preparedKey = nil
        player.isMuted = isMuted
        player.play()
        isPlaying = true
    }

    func prepare(_ video: Video) {
        let asset = AVURLAsset(url: video.streamURL)
        preparedKey = video.streamURL.absoluteString
        preparedItem = AVPlayerItem(asset: asset)
        preparedItem?.preferredForwardBufferDuration = 4
        Task {
            _ = try? await asset.load(.isPlayable)
        }
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func togglePlay() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func toggleMute() {
        isMuted.toggle()
    }
}
