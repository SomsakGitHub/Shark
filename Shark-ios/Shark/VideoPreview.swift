//
//  VideoPreview.swift
//  Shark
//
//  Created by tiscomacnb2486 on 8/8/2569 BE.
//

import SwiftUI
import AVFoundation

struct VideoPreviewPlayer: View {
    let video: VideoItem

    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?

    var body: some View {
        ZStack {
            Color.black
            if let player {
                PlayerView(player: player)
            }
        }
        .task(id: video.id) {
            let item = AVPlayerItem(asset: AVURLAsset(url: video.videoURL))
            let queuePlayer = AVQueuePlayer()
            let looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
            self.looper = looper
            self.player = queuePlayer
            queuePlayer.play()
        }
        .onDisappear {
            player?.pause()
            looper = nil
            player = nil
        }
    }
}

struct VideoPreviewSheet: View {
    let video: VideoItem

    @Environment(\.dismiss) private var dismiss
    @State private var showFullVideo = false

    var body: some View {
        VStack(spacing: 16) {
            VideoPreviewPlayer(video: video)
                .frame(height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.top, 24)

            Text(video.caption)
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            HStack(spacing: 8) {
                Text(video.username)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("·")
                    .foregroundStyle(.secondary)
                Label(video.likes.formatted(), systemImage: "heart.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button {
                showFullVideo = true
            } label: {
                Label("Watch full video", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .presentationDetents([.medium])
        .sheet(isPresented: $showFullVideo) {
            VideoPageView(video: video, isActive: true, isPrefetched: true)
                .ignoresSafeArea()
                .presentationBackground(.black)
                .presentationDragIndicator(.hidden)
        }
    }
}

#Preview {
    VideoPreviewSheet(video: VideoItem(
        id: "1",
        fileName: "fireworks",
        videoUrl: "https://shark-api-bd4f.onrender.com/videos/fireworks.mp4",
        username: "@somsak",
        caption: "Happy New Year from Bangkok",
        likes: 123400,
        comments: 2340,
        shares: 890,
        music: "original sound - som",
        latitude: 13.643960,
        longitude: 100.662433
    ))
}
