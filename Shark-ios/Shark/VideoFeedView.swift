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
    enum FeedState {
        case loading
        case loaded
        case failed(String)
    }

    private static let pageSize = 3

    @State private var videos: [VideoItem] = []
    @State private var currentVideoID: String?
    @State private var feedState: FeedState = .loading
    @State private var isLoadingMore = false
    @State private var hasMore = true

    private let client = APIClient()

    var body: some View {
        Group {
            switch feedState {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                feedErrorView(message)
            case .loaded:
                if videos.isEmpty {
                    emptyView
                } else {
                    feed
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .statusBarHidden()
        .task {
            await load()
        }
    }

    private var feed: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(Array(videos.enumerated()), id: \.element.id) { index, video in
                    VideoPageView(
                        video: video,
                        isActive: video.id == currentVideoID,
                        isPrefetched: shouldPrefetch(index)
                    )
                    .containerRelativeFrame(.vertical)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $currentVideoID)
        .onChange(of: currentVideoID) {
            loadMoreIfNeeded()
        }
        .onAppear {
            if currentVideoID == nil {
                currentVideoID = videos.first?.id
            }
        }
    }

    private func shouldPrefetch(_ index: Int) -> Bool {
        guard let current = currentVideoID,
              let currentIndex = videos.firstIndex(where: { $0.id == current }) else {
            return false
        }
        return abs(index - currentIndex) <= 1
    }

    private func load() async {
        feedState = .loading
        do {
            let page = try await client.fetchVideos(offset: 0, limit: Self.pageSize)
            videos = page.videos
            hasMore = page.hasMore
            currentVideoID = videos.first?.id
            feedState = .loaded
        } catch {
            feedState = .failed(error.localizedDescription)
        }
    }

    private func loadMoreIfNeeded() {
        guard hasMore, !isLoadingMore,
              let current = currentVideoID,
              let index = videos.firstIndex(where: { $0.id == current }),
              index >= videos.count - 1 else { return }

        isLoadingMore = true
        Task {
            do {
                let page = try await client.fetchVideos(offset: videos.count, limit: Self.pageSize)
                videos.append(contentsOf: page.videos)
                hasMore = page.hasMore
            } catch {
                Logger.view.error("Failed to load more videos: \(error.localizedDescription, privacy: .public)")
            }
            isLoadingMore = false
        }
    }

    private var emptyView: some View {
        Text("No videos available")
            .foregroundStyle(.white)
    }

    private func feedErrorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 44))
            Text("Couldn't load the feed")
                .font(.headline)
            Text(message)
                .font(.caption)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await load() }
            }
            .buttonStyle(.borderedProminent)
        }
        .foregroundStyle(.white)
        .padding(24)
    }
}

struct VideoPageView: View {
    let video: VideoItem
    let isActive: Bool
    let isPrefetched: Bool

    enum LoadState: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?
    @State private var loadState: LoadState = .idle

    private var shouldLoad: Bool {
        isActive || isPrefetched
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                PlayerView(player: player)
            }

            switch loadState {
            case .idle, .ready:
                EmptyView()
            case .loading:
                ProgressView()
                    .tint(.white)
            case .failed(let message):
                failedView(message)
            }

            videoOverlay
        }
        .task(id: shouldLoad) {
            if shouldLoad {
                await prepare()
                if isActive {
                    player?.play()
                }
            } else {
                teardown()
            }
        }
        .task(id: isActive) {
            if isActive {
                player?.play()
            }
        }
    }

    private func prepare() async {
        if player != nil {
            return
        }
        loadState = .loading
        let asset = AVURLAsset(url: video.videoURL)
        let item = AVPlayerItem(asset: asset)
        let queuePlayer = AVQueuePlayer()
        let looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        self.looper = looper
        player = queuePlayer
        Logger.view.info("VideoPage \(self.video.fileName) prepare")
        await waitForLoad()
    }

    private func waitForLoad() async {
        let startedAt = ContinuousClock.now
        while !Task.isCancelled {
            if let looper, looper.status == .failed {
                let message = looper.error?.localizedDescription ?? "Failed to load video"
                loadState = .failed(message)
                Logger.view.info("VideoPage \(self.video.fileName) failed: \(message)")
                return
            }
            if let item = player?.items().first {
                switch item.status {
                case .readyToPlay:
                    loadState = .ready
                    Logger.view.info("VideoPage \(self.video.fileName) ready")
                    return
                case .failed:
                    let message = item.error?.localizedDescription ?? "Failed to load video"
                    loadState = .failed(message)
                    Logger.view.info("VideoPage \(self.video.fileName) failed: \(message)")
                    return
                default:
                    break
                }
            }
            if ContinuousClock.now - startedAt > .seconds(15) {
                loadState = .failed("Timed out loading video")
                Logger.view.info("VideoPage \(self.video.fileName) failed: timeout")
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    private func teardown() {
        player?.pause()
        looper = nil
        player = nil
        loadState = .idle
        Logger.view.info("VideoPage \(self.video.fileName) teardown")
    }

    private func retry() {
        teardown()
        Task {
            await prepare()
            if isActive {
                player?.play()
            }
        }
    }

    private func failedView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
            Text("Video failed to load")
                .font(.headline)
            Text(message)
                .font(.caption)
                .multilineTextAlignment(.center)
            Button("Retry") {
                retry()
            }
            .buttonStyle(.borderedProminent)
        }
        .foregroundStyle(.white)
        .padding(24)
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
