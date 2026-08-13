import SwiftUI

struct CommentsView: View {
    let videoID: String
    var onCountChanged: ((Int) -> Void)? = nil

    @EnvironmentObject private var auth: AuthManager
    @State private var comments: [Comment] = []
    @State private var text = ""
    @State private var isLoading = false
    @State private var isPosting = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text("Comments")
                .font(.headline)
                .padding(.top, 16)
                .padding(.bottom, 8)

            Divider()

            if comments.isEmpty && !isLoading {
                Spacer()
                Text("No comments yet")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(comments) { comment in
                    HStack(alignment: .top, spacing: 10) {
                        commentAvatar(comment.user)
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
                .listStyle(.plain)
            }

            Divider()

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
        .task { await load() }
    }

    @ViewBuilder
    private func commentAvatar(_ user: Video.UserRef) -> some View {
        if let path = user.avatarUrl, let url = URL.shark(path) {
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    letterAvatar(user)
                }
            }
            .frame(width: 32, height: 32)
            .clipShape(Circle())
        } else {
            letterAvatar(user)
        }
    }

    private func letterAvatar(_ user: Video.UserRef) -> some View {
        Circle()
            .fill(Color.accentColor.opacity(0.8))
            .frame(width: 32, height: 32)
            .overlay {
                Text(String(user.username.prefix(1)).uppercased())
                    .font(.caption.bold())
                    .foregroundStyle(.white)
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
        do {
            struct Payload: Encodable { let text: String }
            let body = try JSONEncoder.shark().encode(Payload(text: trimmed))
            let response: CommentsResponse = try await APIClient.shared.request(
                "/api/videos/\(videoID)/comments",
                method: "POST",
                body: body
            )
            comments = response.comments
            text = ""
            focused = false
            Haptics.success()
            onCountChanged?(comments.count)
        } catch {
            print("Post comment failed: \(error.localizedDescription)")
        }
    }

    private func deleteComment(_ comment: Comment) async {
        guard auth.isSignedIn else {
            auth.showSignInPrompt = true
            return
        }
        do {
            let response: CommentsResponse = try await APIClient.shared.request(
                "/api/videos/\(videoID)/comments/\(comment.id)",
                method: "DELETE"
            )
            comments = response.comments
            onCountChanged?(comments.count)
        } catch {
            print("Delete comment failed: \(error.localizedDescription)")
        }
    }
}
