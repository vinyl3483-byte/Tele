import SwiftUI
import AVFoundation
import UIKit

struct TriDotSpinnerIOS: View {
    var dotSize: CGFloat = 9
    private let coral = Color(red: 1.0, green: 45/255, blue: 85/255)
    private let green = Color(red: 34/255, green: 197/255, blue: 94/255)

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let phase = (t.truncatingRemainder(dividingBy: 1.1) / 1.1) * (.pi * 2.0)
            Canvas { canvas, size in
                let centerX = size.width / 2.0
                let centerY = size.height / 2.0
                let orbitRx = size.width * 0.34
                let baseR = dotSize / 2.0
                let colors = [coral, Color.white, green]

                let items: [(depth: Double, x: Double, r: Double, alpha: Double, color: Color)] = colors.enumerated().map { idx, color in
                    let angle = phase + Double(idx) * ((.pi * 2.0) / 3.0)
                    let x = centerX + cos(angle) * orbitRx
                    let depth = sin(angle)
                    let r = baseR * (0.72 + 0.42 * ((depth + 1.0) / 2.0))
                    let alpha = 0.65 + 0.35 * ((depth + 1.0) / 2.0)
                    return (depth, x, r, alpha, color)
                }.sorted { $0.depth < $1.depth }

                for item in items {
                    let shadowRect = CGRect(
                        x: item.x - item.r - 1.0,
                        y: centerY - item.r + 1.5,
                        width: (item.r + 1.0) * 2,
                        height: (item.r + 1.0) * 2
                    )
                    canvas.fill(Path(ellipseIn: shadowRect), with: .color(Color.black.opacity(0.25 * item.alpha)))
                    let rect = CGRect(
                        x: item.x - item.r,
                        y: centerY - item.r,
                        width: item.r * 2,
                        height: item.r * 2
                    )
                    canvas.fill(Path(ellipseIn: rect), with: .color(item.color.opacity(item.alpha)))
                }
            }
            .frame(width: 64, height: 28)
        }
    }
}

private struct HeartBurstIOS: Identifiable {
    let id = UUID()
    let point: CGPoint
}

private final class PlayerLayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        playerLayer.videoGravity = .resizeAspect
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private struct AVPlayerSurfaceIOS: UIViewRepresentable {
    let player: AVPlayer?

    func makeUIView(context: Context) -> PlayerLayerUIView {
        let view = PlayerLayerUIView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ uiView: PlayerLayerUIView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
        uiView.playerLayer.videoGravity = .resizeAspect
    }
}

struct AdaptiveFeedVideoCanvasIOS: View {
    let video: FeedVideoItem
    let isActive: Bool
    let player: AVPlayer
    let playbackState: FeedPlaybackStateIOS
    let resolveURL: (String) -> URL?
    let onSingleTap: () -> Void
    let onDoubleTapHeart: () -> Void

    @State private var bursts: [HeartBurstIOS] = []
    private let coral = Color(red: 1.0, green: 45/255, blue: 85/255)

    var body: some View {
        GeometryReader { geo in
            let fitted = TelefamCoreBridge.computeFeedFit(
                containerWidth: geo.size.width,
                containerHeight: geo.size.height,
                videoWidth: video.original_width,
                videoHeight: video.original_height,
                explicitRatio: video.aspect_ratio
            )
            let thumbURL = resolveURL(video.thumbnail_url)

            ZStack {
                Color.black

                if fitted.needsAmbientBackdrop, let thumbURL {
                    AsyncImage(url: thumbURL) { phase in
                        if case .success(let img) = phase {
                            img.resizable()
                                .scaledToFill()
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                                .blur(radius: 26)
                        }
                    }
                    Color.black.opacity(0.56)
                }

                ZStack {
                    if let thumbURL {
                        AsyncImage(url: thumbURL) { phase in
                            if case .success(let img) = phase {
                                img.resizable()
                                    .scaledToFit()
                            }
                        }
                    }

                    if isActive {
                        AVPlayerSurfaceIOS(player: player)
                    }
                }
                .frame(width: max(1, fitted.width), height: max(1, fitted.height))

                if isActive && playbackState.status == .paused {
                    Circle()
                        .fill(Color.black.opacity(0.45))
                        .frame(width: 68, height: 68)
                        .overlay(
                            PlayTriangleVectorIcon()
                                .fill(Color.white.opacity(0.92))
                                .frame(width: 28, height: 28)
                                .offset(x: 2)
                        )
                }

                if isActive && (playbackState.status == .loading || playbackState.loadingReason != .none) {
                    TriDotSpinnerIOS()
                }

                ForEach(bursts) { burst in
                    HeartVectorIcon()
                        .fill(coral)
                        .frame(width: 82, height: 82)
                        .position(burst.point)
                        .transition(.scale(scale: 1.4).combined(with: .opacity))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { location in
                let b = HeartBurstIOS(point: location)
                withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) {
                    bursts.append(b)
                }
                onDoubleTapHeart()
                Task {
                    try? await Task.sleep(nanoseconds: 700_000_000)
                    withAnimation(.easeOut(duration: 0.25)) {
                        bursts.removeAll { $0.id == b.id }
                    }
                }
            }
            .onTapGesture(count: 1) {
                onSingleTap()
            }
        }
    }
}

struct FeedView: View {
    @ObservedObject var viewModel: TelefamViewModel
    let networkQuality: TelefamNetworkQuality

    @State private var scrolledVideoId: String? = nil
    @State private var showCommentsSheet = false
    @State private var optionsVideo: FeedVideoItem? = nil
    @State private var reportVideo: FeedVideoItem? = nil
    @State private var ownerEditVideo: FeedVideoItem? = nil
    @State private var ownerVisibilityVideo: FeedVideoItem? = nil
    @State private var shareURLItem: URL? = nil
    @State private var confirmDeleteVideo: FeedVideoItem? = nil
    @State private var confirmBlockVideo: FeedVideoItem? = nil
    @State private var confirmMuteVideo: FeedVideoItem? = nil

    private let coral = Color(red: 1.0, green: 45/255, blue: 85/255)

    var body: some View {
        let videos = viewModel.activeFeedVideos
        let playback = viewModel.feedPlaybackState

        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                if videos.isEmpty && viewModel.isLoadingVideoFeed {
                    TriDotSpinnerIOS(dotSize: 10)
                } else if videos.isEmpty {
                    emptyOrOfflineView
                } else {
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(videos.enumerated()), id: \.element.video_id) { idx, video in
                                FeedVideoPageItemIOS(
                                    video: video,
                                    isActive: idx == viewModel.activeVideoIndex && viewModel.activeTab == .feeds && !viewModel.showModalFeedPlayer,
                                    player: viewModel.feedPlayback.player,
                                    playbackState: playback,
                                    resolveURL: { viewModel.api.resolveMediaURL($0) },
                                    networkQuality: networkQuality,
                                    onSingleTap: { viewModel.feedPlayback.togglePlayPause() },
                                    onDoubleTapLike: { Task { await viewModel.toggleVideoLike(video, forceLikeOnly: true) } },
                                    onRetry: { viewModel.feedPlayback.retryActive(networkQuality: networkQuality) },
                                    onFollowCreator: { Task { await viewModel.toggleFollowFromFeed(video) } },
                                    onLike: { Task { await viewModel.toggleVideoLike(video) } },
                                    onComment: { showCommentsSheet = true },
                                    onShare: {
                                        if let u = viewModel.api.resolveMediaURL(video.stream_url.isEmpty ? "/v1/videos/\(video.video_id)" : video.stream_url) {
                                            UIPasteboard.general.string = u.absoluteString
                                            shareURLItem = u
                                            Task { await viewModel.recordVideoShare(video, channel: "share_sheet") }
                                        }
                                    },
                                    onSave: { Task { await viewModel.toggleVideoSave(video) } },
                                    onMore: { optionsVideo = video },
                                    onHashtagTap: { tag in viewModel.openHashtagDiscovery(tag: tag, quality: networkQuality) },
                                    onAudioTap: { viewModel.openAudioDiscovery(audioId: video.audio.audio_id, quality: networkQuality) },
                                    onToggleMute: { viewModel.feedPlayback.toggleMute() }
                                )
                                .containerRelativeFrame(.vertical)
                                .frame(width: geo.size.width, height: geo.size.height)
                                .id(video.video_id)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollPosition(id: $scrolledVideoId)
                    .scrollTargetBehavior(.paging)
                    .scrollIndicators(.hidden)
                    .ignoresSafeArea()
                    .onChange(of: scrolledVideoId) { _, newId in
                        guard let newId, let idx = viewModel.activeFeedVideos.firstIndex(where: { $0.video_id == newId }) else { return }
                        viewModel.onFeedVideoSettled(index: idx, quality: networkQuality)
                    }
                }

                // Top Overlay Bar (LIVE · Following | For You · Search)
                VStack(spacing: 0) {
                    HStack {
                        Button {
                            viewModel.feedPlayback.setFeedVisible(false)
                            viewModel.showLiveComingSoon = true
                        } label: {
                            ZStack {
                                LiveTVVectorIcon()
                                    .stroke(Color.white, style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
                                    .frame(width: 24, height: 24)
                                Text("LIVE")
                                    .font(.system(size: 7.5, weight: .heavy))
                                    .foregroundColor(.white)
                                    .offset(y: 2)
                            }
                            .frame(width: 48, height: 48)
                        }

                        Spacer()

                        HStack(spacing: 22) {
                            topFeedTab(title: "Following", selected: viewModel.videoFeedTab == "following") {
                                scrolledVideoId = nil
                                viewModel.selectVideoFeedTab("following", quality: networkQuality)
                            }
                            topFeedTab(title: "For You", selected: viewModel.videoFeedTab == "for_you") {
                                scrolledVideoId = nil
                                viewModel.selectVideoFeedTab("for_you", quality: networkQuality)
                            }
                        }

                        Spacer()

                        Button {
                            viewModel.openFeedSearch(quality: networkQuality)
                        } label: {
                            SearchVectorIcon()
                                .stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                                .frame(width: 22, height: 22)
                                .frame(width: 48, height: 48)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    .background(
                        LinearGradient(
                            colors: [Color.black.opacity(0.55), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .ignoresSafeArea(edges: .top)
                    )

                    Spacer()
                }
            }
        }
        .onAppear {
            viewModel.feedPlayback.setFeedVisible(true)
            if viewModel.activeFeedVideos.isEmpty {
                Task { await viewModel.refreshVideoFeed(tab: viewModel.videoFeedTab, reset: true, quality: networkQuality) }
            } else {
                let idx = viewModel.activeVideoIndex
                if viewModel.activeFeedVideos.indices.contains(idx) {
                    scrolledVideoId = viewModel.activeFeedVideos[idx].video_id
                }
                viewModel.onFeedVideoSettled(index: idx, quality: networkQuality)
            }
        }
        .onDisappear {
            viewModel.feedPlayback.setFeedVisible(false)
        }
        .sheet(isPresented: $showCommentsSheet) {
            CommentsComingSoonSheetIOS()
        }
        .sheet(item: $optionsVideo) { vid in
            FeedVideoOptionsSheetIOS(
                video: vid,
                onReport: { reportVideo = vid },
                onRepost: { Task { await viewModel.toggleRepost(vid) } },
                onBlockCreator: { confirmBlockVideo = vid },
                onMuteCreator: { confirmMuteVideo = vid },
                onNotInterested: { Task { await viewModel.markVideoNotInterested(vid) } },
                onOwnerEdit: { ownerEditVideo = vid },
                onOwnerMarkPrivate: { Task { await viewModel.updateOwnerVideo(vid, title: nil, description: nil, visibility: "private") } },
                onOwnerVisibility: { ownerVisibilityVideo = vid },
                onOwnerDelete: { confirmDeleteVideo = vid }
            )
        }
        .sheet(item: $reportVideo) { vid in
            ReportVideoSheetIOS { reason, details in
                Task { await viewModel.submitVideoReport(vid, reason: reason, details: details) }
            }
        }
        .sheet(item: $ownerEditVideo) { vid in
            OwnerEditDetailsSheetIOS(initialTitle: vid.title, initialDescription: vid.description) { t, d in
                Task { await viewModel.updateOwnerVideo(vid, title: t, description: d, visibility: nil) }
            }
        }
        .sheet(item: $ownerVisibilityVideo) { vid in
            OwnerVisibilitySheetIOS(currentVisibility: vid.visibility) { nextVis in
                Task { await viewModel.updateOwnerVideo(vid, title: nil, description: nil, visibility: nextVis) }
            }
        }
        .sheet(isPresented: Binding(
            get: { shareURLItem != nil },
            set: { if !$0 { shareURLItem = nil } }
        )) {
            if let u = shareURLItem {
                ActivityShareSheetIOS(items: [u])
            }
        }
        .alert("Delete video?", isPresented: Binding(
            get: { confirmDeleteVideo != nil },
            set: { if !$0 { confirmDeleteVideo = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let vid = confirmDeleteVideo {
                    Task { await viewModel.deleteOwnerVideo(vid) }
                }
                confirmDeleteVideo = nil
            }
            Button("Cancel", role: .cancel) { confirmDeleteVideo = nil }
        }
        .alert("Block creator?", isPresented: Binding(
            get: { confirmBlockVideo != nil },
            set: { if !$0 { confirmBlockVideo = nil } }
        )) {
            Button("Block", role: .destructive) {
                if let vid = confirmBlockVideo {
                    Task { await viewModel.blockCreator(vid.creator_id) }
                }
                confirmBlockVideo = nil
            }
            Button("Cancel", role: .cancel) { confirmBlockVideo = nil }
        }
        .alert("Mute creator?", isPresented: Binding(
            get: { confirmMuteVideo != nil },
            set: { if !$0 { confirmMuteVideo = nil } }
        )) {
            Button("Mute", role: .destructive) {
                if let vid = confirmMuteVideo {
                    Task { await viewModel.muteCreator(vid.creator_id) }
                }
                confirmMuteVideo = nil
            }
            Button("Cancel", role: .cancel) { confirmMuteVideo = nil }
        }
    }

    private func topFeedTab(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: selected ? .bold : .semibold))
                    .foregroundColor(selected ? .white : .white.opacity(0.68))
                Capsule()
                    .fill(selected ? Color.white : Color.clear)
                    .frame(width: 26, height: 3)
            }
            .frame(minHeight: 44)
        }
    }

    private var emptyOrOfflineView: some View {
        VStack(spacing: 14) {
            Text(networkQuality == .offline ? "No internet." : (viewModel.videoFeedError ?? "No videos yet"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
            HStack(spacing: 12) {
                Button("Retry") {
                    Task { await viewModel.refreshVideoFeed(tab: viewModel.videoFeedTab, reset: true, quality: networkQuality) }
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 22)
                .frame(height: 44)
                .background(coral)
                .cornerRadius(22)

                if networkQuality == .offline {
                    Button("Settings") {
                        if let u = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(u)
                        }
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .frame(height: 44)
                    .background(Color.white.opacity(0.14))
                    .cornerRadius(22)
                }
            }
        }
        .padding(24)
    }
}

struct FeedVideoPageItemIOS: View {
    let video: FeedVideoItem
    let isActive: Bool
    let player: AVPlayer
    let playbackState: FeedPlaybackStateIOS
    let resolveURL: (String) -> URL?
    let networkQuality: TelefamNetworkQuality

    let onSingleTap: () -> Void
    let onDoubleTapLike: () -> Void
    let onRetry: () -> Void
    let onFollowCreator: () -> Void
    let onLike: () -> Void
    let onComment: () -> Void
    let onShare: () -> Void
    let onSave: () -> Void
    let onMore: () -> Void
    let onHashtagTap: (String) -> Void
    let onAudioTap: () -> Void
    let onToggleMute: () -> Void

    @State private var captionExpanded = false
    @Environment(\.openURL) private var openURL
    private let coral = Color(red: 1.0, green: 45/255, blue: 85/255)

    var body: some View {
        ZStack {
            AdaptiveFeedVideoCanvasIOS(
                video: video,
                isActive: isActive,
                player: player,
                playbackState: playbackState,
                resolveURL: resolveURL,
                onSingleTap: onSingleTap,
                onDoubleTapHeart: onDoubleTapLike
            )

            if isActive, case .error(let msg) = playbackState.status {
                VStack(spacing: 12) {
                    Text(networkQuality == .offline ? "No internet." : msg)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    Button("Retry", action: onRetry)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 22)
                        .frame(height: 44)
                        .background(coral)
                        .cornerRadius(22)
                }
                .padding(20)
                .background(Color.black.opacity(0.75))
                .cornerRadius(16)
            }

            // Bottom gradient scrim
            VStack {
                Spacer()
                LinearGradient(
                    colors: [Color.clear, Color.black.opacity(0.72)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 250)
            }
            .allowsHitTesting(false)

            // Bottom-left metadata + Right interaction rail + Bottom scrubber
            VStack(spacing: 0) {
                Spacer()
                HStack(alignment: .bottom, spacing: 12) {
                    bottomLeftColumn
                    Spacer(minLength: 4)
                    rightInteractionRail
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 16)

                if isActive && playbackState.durationMs > 0 {
                    let frac = min(1.0, max(0.0, Double(playbackState.positionMs) / Double(max(1, playbackState.durationMs))))
                    GeometryReader { barGeo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Color.white.opacity(0.22))
                            Rectangle()
                                .fill(Color.white.opacity(0.92))
                                .frame(width: barGeo.size.width * frac)
                        }
                    }
                    .frame(height: 2.5)
                }
            }
            .padding(.bottom, 68)
        }
    }

    private var rightInteractionRail: some View {
        VStack(spacing: 16) {
            ZStack(alignment: .bottom) {
                Circle()
                    .fill(Color(red: 36/255, green: 38/255, blue: 44/255))
                    .frame(width: 48, height: 48)
                    .overlay(
                        Text(String((video.creator_username.isEmpty ? video.creator_name : video.creator_username).prefix(2)).uppercased())
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                    )
                    .overlay(Circle().stroke(Color.white, lineWidth: 1.5))

                if !video.is_owner && !video.is_following_creator {
                    Button(action: onFollowCreator) {
                        Circle()
                            .fill(coral)
                            .frame(width: 22, height: 22)
                            .overlay(
                                PlusVectorIcon()
                                    .stroke(Color.white, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                                    .frame(width: 11, height: 11)
                            )
                    }
                    .offset(y: 9)
                }
            }
            .padding(.bottom, 6)

            railActionButton(
                count: TelefamCoreBridge.formatFeedCount(video.likes_count),
                action: onLike
            ) {
                HeartVectorIcon()
                    .fill(video.is_liked ? coral : Color.white)
                    .frame(width: 30, height: 30)
            }

            railActionButton(
                count: TelefamCoreBridge.formatFeedCount(video.comments_count),
                action: onComment
            ) {
                FeedCommentBubbleVectorIcon()
                    .fill(Color.white)
                    .frame(width: 29, height: 29)
            }

            railActionButton(
                count: TelefamCoreBridge.formatFeedCount(video.shares_count),
                action: onShare
            ) {
                FeedShareVectorIcon()
                    .stroke(video.is_liked ? Color.white : coral, style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round))
                    .frame(width: 27, height: 27)
            }

            railActionButton(
                count: TelefamCoreBridge.formatFeedCount(video.saves_count),
                action: onSave
            ) {
                BookmarkVectorIcon()
                    .fill(video.is_saved ? coral : Color.clear)
                    .overlay(
                        BookmarkVectorIcon()
                            .stroke(coral, style: StrokeStyle(lineWidth: 2.1, lineCap: .round, lineJoin: .round))
                    )
                    .frame(width: 26, height: 28)
            }

            Button(action: onMore) {
                MoreHorizVectorIcon()
                    .fill(Color.white)
                    .frame(width: 26, height: 26)
                    .frame(width: 48, height: 40)
            }
        }
    }

    private func railActionButton<Icon: View>(
        count: String,
        action: @escaping () -> Void,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                icon()
                Text(count)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(minWidth: 48, minHeight: 48)
        }
    }

    private var bottomLeftColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !video.recommendation_label.isEmpty {
                HStack(spacing: 6) {
                    AutoSparkleVectorIcon()
                        .fill(coral)
                        .frame(width: 13, height: 13)
                    Text(video.recommendation_label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.92))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.45))
                .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
                .clipShape(Capsule())
            }

            Text(video.creator_username.isEmpty ? video.creator_name : video.creator_username)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)

            if !video.description.isEmpty || !video.hashtags.isEmpty {
                captionBlock
            }

            HStack(spacing: 10) {
                Button(action: onAudioTap) {
                    HStack(spacing: 6) {
                        MusicNoteVectorIcon()
                            .stroke(Color.white, style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
                            .frame(width: 15, height: 15)
                        Text(video.audio.title.isEmpty ? "Original sound" : video.audio.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        EqualizerVectorIcon()
                            .stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .frame(width: 14, height: 14)
                    }
                    .frame(minHeight: 36)
                }

                Button(action: onToggleMute) {
                    Group {
                        if playbackState.isMuted {
                            VolumeOffVectorIcon()
                                .stroke(Color.white, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                        } else {
                            VolumeOnVectorIcon()
                                .stroke(Color.white, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                        }
                    }
                    .frame(width: 15, height: 15)
                    .frame(width: 30, height: 30)
                    .background(Color.black.opacity(0.45))
                    .clipShape(Circle())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var captionBlock: some View {
        let baseDesc = video.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let extraTags = video.hashtags.filter { !baseDesc.localizedCaseInsensitiveContains("#\($0)") }
        let fullText = ([baseDesc] + [extraTags.map { "#\($0)" }.joined(separator: " ")])
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        VStack(alignment: .leading, spacing: 4) {
            Text(attributedCaption(fullText))
                .font(.system(size: 14))
                .lineLimit(captionExpanded ? 8 : 2)
                .environment(\.openURL, OpenURLAction { url in
                    if url.scheme == "telefam-tag", let host = url.host {
                        onHashtagTap(host)
                        return .handled
                    }
                    openURL(url)
                    return .handled
                })

            if fullText.count > 75 || extraTags.count > 2 {
                Button(captionExpanded ? "Read less" : "Read more") {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        captionExpanded.toggle()
                    }
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.75))
            }
        }
    }

    private func attributedCaption(_ text: String) -> AttributedString {
        var attr = AttributedString(text)
        attr.foregroundColor = .white

        if let tagRegex = try? NSRegularExpression(pattern: "#([A-Za-z0-9_]{1,40})") {
            let ns = text as NSString
            let matches = tagRegex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            for m in matches {
                if let swiftRange = Range(m.range, in: text),
                   let tagRange = Range(m.range(at: 1), in: text),
                   let start = AttributedString.Index(swiftRange.lowerBound, within: attr),
                   let end = AttributedString.Index(swiftRange.upperBound, within: attr) {
                    let tag = String(text[tagRange]).lowercased()
                    attr[start..<end].foregroundColor = coral
                    attr[start..<end].link = URL(string: "telefam-tag://\(tag)")
                }
            }
        }
        return attr
    }
}

private struct ActivityShareSheetIOS: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
