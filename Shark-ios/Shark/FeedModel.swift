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
        guard !isLoading, !hasLoaded || nextCursor != nil else { return }
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
            if videos.isEmpty {
                errorMessage = error.localizedDescription
            }
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
    @Published var isMuted = false
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = false

    private var players: [String: AVPlayer] = [:]
    private var endObservers: [String: NSObjectProtocol] = [:]
    private var statusObservers: [String: NSKeyValueObservation] = [:]
    private(set) var activeKey: String?
    private var pauseObservers: [NSObjectProtocol] = []

    init() {
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
        pauseObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func activate(video: Video, videos: [Video], index: Int) {
        let key = video.streamURL.absoluteString

        if activeKey == key {
            players[key]?.play()
            isPlaying = true
            return
        }

        if let currentKey = activeKey {
            players[currentKey]?.pause()
        }

        let player = getOrCreatePlayer(for: video)
        activeKey = key
        player.isMuted = isMuted
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard self?.activeKey == key else { return }
                self?.players[key]?.play()
                self?.isPlaying = true
            }
        }

        for offset in 1...2 {
            let nextIndex = index + offset
            if videos.indices.contains(nextIndex) {
                _ = getOrCreatePlayer(for: videos[nextIndex])
            }
        }

        var keepKeys = Set<String>()
        keepKeys.insert(key)
        if let prev = videoForPlayer(at: index - 1, in: videos) {
            keepKeys.insert(prev.streamURL.absoluteString)
        }
        for offset in 1...2 {
            let nextIndex = index + offset
            if videos.indices.contains(nextIndex) {
                keepKeys.insert(videos[nextIndex].streamURL.absoluteString)
            }
        }
        for playerKey in players.keys where !keepKeys.contains(playerKey) {
            removePlayer(for: playerKey)
        }
    }

    func player(for video: Video) -> AVPlayer? {
        players[video.streamURL.absoluteString]
    }

    private func videoForPlayer(at index: Int, in videos: [Video]) -> Video? {
        videos.indices.contains(index) ? videos[index] : nil
    }

    private func getOrCreatePlayer(for video: Video) -> AVPlayer {
        let key = video.streamURL.absoluteString
        if let existing = players[key] {
            return existing
        }
        let player = AVPlayer(url: video.streamURL)
        player.automaticallyWaitsToMinimizeStalling = true
        player.actionAtItemEnd = .none
        player.currentItem?.preferredForwardBufferDuration = 15

        let endObs = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: player.currentItem,
            queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                player?.play()
            }
        }
        endObservers[key] = endObs

        let statusObs = player.observe(\.timeControlStatus, options: [.new, .initial]) { [weak self] player, _ in
            let isWaiting = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
            Task { @MainActor [weak self] in
                guard self?.activeKey == key else { return }
                self?.isLoading = isWaiting
            }
        }
        statusObservers[key] = statusObs

        players[key] = player
        return player
    }

    func pause() {
        if let key = activeKey {
            players[key]?.pause()
        }
        isPlaying = false
    }

    func togglePlay() {
        guard let key = activeKey, let player = players[key] else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    func toggleMute() {
        isMuted.toggle()
        if let key = activeKey {
            players[key]?.isMuted = isMuted
        }
    }

    private func removePlayer(for key: String) {
        guard key != activeKey else { return }
        players[key]?.pause()
        players[key]?.replaceCurrentItem(with: nil)
        if let observer = endObservers[key] {
            NotificationCenter.default.removeObserver(observer)
        }
        statusObservers[key]?.invalidate()
        endObservers[key] = nil
        statusObservers[key] = nil
        players[key] = nil
    }

    func removeAll() {
        players.keys.forEach { removePlayer(for: $0) }
        if let activeKey {
            players[activeKey]?.pause()
            players[activeKey]?.replaceCurrentItem(with: nil)
            players[activeKey] = nil
        }
        self.activeKey = nil
        isPlaying = false
        isLoading = false
    }
}
