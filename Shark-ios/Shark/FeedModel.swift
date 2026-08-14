import AVFoundation
import Combine
import Foundation
import UIKit

@MainActor
final class FeedModel: ObservableObject {
    @Published private(set) var videos: [Video] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let mode: FeedMode
    private var nextCursor: String?
    private var hasLoaded = false

    init(mode: FeedMode = .forYou) {
        self.mode = mode
    }

    func applyLike(videoID: String, liked: Bool, likeCount: Int) {
        guard let index = videos.firstIndex(where: { $0.id == videoID }) else { return }
        videos[index].likedByMe = liked
        videos[index].likeCount = likeCount
    }

    func applyCommentCount(videoID: String, count: Int) {
        guard let index = videos.firstIndex(where: { $0.id == videoID }) else { return }
        videos[index].commentCount = count
    }

    func loadIfNeeded() async {
        guard !hasLoaded, !isLoading else { return }
        await loadMore()
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let base = mode == .following ? "/api/videos/following" : "/api/videos"
            let response: FeedResponse = try await APIClient.shared.request(base)
            if response.videos.isEmpty {
                videos = []
                nextCursor = nil
            } else {
                videos = response.videos
                nextCursor = response.nextCursor
            }
            hasLoaded = true
            errorMessage = nil
        } catch {
            print("Feed refresh error: \(error.localizedDescription)")
        }
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
            errorMessage = nil
        } catch {
            print("Feed load error: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }
}

enum FeedMode: Hashable {
    case forYou
    case following
}

extension Notification.Name {
    static let sharkPauseFeedPlayback = Notification.Name("sharkPauseFeedPlayback")
}

@MainActor
final class PlayerModel: ObservableObject {
    let player = AVPlayer()
    @Published var isMuted = false {
        didSet { player.isMuted = isMuted }
    }
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = false

    private var preparedItem: AVPlayerItem?
    private var preparedKey: String?
    private var endObserver: NSObjectProtocol?
    private var pauseObservers: [NSObjectProtocol] = []
    private var timeControlObserver: NSKeyValueObservation?
    private var itemCache: [String: AVPlayerItem] = [:]
    private let maxCacheSize = 5

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
        timeControlObserver = player.observe(\.timeControlStatus, options: [.new, .initial]) { [weak self] player, _ in
            let waiting = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
            Task { @MainActor [weak self] in
                self?.isLoading = waiting
            }
        }
        pauseObservers = [
            NotificationCenter.default.addObserver(
                forName: .sharkPauseFeedPlayback,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.pause() }
            },
            NotificationCenter.default.addObserver(
                forName: UIApplication.willResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.pause() }
            },
        ]
    }

    deinit {
        timeControlObserver?.invalidate()
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        pauseObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func play() {
        player.play()
        isPlaying = true
    }

    func play(_ video: Video) {
        let url = video.streamURL.absoluteString
        if let cached = itemCache.removeValue(forKey: url) {
            player.replaceCurrentItem(with: cached)
        } else if let preparedItem, preparedKey == url {
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

    func cache(_ video: Video) {
        let url = video.streamURL.absoluteString
        guard itemCache[url] == nil else { return }
        let asset = AVURLAsset(url: video.streamURL)
        itemCache[url] = AVPlayerItem(asset: asset)
        while itemCache.count > maxCacheSize, let key = itemCache.keys.first {
            itemCache.removeValue(forKey: key)
        }
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
