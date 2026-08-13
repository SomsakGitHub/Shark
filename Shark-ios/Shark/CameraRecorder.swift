import AVFoundation
import Combine
import SwiftUI
import UIKit

@MainActor
final class CameraRecorder: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var recordedURL: URL?

    let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var isConfigured = false

    override init() {
        super.init()
    }

    func prepare() {
        guard !isConfigured else { return }
        isConfigured = true

        session.beginConfiguration()
        session.sessionPreset = .hd1280x720

        if let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
           let input = try? AVCaptureDeviceInput(device: camera),
           session.canAddInput(input) {
            session.addInput(input)
        }
        if let mic = AVCaptureDevice.default(for: .audio),
           let input = try? AVCaptureDeviceInput(device: mic),
           session.canAddInput(input) {
            session.addInput(input)
        }
        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        }
        session.commitConfiguration()

        Task.detached(priority: .userInitiated) { [session] in
            session.startRunning()
        }
    }

    func toggleRecording() {
        if isRecording {
            movieOutput.stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        guard !movieOutput.isRecording else { return }
        recordedURL = nil
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rec-\(UUID().uuidString).mov")
        movieOutput.startRecording(to: url, recordingDelegate: self)
    }
}

extension CameraRecorder: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        Task { @MainActor in
            isRecording = true
        }
    }

    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        Task { @MainActor in
            isRecording = false
            if error == nil {
                recordedURL = outputFileURL
            }
        }
    }
}

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {}
}

final class CameraPreviewUIView: UIView {
    let previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        layer.addSublayer(previewLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
    }
}

struct CameraRecorderView: View {
    var onVideoRecorded: (URL) -> Void

    @StateObject private var recorder = CameraRecorder()

    var body: some View {
        VStack(spacing: 16) {
            CameraPreviewView(session: recorder.session)
                .aspectRatio(9.0 / 16.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .bottom) {
                    Text(recorder.isRecording ? "Recording…" : "Tap to record")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.5), in: Capsule())
                        .padding(.bottom, 12)
                }

            Button {
                recorder.toggleRecording()
            } label: {
                Circle()
                    .fill(recorder.isRecording ? Color.red : Color.white)
                    .frame(width: 72, height: 72)
                    .overlay {
                        Circle()
                            .strokeBorder(.black.opacity(0.7), lineWidth: 4)
                            .frame(width: 80, height: 80)
                    }
            }
            .buttonStyle(.plain)
            .padding(.vertical, 8)
        }
        .onAppear { recorder.prepare() }
        .onChange(of: recorder.recordedURL) { _, url in
            if let url {
                onVideoRecorded(url)
            }
        }
    }
}
