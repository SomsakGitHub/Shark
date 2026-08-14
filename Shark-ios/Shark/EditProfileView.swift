import PhotosUI
import SwiftUI

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthManager

    let user: APIUser?
    var onSaved: () -> Void

    @State private var username: String
    @State private var bio: String
    @State private var avatarItem: PhotosPickerItem?
    @State private var avatarData: Data?
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(user: APIUser?, onSaved: @escaping () -> Void) {
        self.user = user
        self.onSaved = onSaved
        _username = State(initialValue: user?.username ?? "")
        _bio = State(initialValue: user?.bio ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Photo") {
                    HStack(spacing: 16) {
                        avatarPreview
                        PhotosPicker(selection: $avatarItem, matching: .images) {
                            Label(avatarData == nil ? "Change Photo" : "Replace", systemImage: "photo")
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Username") {
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Bio") {
                    TextField("Tell people about yourself", text: $bio, axis: .vertical)
                        .lineLimit(3...5)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Edit Profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(isSaving || username.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onChange(of: avatarItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self) {
                        avatarData = data
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var avatarPreview: some View {
        if let avatarData, let image = UIImage(data: avatarData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 80, height: 80)
                .clipShape(Circle())
        } else {
            AvatarView(url: user?.avatarUrl, username: username, size: 80)
        }
    }

    private func save() async {
        let trimmedName = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBio = bio.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.count >= 3, trimmedName.count <= 24 else {
            errorMessage = "Username must be 3-24 characters"
            return
        }
        guard trimmedBio.count <= 160 else {
            errorMessage = "Bio must be 160 characters or fewer"
            return
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            if let avatarData {
                _ = try await APIClient.shared.uploadAvatar(data: avatarData)
            }
            _ = try await APIClient.shared.updateProfile(username: trimmedName, bio: trimmedBio)
            await auth.refresh()
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
