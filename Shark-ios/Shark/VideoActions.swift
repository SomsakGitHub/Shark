import SwiftUI

struct VideoActions: View {
    let video: Video
    @Binding var liked: Bool
    @Binding var likeCount: Int
    var onLikeChanged: ((Bool, Int) -> Void)? = nil
    var onCommentCountChanged: ((Int) -> Void)? = nil

    @State private var commentCount: Int
    @State private var showingComments = false
    @EnvironmentObject private var auth: AuthManager

    init(
        video: Video,
        liked: Binding<Bool>,
        likeCount: Binding<Int>,
        onLikeChanged: ((Bool, Int) -> Void)? = nil,
        onCommentCountChanged: ((Int) -> Void)? = nil
    ) {
        self.video = video
        _liked = liked
        _likeCount = likeCount
        self.onLikeChanged = onLikeChanged
        self.onCommentCountChanged = onCommentCountChanged
        _commentCount = State(initialValue: video.commentCount)
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
            Text("\(commentCount)").font(.caption2)

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
            CommentsView(
                videoID: video.id,
                onCountChanged: { count in
                    commentCount = count
                    onCommentCountChanged?(count)
                }
            )
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
        guard auth.isSignedIn else {
            auth.showSignInPrompt = true
            return
        }
        let previousLiked = liked
        let previousCount = likeCount
        withAnimation(.spring(response: 0.4)) {
            liked.toggle()
            likeCount += liked ? 1 : -1
        }
        Haptics.impact(liked ? .medium : .light)
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
            print("Like failed: \(error.localizedDescription)")
        }
    }
}
