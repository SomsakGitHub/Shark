import AVFoundation
import Combine
import Foundation

@MainActor
final class FeedModel: ObservableObject {
    @Published private(set) var videos: [Video] = []
    @Published private(set) var isLoading = false

    private var nextCursor: String?
    private var hasLoaded = false

    func loadIfNeeded() async {
        guard !hasLoaded, !isLoading else { return }
        await loadMore()
    }

    func loadMore() async {
        guard !isLoading else { return }
        if nextCursor == "" { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let path: String
            if let cursor = nextCursor {
                let encoded = cursor.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cursor
                path = "/api/videos?cursor=\(encoded)"
            } else {
                path = "/api/videos"
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

@MainActor
final class PlayerModel: ObservableObject {
    let player = AVPlayer()

    func replace(with url: URL) {
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
    }

    func play() {
        player.play()
    }

    func pause() {
        player.pause()
    }
}
