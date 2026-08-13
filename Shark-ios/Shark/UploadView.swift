import AVFoundation
import PhotosUI
import SwiftUI
import UIKit

struct UploadView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pickerItem: PhotosPickerItem?
    @State private var videoData: Data?
    @State private var caption = ""
    @State private var isUploading = false
    @State private var errorMessage: String?
    @State private var didUpload = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PhotosPicker(selection: $pickerItem, matching: .videos) {
                        HStack {
                            if videoData == nil {
                                Image(systemName: "video.badge.plus")
                                Text("Choose a video")
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("Video selected")
                            }
                            Spacer()
                        }
                    }
                    if videoData != nil {
                        Button("Remove", role: .destructive) {
                            videoData = nil
                            pickerItem = nil
                        }
                    }
                }

                Section("Caption") {
                    TextField("Say something…", text: $caption)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        Task { await upload() }
                    } label: {
                        HStack {
                            Spacer()
                            if isUploading {
                                ProgressView()
                            } else {
                                Text("Post")
                                    .bold()
                            }
                            Spacer()
                        }
                    }
                    .disabled(videoData == nil || isUploading)
                }
            }
            .navigationTitle("Upload")
            .onChange(of: pickerItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self) {
                        videoData = data
                    }
                }
            }
            .onChange(of: didUpload) { _, posted in
                if posted { dismiss() }
            }
        }
    }

    private func upload() async {
        guard let videoData else { return }
        isUploading = true
        errorMessage = nil
        defer { isUploading = false }

        do {
            let localKey = "\(UUID().uuidString).mp4"
            let storageKey = try await APIClient.shared.uploadVideo(key: localKey, data: videoData)
            if let thumbnail = makeThumbnail(data: videoData) {
                try? await APIClient.shared.uploadThumbnail(key: storageKey, data: thumbnail)
            }
            let payload = try JSONEncoder.shark().encode(VideoCreateRequest(key: storageKey, caption: caption))
            let _: VideoCreateResponse = try await APIClient.shared.request(
                "/api/videos",
                method: "POST",
                body: payload
            )
            didUpload = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func makeThumbnail(data: Data) -> Data? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        do {
            try data.write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }

            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 360, height: 640)

            let image = try generator.copyCGImage(at: .zero, actualTime: nil)
            return UIImage(cgImage: image).jpegData(compressionQuality: 0.7)
        } catch {
            print("Thumbnail generation failed: \(error.localizedDescription)")
            return nil
        }
    }
}
