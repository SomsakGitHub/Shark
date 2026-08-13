import Combine
import Foundation

@MainActor
final class DeepLinkHandler: ObservableObject {
    @Published var pendingVideo: Video?

    func handle(_ url: URL) {
        guard url.scheme?.lowercased() == "shark", url.host?.lowercased() == "video" else { return }
        let id = url.lastPathComponent
        guard !id.isEmpty else { return }
        Task {
            do {
                let video = try await APIClient.shared.fetchVideo(id: id)
                pendingVideo = video
            } catch {
                print("Deep link load failed: \(error.localizedDescription)")
            }
        }
    }
}
