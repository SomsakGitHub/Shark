import SwiftUI

struct CommentsView: View {
    let videoID: String
    var onCountChanged: ((Int) -> Void)? = nil

    @EnvironmentObject private var auth: AuthManager
    @State private var comments: [Comment] = []
    @State private var text = ""
    @State private var isLoading = false
    @State private var isPosting = false
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text("Comments")
                .font(.headline)
                .padding(.top, 16)
                .padding(.bottom, 8)

            Divider()

            content

            Divider()

            inputBar
        }
        .task { await load() }
        .overlay(alignment: .top) { errorToast }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && comments.isEmpty {
            Spacer()
            ProgressView()
            Spacer()
        } else if comments.isEmpty {
            Spacer()
            Text("No comments yet")
                .foregroundStyle(.secondary)
            Spacer()
        } else {
            List(comments) { comment in
                commentRow(comment)
            }
            .listStyle(.plain)
            .refreshable { await load() }
        }
    }

    private func commentRow(_ comment: Comment) -> some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarView(url: comment.user.avatarUrl, username: comment.user.username, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text("@\(comment.user.username)  ·  \(comment.createdAt.timeAgo)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(comment.text)
                    .font(.subheadline)
            }
            Spacer()
            if comment.user.id == auth.user?.id {
                Button {
                    Task { await deleteComment(comment) }
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listRowSeparator(.hidden)
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Add a comment…", text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
            Button("Post") {
                Task { await postComment() }
            }
            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || isPosting)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var errorToast: some View {
        if let errorMessage {
            Text(errorMessage)
                .font(.footnote.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.red.opacity(0.9), in: Capsule())
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: errorMessage) {
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation {
                        self.errorMessage = nil
                    }
                }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response: CommentsResponse = try await APIClient.shared.request(
                "/api/videos/\(videoID)/comments"
            )
            comments = response.comments
            onCountChanged?(comments.count)
        } catch {
            print("Load comments failed: \(error.localizedDescription)")
            errorMessage = "Couldn't load comments"
        }
    }

    private func postComment() async {
        guard auth.isSignedIn else {
            auth.showSignInPrompt = true
            return
        }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isPosting = true
        defer { isPosting = false }
        text = ""
        focused = false

        let optimistic = Comment(
            id: UUID().uuidString,
            text: trimmed,
            createdAt: Date(),
            user: Video.UserRef(
                id: auth.user?.id ?? "",
                username: auth.user?.username ?? "",
                avatarUrl: auth.user?.avatarUrl
            )
        )
        comments.append(optimistic)
        onCountChanged?(comments.count)
        Haptics.success()

        do {
            struct Payload: Encodable { let text: String }
            let body = try JSONEncoder.shark().encode(Payload(text: trimmed))
            let response: CommentsResponse = try await APIClient.shared.request(
                "/api/videos/\(videoID)/comments",
                method: "POST",
                body: body
            )
            comments = response.comments
            onCountChanged?(comments.count)
        } catch {
            comments.removeAll { $0.id == optimistic.id }
            onCountChanged?(comments.count)
            print("Post comment failed: \(error.localizedDescription)")
            errorMessage = "Couldn't post comment"
        }
    }

    private func deleteComment(_ comment: Comment) async {
        guard auth.isSignedIn else {
            auth.showSignInPrompt = true
            return
        }
        comments.removeAll { $0.id == comment.id }
        onCountChanged?(comments.count)
        do {
            let response: CommentsResponse = try await APIClient.shared.request(
                "/api/videos/\(videoID)/comments/\(comment.id)",
                method: "DELETE"
            )
            comments = response.comments
            onCountChanged?(comments.count)
        } catch {
            print("Delete comment failed: \(error.localizedDescription)")
            await load()
            errorMessage = "Couldn't delete comment"
        }
    }
}
