import SwiftUI

struct CommentsView: View {
    let videoID: String

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
                        Circle()
                            .fill(Color.accentColor.opacity(0.8))
                            .frame(width: 32, height: 32)
                            .overlay {
                                Text(String(comment.user.username.prefix(1)).uppercased())
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                            }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("@\(comment.user.username)")
                                .font(.caption.bold())
                            Text(comment.text)
                                .font(.subheadline)
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

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response: CommentsResponse = try await APIClient.shared.request(
                "/api/videos/\(videoID)/comments"
            )
            comments = response.comments
        } catch {
            print("Load comments failed: \(error.localizedDescription)")
        }
    }

    private func postComment() async {
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
        } catch {
            print("Post comment failed: \(error.localizedDescription)")
        }
    }
}
