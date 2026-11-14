//
//  MediaViewer.swift
//  Schwarznote
//

import AVKit
import SwiftUI

/// Left side of a note. Multiple pages get a thumbnail strip.
///
/// On its own, the strip holds the focus: moving along it switches the big view (live photos play
/// once as you land on them), and selecting a thumbnail opens that picture full screen, or the
/// video player for a video. With an `index` binding, the parent changes pages instead (the note
/// page does it with left and right clicks), nothing here takes focus, and setting
/// `fullScreenRequest` opens the current page.
struct MediaViewer: View {
    let media: [MediaItem]
    private let controlledIndex: Binding<Int>?
    private let fullScreenRequest: Binding<Bool>?

    @State private var ownIndex = 0
    @State private var playingLive = false
    @State private var fullScreenVideo: PlayableVideo?
    @State private var fullScreenPhoto: PhotoPage?
    @FocusState private var focusedThumbnail: Int?

    init(media: [MediaItem]) {
        self.media = media
        controlledIndex = nil
        fullScreenRequest = nil
    }

    init(media: [MediaItem], index: Binding<Int>, fullScreenRequest: Binding<Bool>) {
        self.media = media
        controlledIndex = index
        self.fullScreenRequest = fullScreenRequest
    }

    private var isControlled: Bool { controlledIndex != nil }

    private var index: Int {
        get { controlledIndex?.wrappedValue ?? ownIndex }
        nonmutating set {
            if let controlledIndex { controlledIndex.wrappedValue = newValue } else { ownIndex = newValue }
        }
    }

    private var current: MediaItem? {
        media.isEmpty ? nil : media[min(index, media.count - 1)]
    }

    var body: some View {
        VStack(spacing: 30) {
            stage
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if media.count > 1 {
                if isControlled {
                    pageStrip
                } else {
                    thumbnails
                }
            } else if !isControlled, let current {
                Button {
                    activate(current)
                } label: {
                    switch current.kind {
                    case .image: Label("全屏查看", systemImage: "arrow.up.left.and.arrow.down.right")
                    case .livePhoto: Label("全屏播放实况", systemImage: "livephoto")
                    case .video: Label("播放视频", systemImage: "play.fill")
                    }
                }
            }
        }
        .padding(.vertical, 40)
        .background(.black)
        .onChange(of: focusedThumbnail) { _, focused in
            guard let focused else { return }
            index = focused
            // Live photos play their motion once when you land on them, like hovering on the web.
            playingLive = media[focused].kind == .livePhoto
        }
        .onChange(of: media) {
            index = 0
            playingLive = media.first?.kind == .livePhoto
        }
        .onChange(of: index) { _, index in
            guard isControlled, media.indices.contains(index) else { return }
            playingLive = media[index].kind == .livePhoto
        }
        .onChange(of: fullScreenRequest?.wrappedValue ?? false) { _, requested in
            guard requested, let current else { return }
            fullScreenRequest?.wrappedValue = false
            activate(current)
        }
        .fullScreenCover(item: $fullScreenVideo) { video in
            VideoPlayerScreen(url: video.url)
        }
        .fullScreenCover(item: $fullScreenPhoto) { page in
            PhotoViewerScreen(media: media, startAt: page.index)
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
            }
            .overlay(alignment: .topLeading) { badge(for: current) }
            .overlay {
                if current.kind == .video {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 120))
                        .foregroundStyle(.white, .black.opacity(0.4))
                }
            }
        }
    }

    private var thumbnails: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 24) {
                ForEach(media) { item in
                    Button {
                        activate(item)
                    } label: {
                        RemoteImage(url: item.imageURL, contentMode: .fill)
                            .frame(width: 120, height: 160)
                            .overlay(alignment: .topLeading) { badge(for: item).scaleEffect(0.7, anchor: .topLeading) }
                    }
                    .buttonStyle(.card)
                    .focused($focusedThumbnail, equals: item.id)
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 20)
        }
        .scrollClipDisabled()
    }

    /// Thumbnails that only show where you are; the current one is outlined and kept in view.
    private var pageStrip: some View {
        VStack(spacing: 16) {
            ScrollViewReader { scroll in
                ScrollView(.horizontal) {
                    HStack(spacing: 24) {
                        ForEach(media) { item in
                            let isCurrent = item.id == current?.id
                            RemoteImage(url: item.imageURL, contentMode: .fill)
                                .frame(width: 120, height: 160)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(.white, lineWidth: isCurrent ? 5 : 0)
                                }
                                .overlay(alignment: .topLeading) {
                                    badge(for: item).scaleEffect(0.7, anchor: .topLeading)
                                }
                                .scaleEffect(isCurrent ? 1.08 : 1)
                                .opacity(isCurrent ? 1 : 0.6)
                                .id(item.id)
                        }
                    }
                    .padding(.horizontal, 40)
                    .padding(.vertical, 20)
                }
                .scrollClipDisabled()
                .scrollDisabled(true)
                .onChange(of: index) {
                    withAnimation(.easeOut(duration: 0.2)) { scroll.scrollTo(current?.id, anchor: .center) }
                }
            }
            .animation(.easeOut(duration: 0.15), value: index)

            Text("\(index + 1) / \(media.count)  ·  按遥控器左右键切换")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func badge(for item: MediaItem) -> some View {
        if item.kind == .livePhoto {
            Label("LIVE", systemImage: "livephoto")
                .font(.caption.bold())
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(.black.opacity(0.5), in: Capsule())
                .padding(20)
        }
    }

    private func activate(_ item: MediaItem) {
        index = media.firstIndex(of: item) ?? index
        switch item.kind {
        case .image, .livePhoto: fullScreenPhoto = PhotoPage(index: index)
        case .video: fullScreenVideo = item.videoURL.map(PlayableVideo.init)
        }
    }
}

/// Which picture to open full screen; drives `fullScreenCover(item:)`.
struct PhotoPage: Identifiable {
    let index: Int
    var id: Int { index }
}

/// Wraps a URL so it can drive `fullScreenCover(item:)`.
struct PlayableVideo: Identifiable {
    let url: URL
    var id: URL { url }
}

/// AsyncImage with a neutral placeholder and a broken-image icon on failure.
struct RemoteImage: View {
    let url: URL?
    let contentMode: ContentMode

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: contentMode)
            case .failure:
                Color.white.opacity(0.06)
                    .overlay { Image(systemName: "photo.badge.exclamationmark").foregroundStyle(.secondary) }
            default:
                Color.white.opacity(0.06).overlay { ProgressView() }
            }
        }
        .clipped()
    }
}

/// Plays a video once without controls (the motion part of a live photo).
struct PlayOnceVideoView: UIViewRepresentable {
    let url: URL
    let onFinish: () -> Void

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        var observer: NSObjectProtocol?

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        let player = AVPlayer(url: url)
        player.isMuted = true
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        let onFinish = onFinish
        view.observer = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: player.currentItem, queue: .main
        ) { _ in
            MainActor.assumeIsolated { onFinish() }
        }
        player.play()
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {}

    static func dismantleUIView(_ view: PlayerView, coordinator: ()) {
        view.playerLayer.player?.pause()
    }
}

/// Full-screen player with the system transport controls. Menu closes it.
struct VideoPlayerScreen: View {
    let url: URL
    @Environment(ShortcutCenter.self) private var shortcuts
    @State private var player: AVPlayer?

    var body: some View {
        VideoPlayer(player: player)
            .ignoresSafeArea()
            .onAppear {
                // Play/Pause belongs to the player here, not to the 点赞 shortcut.
                shortcuts.isPaused = true
                let player = AVPlayer(url: url)
                self.player = player
                player.play()
            }
            .onDisappear {
                shortcuts.isPaused = false
                player?.pause()
            }
    }
}
