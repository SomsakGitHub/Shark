import SwiftUI

struct VideoActions: View {
    let video: Video

    @State private var liked: Bool
    @State private var likeCount: Int
    @State private var showingComments = false

    init(video: Video) {
        self.video = video
        _liked = State(initialValue: video.likedByMe)
        _likeCount = State(initialValue: video.likeCount)
    }

    var body: some View {
        VStack(spacing: 6) {
            actionButton(systemImage: liked ? "heart.fill" : "heart", tint: liked ? .red : .white) {
                Task { await toggleLike() }
            }
            Text("\(likeCount)").font(.caption2)

            actionButton(systemImage: "bubble.right", tint: .white) {
                showingComments = true
            }
            Text("\(video.commentCount)").font(.caption2)

            ShareLink(item: video.shareURL, subject: Text("Check out this video on Shark")) {
                Image(systemName: "arrowshape.turn.up.right")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            Text("Share").font(.caption2)
        }
        .foregroundStyle(.white)
        .sheet(isPresented: $showingComments) {
            CommentsView(videoID: video.id)
                .presentationDetents([.medium, .large])
        }
    }

    private func actionButton(systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
        }
    }

    private func toggleLike() async {
        do {
            let response: LikeResponse = try await APIClient.shared.request(
                "/api/videos/\(video.id)/like",
                method: "POST"
            )
            withAnimation(.spring(response: 0.4)) {
                liked = response.liked
                likeCount = response.likeCount
            }
        } catch {
            print("Like failed: \(error.localizedDescription)")
        }
    }
}
