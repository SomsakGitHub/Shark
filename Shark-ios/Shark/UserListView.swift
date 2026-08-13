import SwiftUI

enum UserListMode: Identifiable {
    case followers(String)
    case following(String)

    var id: String {
        switch self {
        case .followers(let userId): return "followers-\(userId)"
        case .following(let userId): return "following-\(userId)"
        }
    }

    var title: String {
        switch self {
        case .followers: return "Followers"
        case .following: return "Following"
        }
    }

    var path: String {
        switch self {
        case .followers(let userId): return "/api/users/\(userId)/followers"
        case .following(let userId): return "/api/users/\(userId)/following"
        }
    }
}

struct UserListView: View {
    let mode: UserListMode

    @State private var users: [UserSummary] = []
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            Group {
                if users.isEmpty {
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    } else {
                        Text(mode.title == "Followers" ? "No followers yet" : "Not following anyone yet")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    }
                } else {
                    List(users) { user in
                        NavigationLink {
                            ProfileView(userId: user.id)
                        } label: {
                            UserRow(user: user)
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .task { await load() }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response: UsersResponse = try await APIClient.shared.request(mode.path)
            users = response.users
        } catch {
            print("User list load failed: \(error.localizedDescription)")
        }
    }
}
