//
//  VideoFeedView.swift
//  Shark
//
//  Created by tiscomacnb2486 on 6/8/2569 BE.
//

import SwiftUI
import AVFoundation
import os

struct VideoFeedView: View {
    @State private var videos = VideoItem.mockData
    @State private var currentVideoID: String?

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(videos) { video in
                    VideoPageView(video: video, isActive: video.id == currentVideoID)
                        .containerRelativeFrame(.vertical)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $currentVideoID)
        .ignoresSafeArea()
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onChange(of: currentVideoID) { _, newID in
            Logger.view.info("Feed currentVideoID -> \(String(describing: newID))")
        }
        .onAppear {
            Logger.view.info("Feed onAppear currentVideoID=\(String(describing: currentVideoID))")
            if currentVideoID == nil {
                currentVideoID = videos.first?.id
            }
        }
    }
}

struct VideoPageView: View {
    let video: VideoItem
    let isActive: Bool

    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                PlayerView(player: player)
            }

            videoOverlay
        }
        .ignoresSafeArea()
        .onAppear {
            setupPlayerIfNeeded()
        }
        .onDisappear {
            player?.pause()
        }
        .task(id: isActive) {
            if isActive {
                Logger.view.info("VideoPage \(video.fileName) play")
                player?.play()
            } else {
                player?.pause()
            }
            #if DEBUG
            while !Task.isCancelled {
                if let player {
                    Logger.view.info("Playback \(self.video.fileName) tcs=\(player.timeControlStatus.rawValue) rate=\(player.rate) t=\(player.currentTime().seconds)")
                }
                try? await Task.sleep(for: .seconds(1))
            }
            #endif
        }
    }

    private func setupPlayerIfNeeded() {
        guard player == nil,
              let url = Bundle.main.url(forResource: video.fileName, withExtension: "mp4") else {
            return
        }
        let item = AVPlayerItem(url: url)
        let queuePlayer = AVQueuePlayer()
        let looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        self.looper = looper
        self.player = queuePlayer
        Logger.view.info("VideoPage \(self.video.fileName) setup isActive=\(self.isActive) url=\(url.path)")
        #if DEBUG
        queuePlayer.addPeriodicTimeObserver(forInterval: CMTime(seconds: 2, preferredTimescale: 600), queue: .main) { time in
            Logger.view.info("Playback \(self.video.fileName) t=\(time.seconds, privacy: .public)s rate=\(queuePlayer.rate)")
        }
        #endif
        if self.isActive {
            queuePlayer.play()
        }
    }

    private var videoOverlay: some View {
        ZStack {
            LinearGradient(
                colors: [.clear, .black.opacity(0.5)],
                startPoint: .center,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Spacer()
                bottomBar
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 20)
        }
    }

    private var header: some View {
        HStack(spacing: 24) {
            Spacer()
            Text("Following")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
            Text("For You")
                .font(.headline)
                .foregroundStyle(.white)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(.white)
                        .frame(width: 28, height: 2)
                        .offset(y: 6)
                }
            Spacer()
        }
        .padding(.top, 4)
    }

    private var bottomBar: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(video.username)
                    .font(.headline)
                Text(video.caption)
                    .font(.subheadline)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Image(systemName: "music.note")
                    Text(video.music)
                        .font(.caption)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .shadow(color: .black.opacity(0.4), radius: 2, y: 1)

            VStack(spacing: 20) {
                avatar
                actionButton(icon: "heart", count: video.likes)
                actionButton(icon: "message", count: video.comments)
                actionButton(icon: "arrowshape.turn.up.right", count: video.shares)
                MusicDisc()
            }
        }
    }

    private var avatar: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .frame(width: 48, height: 48)
                .foregroundStyle(.white.opacity(0.9))
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(.pink)
                .background(Circle().fill(.white))
                .offset(x: 2, y: 2)
        }
        .padding(.bottom, 4)
    }

    private func actionButton(icon: String, count: Int) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
            Text(shortCount(count))
                .font(.caption)
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
    }

    private func shortCount(_ n: Int) -> String {
        if n >= 1_000_000 {
            return String(format: "%.1fM", Double(n) / 1_000_000)
        }
        if n >= 1_000 {
            return String(format: "%.1fK", Double(n) / 1_000)
        }
        return "\(n)"
    }
}

struct MusicDisc: View {
    @State private var isSpinning = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.35))
                .frame(width: 44, height: 44)
            Image(systemName: "music.note")
                .font(.subheadline)
                .foregroundStyle(.white)
        }
        .rotationEffect(.degrees(isSpinning ? 360 : 0))
        .animation(.linear(duration: 4).repeatForever(autoreverses: false), value: isSpinning)
        .onAppear {
            isSpinning = true
        }
    }
}

#Preview {
    VideoFeedView()
}
