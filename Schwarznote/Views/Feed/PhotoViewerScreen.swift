//
//  PhotoViewerScreen.swift
//  Schwarznote
//

import SwiftUI

/// A note's pictures, full screen. Swipe (or click) left and right to move between them; live
/// photos play their motion when you arrive and again when you press select; a video opens the
/// player. The back button closes it.
struct PhotoViewerScreen: View {
    let media: [MediaItem]

    @State private var index: Int
    @State private var playingLive = false
    @State private var video: PlayableVideo?
    @State private var lastStep = Date.distantPast
    @State private var showsChrome = true

    init(media: [MediaItem], startAt index: Int) {
        self.media = media
        _index = State(initialValue: min(max(index, 0), max(media.count - 1, 0)))
    }

    private var current: MediaItem? { media.isEmpty ? nil : media[index] }

    var body: some View {
        Button(action: activate) {
            stage
        }
        .buttonStyle(BareButtonStyle())
        .background(Color.black.ignoresSafeArea())
        .overlay(alignment: .bottom) { chrome }
        .background(SwipeMonitor(directions: [.left, .right]) { direction in
            step(direction == .right ? 1 : -1)
        })
        .onMoveCommand { direction in
            switch direction {
            case .right: step(1)
            case .left: step(-1)
            default: break
            }
        }
        .onAppear { arrive() }
        .fullScreenCover(item: $video) { video in
            VideoPlayerScreen(url: video.url)
        }
    }

    @ViewBuilder
    private var stage: some View {
        if let current {
            ZStack {
                RemoteImage(url: current.imageURL, contentMode: .fit)
                if current.kind == .livePhoto, playingLive, let url = current.videoURL {
                    PlayOnceVideoView(url: url) { playingLive = false }
                        .aspectRatio(current.aspectRatio, contentMode: .fit)
                }
                if current.kind == .video {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 160))
                        .foregroundStyle(.white, .black.opacity(0.4))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            .id(index)
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var chrome: some View {
        if let current, showsChrome {
            HStack(spacing: 24) {
                if current.kind == .livePhoto {
                    Label("LIVE", systemImage: "livephoto")
                        .font(.caption.bold())
                }
                if media.count > 1 {
                    Text("\(index + 1) / \(media.count)")
                        .monospacedDigit()
                }
                Text(hint(for: current))
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .padding(.horizontal, 30)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.bottom, 50)
            .transition(.opacity)
        }
    }

    private func hint(for item: MediaItem) -> String {
        let move = media.count > 1 ? "左右滑动切换" : nil
        let select: String? = switch item.kind {
        case .image: nil
        case .livePhoto: "按确认键重播实况"
        case .video: "按确认键播放视频"
        }
        return [move, select].compactMap { $0 }.joined(separator: " · ")
    }

    private func step(_ delta: Int) {
        guard media.count > 1, Date().timeIntervalSince(lastStep) > 0.3 else { return }
        lastStep = Date()
        let target = index + delta
        guard media.indices.contains(target) else { return }
        withAnimation(.easeInOut(duration: 0.25)) { index = target }
        arrive()
    }

    /// Live photos play once on arrival; the hint fades after a few seconds so the photo is unobstructed.
    private func arrive() {
        playingLive = current?.kind == .livePhoto
        withAnimation { showsChrome = true }
        let shown = index
        Task {
            try? await Task.sleep(for: .seconds(3))
            if index == shown { withAnimation { showsChrome = false } }
        }
    }

    private func activate() {
        guard let current else { return }
        withAnimation { showsChrome = true }
        switch current.kind {
        case .image: break
        case .livePhoto: playingLive = true
        case .video: video = current.videoURL.map(PlayableVideo.init)
        }
    }
}

/// A button with no visual change on focus or press, for full-bleed content.
struct BareButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}
