import AVFoundation
import PhotosUI
import SwiftUI
import UIKit

struct UploadView: View {
    enum UploadSource: String, CaseIterable, Identifiable {
        case library = "Library"
        case camera = "Camera"
        var id: String { rawValue }
    }

    enum UploadError: LocalizedError {
        case fileTooLarge(Int)

        var errorDescription: String? {
            switch self {
            case .fileTooLarge(let max):
                return "Video is too large (max \(max / 1_048_576) MB)"
            }
        }
    }

    private static let maxSourceBytes = 100 * 1_048_576

    @Environment(\.dismiss) private var dismiss
    @State private var source: UploadSource = .library
    @State private var pickerItem: PhotosPickerItem?
    @State private var videoURL: URL?
    @State private var caption = ""
    @State private var isUploading = false
    @State private var uploadProgress = 0.0
    @State private var errorMessage: String?
    @State private var didUpload = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Source", selection: $source) {
                        ForEach(UploadSource.allCases) { source in
                            Text(source.rawValue).tag(source)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if source == .library {
                    librarySection
                } else {
                    cameraSection
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
                    postButton
                }
            }
            .navigationTitle("Upload")
            .onChange(of: pickerItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    do {
                        if let url = try await newItem.loadTransferable(type: URL.self) {
                            videoURL = url
                        } else if let data = try await newItem.loadTransferable(type: Data.self) {
                            let url = FileManager.default.temporaryDirectory
                                .appendingPathComponent("picked-\(UUID().uuidString).mov")
                            try data.write(to: url)
                            videoURL = url
                        } else {
                            errorMessage = "Couldn't load the selected video"
                        }
                    } catch {
                        errorMessage = "Couldn't load the selected video"
                    }
                }
            }
            .onChange(of: didUpload) { _, posted in
                if posted { dismiss() }
            }
        }
    }

    private var librarySection: some View {
        Section {
            PhotosPicker(selection: $pickerItem, matching: .videos) {
                HStack {
                    if videoURL == nil {
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
            if videoURL != nil {
                Button("Remove", role: .destructive) {
                    videoURL = nil
                    pickerItem = nil
                }
            }
        }
    }

    private var cameraSection: some View {
        Section {
            CameraRecorderView { url in
                videoURL = url
                pickerItem = nil
            }
            if videoURL != nil {
                Button("Remove", role: .destructive) {
                    videoURL = nil
                }
            }
        }
    }

    private var postButton: some View {
        Button {
            Task { await upload() }
        } label: {
            HStack {
                Spacer()
                if isUploading {
                    VStack(spacing: 6) {
                        ProgressView(value: uploadProgress)
                        Text("\(Int(uploadProgress * 100))%")
                            .font(.caption)
                    }
                } else {
                    Text("Post")
                        .bold()
                }
                Spacer()
            }
        }
        .disabled(videoURL == nil || isUploading)
    }

    private func upload() async {
        guard let sourceURL = videoURL else { return }
        isUploading = true
        errorMessage = nil
        uploadProgress = 0
        defer { isUploading = false }

        do {
            let fileURL = try await prepareForUpload(sourceURL)
            let localKey = "\(UUID().uuidString).mp4"
            let storageKey = try await APIClient.shared.uploadVideo(
                key: localKey,
                fileURL: fileURL
            ) { fraction in
                uploadProgress = fraction
            }
            if let thumbnail = await makeThumbnail(fileURL: fileURL) {
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

    private func prepareForUpload(_ source: URL) async throws -> URL {
        let size = (try? FileManager.default.attributesOfItem(atPath: source.path)[.size] as? Int) ?? 0
        guard size > 0 else { throw UploadError.fileTooLarge(Self.maxSourceBytes) }
        guard size <= Self.maxSourceBytes else { throw UploadError.fileTooLarge(Self.maxSourceBytes) }

        if let compressed = await transcodeTo720p(source) {
            return compressed
        }
        return source
    }

    private func transcodeTo720p(_ source: URL) async -> URL? {
        let asset = AVURLAsset(url: source)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720) else {
            return nil
        }
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("compressed-\(UUID().uuidString).mp4")
        export.outputURL = output
        export.outputFileType = .mp4
        export.shouldOptimizeForNetworkUse = true
        do {
            try await export.export(to: output, as: .mp4)
        } catch {
            print("Transcode failed: \(error.localizedDescription)")
            return nil
        }
        guard FileManager.default.fileExists(atPath: output.path) else { return nil }
        return output
    }

    private func makeThumbnail(fileURL: URL) async -> Data? {
        let asset = AVURLAsset(url: fileURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 360, height: 640)
        let cgImage: CGImage? = await withCheckedContinuation { continuation in
            generator.generateCGImageAsynchronously(for: .zero) { image, _, _ in
                continuation.resume(returning: image)
            }
        }
        guard let cgImage else {
            print("Thumbnail generation failed")
            return nil
        }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.7)
    }
}
