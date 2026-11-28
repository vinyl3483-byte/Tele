import SwiftUI

struct FeedThumbnailGridCellIOS: View {
    let video: FeedVideoItem
    let resolveURL: (String) -> URL?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color(red: 22/255, green: 24/255, blue: 29/255)

            if let thumbURL = resolveURL(video.thumbnail_url) {
                AsyncImage(url: thumbURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Color(red: 22/255, green: 24/255, blue: 29/255)
                    }
                }
            }

            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.68)],
                startPoint: .center,
                endPoint: .bottom
            )

            HStack(spacing: 4) {
                PlayTriangleVectorIcon()
                    .fill(Color.white)
                    .frame(width: 11, height: 11)
                Text(TelefamCoreBridge.formatFeedCount(video.views_count))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 6)
        }
        .aspectRatio(0.75, contentMode: .fill)
        .clipped()
        .cornerRadius(6)
    }
}

struct LiveComingSoonView: View {
    let onClose: () -> Void
    private let coral = Color(red: 1.0, green: 45/255, blue: 85/255)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                HStack {
                    Button(action: onClose) {
                        ArrowLeftVectorIcon()
                            .stroke(Color.white, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                            .frame(width: 22, height: 22)
                            .frame(width: 48, height: 48)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)

                Spacer()

                ZStack {
                    Circle()
                        .fill(coral.opacity(0.16))
                        .frame(width: 84, height: 84)
                    LiveTVVectorIcon()
                        .stroke(coral, style: StrokeStyle(lineWidth: 2.1, lineCap: .round, lineJoin: .round))
                        .frame(width: 36, height: 36)
                }

                Text("LIVE Coming Soon")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)

                Text("Live streaming is not available yet.")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.68))

                Button("Back", action: onClose)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 28)
                    .frame(height: 46)
                    .background(coral)
                    .cornerRadius(23)
                    .padding(.top, 6)

                Spacer()
            }
        }
        .telefamSwipeBack(onBack: onClose)
    }
}

struct FeedSearchView: View {
    @ObservedObject var viewModel: TelefamViewModel
    let networkQuality: TelefamNetworkQuality

    private let coral = Color(red: 1.0, green: 45/255, blue: 85/255)
    private let tabs = ["Videos", "Hashtags", "Creators", "Sounds"]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    viewModel.showFeedSearch = false
                    viewModel.resumeMainFeedIfVisible(quality: networkQuality)
                } label: {
                    ArrowLeftVectorIcon()
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                        .frame(width: 20, height: 20)
                        .frame(width: 44, height: 44)
                }

                HStack(spacing: 8) {
                    SearchVectorIcon()
                        .stroke(Color.white.opacity(0.65), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 16, height: 16)
                    TextField(
                        "",
                        text: Binding(
                            get: { viewModel.feedSearchQuery },
                            set: { viewModel.updateFeedSearchQuery($0, quality: networkQuality) }
                        ),
                        prompt: Text("Search videos, hashtags, creators, sounds")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.55))
                    )
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit {
                        Task { await viewModel.executeFeedSearch(query: viewModel.feedSearchQuery, reset: true, quality: networkQuality) }
                    }

                    if !viewModel.feedSearchQuery.isEmpty {
                        Button {
                            viewModel.updateFeedSearchQuery("", quality: networkQuality)
                        } label: {
                            CloseVectorIcon()
                                .stroke(Color.white.opacity(0.7), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                                .frame(width: 14, height: 14)
                                .frame(width: 30, height: 30)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 42)
                .background(Color.white.opacity(0.1))
                .cornerRadius(21)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            HStack(spacing: 0) {
                ForEach(Array(tabs.enumerated()), id: \.offset) { idx, title in
                    let selected = viewModel.feedSearchTab == idx
                    Button {
                        viewModel.feedSearchTab = idx
                    } label: {
                        VStack(spacing: 6) {
                            Text(title)
                                .font(.system(size: 14, weight: selected ? .bold : .medium))
                                .foregroundColor(selected ? .white : .white.opacity(0.6))
                            Capsule()
                                .fill(selected ? coral : Color.clear)
                                .frame(height: 2.5)
                                .padding(.horizontal, 14)
                        }
                        .frame(maxWidth: .infinity, minHeight: 42)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
            }

            if viewModel.feedSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                searchDiscoveryPrompts
            }

            if viewModel.isSearchingFeed && viewModel.feedSearchResults == nil {
                Spacer()
                TriDotSpinnerIOS()
                Spacer()
            } else {
                searchTabBody
            }
        }
        .background(Color.black.ignoresSafeArea())
        .telefamSwipeBack {
            viewModel.showFeedSearch = false
            viewModel.resumeMainFeedIfVisible(quality: networkQuality)
        }
    }

    @ViewBuilder
    private var searchDiscoveryPrompts: some View {
        let serverRecents = viewModel.feedSearchResults?.recent_searches ?? []
        let trending = viewModel.feedSearchResults?.trending ?? []
        let localOnly = viewModel.localRecentSearches.filter { local in
            !serverRecents.contains { $0.query.caseInsensitiveCompare(local) == .orderedSame }
        }

        if !serverRecents.isEmpty || !localOnly.isEmpty || !trending.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if !serverRecents.isEmpty || !localOnly.isEmpty {
                    HStack {
                        Text("Recent")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.75))
                        Spacer()
                        Button("Clear") {
                            Task { await viewModel.clearAllSearchHistory(quality: networkQuality) }
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(coral)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(serverRecents) { item in
                                recentChip(label: item.query) {
                                    viewModel.updateFeedSearchQuery(item.query, quality: networkQuality)
                                } onDelete: {
                                    Task { await viewModel.deleteRecentSearch(id: item.id, query: item.query, quality: networkQuality) }
                                }
                            }
                            ForEach(localOnly, id: \.self) { q in
                                recentChip(label: q) {
                                    viewModel.updateFeedSearchQuery(q, quality: networkQuality)
                                } onDelete: {
                                    Task { await viewModel.deleteRecentSearch(id: "", query: q, quality: networkQuality) }
                                }
                            }
                        }
                    }
                }

                if !trending.isEmpty {
                    Text("Trending")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.75))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(trending, id: \.self) { term in
                                Button {
                                    viewModel.updateFeedSearchQuery(term, quality: networkQuality)
                                } label: {
                                    Text(term)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(Color.white.opacity(0.09))
                                        .cornerRadius(16)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private func recentChip(label: String, onTap: @escaping () -> Void, onDelete: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Button(action: onTap) {
                Text(label)
                    .font(.system(size: 13))
                    .foregroundColor(.white)
            }
            Button(action: onDelete) {
                CloseVectorIcon()
                    .stroke(Color.white.opacity(0.6), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                    .frame(width: 10, height: 10)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.1))
        .cornerRadius(16)
    }

    @ViewBuilder
    private var searchTabBody: some View {
        let payload = viewModel.feedSearchResults

        switch viewModel.feedSearchTab {
        case 0:
            let videos = payload?.videos ?? []
            if videos.isEmpty {
                emptySearchMessage(networkQuality == .offline ? "No internet." : "No videos found")
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 4)], spacing: 4) {
                        ForEach(Array(videos.enumerated()), id: \.element.video_id) { idx, vid in
                            Button {
                                viewModel.openModalFeedPlayer(videos: videos, initialIndex: idx, title: viewModel.feedSearchQuery.isEmpty ? "Videos" : viewModel.feedSearchQuery)
                            } label: {
                                FeedThumbnailGridCellIOS(video: vid, resolveURL: { viewModel.api.resolveMediaURL($0) })
                            }
                            .onAppear {
                                if idx >= videos.count - 3 && payload?.has_more == true {
                                    Task { await viewModel.executeFeedSearch(query: viewModel.feedSearchQuery, reset: false, quality: networkQuality) }
                                }
                            }
                        }
                    }
                    .padding(6)
                }
            }
        case 1:
            let tags = payload?.hashtags ?? []
            if tags.isEmpty {
                emptySearchMessage("No hashtags found")
            } else {
                List(tags) { tag in
                    Button {
                        viewModel.openHashtagDiscovery(tag: tag.tag, quality: networkQuality)
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(coral.opacity(0.18))
                                .frame(width: 42, height: 42)
                                .overlay(Text("#").font(.system(size: 18, weight: .bold)).foregroundColor(coral))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("#\(tag.tag)")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.white)
                                Text("\(TelefamCoreBridge.formatFeedCount(tag.post_count)) videos")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                            Spacer()
                            ChevronRightVectorIcon()
                                .stroke(Color.white.opacity(0.5), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                                .frame(width: 14, height: 14)
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(Color.black)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        case 2:
            let creators = payload?.creators ?? []
            if creators.isEmpty {
                emptySearchMessage("No creators found")
            } else {
                List(creators) { creator in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color(red: 36/255, green: 38/255, blue: 44/255))
                            .frame(width: 44, height: 44)
                            .overlay(
                                Text(String((creator.full_name.isEmpty ? creator.username : creator.full_name).prefix(2)).uppercased())
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                            )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(creator.full_name.isEmpty ? creator.username : creator.full_name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                            Text("@\(creator.username)")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        Spacer()
                        Button {
                            Task {
                                if let sess = viewModel.session, viewModel.core.allowFollowRateLimit(accountKey: sess.user_id) {
                                    let _ = try? await viewModel.withAuthedRetry { tok in
                                        try await viewModel.api.setFollowState(token: tok, targetUserId: creator.user_id, follow: !creator.is_following)
                                    }
                                    await viewModel.executeFeedSearch(query: viewModel.feedSearchQuery, reset: true, quality: networkQuality)
                                } else {
                                    viewModel.showContactsToast("Try again later")
                                }
                            }
                        } label: {
                            Text(creator.is_following ? "Following" : "Follow")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(creator.is_following ? .white : .white)
                                .padding(.horizontal, 16)
                                .frame(height: 34)
                                .background(creator.is_following ? Color.white.opacity(0.14) : coral)
                                .cornerRadius(17)
                        }
                    }
                    .listRowBackground(Color.black)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        default:
            let audios = payload?.audios ?? []
            if audios.isEmpty {
                emptySearchMessage("No sounds found")
            } else {
                List(audios) { audio in
                    Button {
                        viewModel.openAudioDiscovery(audioId: audio.audio_id, quality: networkQuality)
                    } label: {
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(coral.opacity(0.18))
                                .frame(width: 44, height: 44)
                                .overlay(
                                    MusicNoteVectorIcon()
                                        .stroke(coral, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                                        .frame(width: 20, height: 20)
                                )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(audio.title.isEmpty ? "Original sound" : audio.title)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                Text("\(audio.artist.isEmpty ? "Creator" : audio.artist) · \(TelefamCoreBridge.formatFeedCount(audio.usage_count)) videos")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                            Spacer()
                            ChevronRightVectorIcon()
                                .stroke(Color.white.opacity(0.5), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                                .frame(width: 14, height: 14)
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(Color.black)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func emptySearchMessage(_ msg: String) -> some View {
        VStack {
            Spacer()
            Text(msg)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white.opacity(0.65))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

struct HashtagDiscoveryView: View {
    let tag: String
    @ObservedObject var viewModel: TelefamViewModel
    let networkQuality: TelefamNetworkQuality

    private let coral = Color(red: 1.0, green: 45/255, blue: 85/255)

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    viewModel.activeHashtagTag = nil
                    viewModel.resumeMainFeedIfVisible(quality: networkQuality)
                } label: {
                    ArrowLeftVectorIcon()
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                        .frame(width: 22, height: 22)
                        .frame(width: 44, height: 44)
                }
                Text("#\(tag)")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if let payload = viewModel.hashtagDiscovery {
                HStack(spacing: 16) {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(coral.opacity(0.18))
                        .frame(width: 64, height: 64)
                        .overlay(Text("#").font(.system(size: 30, weight: .bold)).foregroundColor(coral))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("#\(payload.tag)")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                        Text("\(TelefamCoreBridge.formatFeedCount(payload.video_count)) videos · \(TelefamCoreBridge.formatFeedCount(payload.views_count)) views")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                if payload.videos.isEmpty {
                    Spacer()
                    Text("No videos yet")
                        .foregroundColor(.white.opacity(0.65))
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 4)], spacing: 4) {
                            ForEach(Array(payload.videos.enumerated()), id: \.element.video_id) { idx, vid in
                                Button {
                                    viewModel.openModalFeedPlayer(videos: payload.videos, initialIndex: idx, title: "#\(payload.tag)")
                                } label: {
                                    FeedThumbnailGridCellIOS(video: vid, resolveURL: { viewModel.api.resolveMediaURL($0) })
                                }
                                .onAppear {
                                    if idx >= payload.videos.count - 3 && payload.has_more {
                                        Task { await viewModel.loadHashtagDiscovery(tag: tag, reset: false, quality: networkQuality) }
                                    }
                                }
                            }
                        }
                        .padding(6)
                    }
                }
            } else if viewModel.isLoadingHashtagDiscovery {
                Spacer()
                TriDotSpinnerIOS()
                Spacer()
            } else {
                Spacer()
                Text(networkQuality == .offline ? "No internet." : "No videos yet")
                    .foregroundColor(.white.opacity(0.65))
                Spacer()
            }
        }
        .background(Color.black.ignoresSafeArea())
        .telefamSwipeBack {
            viewModel.activeHashtagTag = nil
            viewModel.resumeMainFeedIfVisible(quality: networkQuality)
        }
    }
}

struct AudioDiscoveryView: View {
    let audioId: String
    @ObservedObject var viewModel: TelefamViewModel
    let networkQuality: TelefamNetworkQuality

    private let coral = Color(red: 1.0, green: 45/255, blue: 85/255)

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    viewModel.activeAudioId = nil
                    viewModel.resumeMainFeedIfVisible(quality: networkQuality)
                } label: {
                    ArrowLeftVectorIcon()
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                        .frame(width: 22, height: 22)
                        .frame(width: 44, height: 44)
                }
                Text("Sound")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if let payload = viewModel.audioDiscovery {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(coral.opacity(0.18))
                                .frame(width: 72, height: 72)
                            if let artURL = URL(string: payload.audio.artwork_url), !payload.audio.artwork_url.isEmpty {
                                AsyncImage(url: artURL) { phase in
                                    if case .success(let img) = phase {
                                        img.resizable().scaledToFill()
                                            .frame(width: 72, height: 72)
                                            .cornerRadius(14)
                                    } else {
                                        MusicNoteVectorIcon()
                                            .stroke(coral, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                                            .frame(width: 28, height: 28)
                                    }
                                }
                            } else {
                                MusicNoteVectorIcon()
                                    .stroke(coral, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                                    .frame(width: 28, height: 28)
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(payload.audio.title.isEmpty ? "Original sound" : payload.audio.title)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(2)
                            if !payload.audio.artist.isEmpty {
                                Text(payload.audio.artist)
                                    .font(.system(size: 14))
                                    .foregroundColor(.white.opacity(0.72))
                            }
                            Text("\(TelefamCoreBridge.formatFeedCount(payload.audio.usage_count)) videos")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        Spacer()
                    }

                    Button {
                        viewModel.useSoundInPostComposer(payload.audio)
                    } label: {
                        HStack(spacing: 8) {
                            MusicNoteVectorIcon()
                                .stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                                .frame(width: 16, height: 16)
                            Text("Use this sound")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(coral)
                        .cornerRadius(23)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                if payload.videos.isEmpty {
                    Spacer()
                    Text("No videos yet")
                        .foregroundColor(.white.opacity(0.65))
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 4)], spacing: 4) {
                            ForEach(Array(payload.videos.enumerated()), id: \.element.video_id) { idx, vid in
                                Button {
                                    viewModel.openModalFeedPlayer(videos: payload.videos, initialIndex: idx, title: payload.audio.title.isEmpty ? "Sound" : payload.audio.title)
                                } label: {
                                    FeedThumbnailGridCellIOS(video: vid, resolveURL: { viewModel.api.resolveMediaURL($0) })
                                }
                                .onAppear {
                                    if idx >= payload.videos.count - 3 && payload.has_more {
                                        Task { await viewModel.loadAudioDiscovery(audioId: audioId, reset: false, quality: networkQuality) }
                                    }
                                }
                            }
                        }
                        .padding(6)
                    }
                }
            } else if viewModel.isLoadingAudioDiscovery {
                Spacer()
                TriDotSpinnerIOS()
                Spacer()
            } else {
                Spacer()
                Text(networkQuality == .offline ? "No internet." : "No videos yet")
                    .foregroundColor(.white.opacity(0.65))
                Spacer()
            }
        }
        .background(Color.black.ignoresSafeArea())
        .telefamSwipeBack {
            viewModel.activeAudioId = nil
            viewModel.resumeMainFeedIfVisible(quality: networkQuality)
        }
    }
}

struct FeedModalPlayerView: View {
    @ObservedObject var viewModel: TelefamViewModel
    let networkQuality: TelefamNetworkQuality

    @State private var scrolledVideoId: String? = nil
    @State private var activeIndex: Int = 0
    @State private var showCommentsSheet = false
    @State private var optionsVideo: FeedVideoItem? = nil
    @State private var reportVideo: FeedVideoItem? = nil
    @State private var ownerEditVideo: FeedVideoItem? = nil
    @State private var ownerVisibilityVideo: FeedVideoItem? = nil
    @State private var shareURLItem: URL? = nil
    @State private var confirmDeleteVideo: FeedVideoItem? = nil

    var body: some View {
        let videos = viewModel.modalFeedVideos
        let playback = viewModel.feedPlaybackState

        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(videos.enumerated()), id: \.element.video_id) { idx, video in
                            FeedVideoPageItemIOS(
                                video: video,
                                isActive: idx == activeIndex,
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
                                onHashtagTap: { tag in
                                    viewModel.closeModalFeedPlayer()
                                    viewModel.openHashtagDiscovery(tag: tag, quality: networkQuality)
                                },
                                onAudioTap: {
                                    viewModel.closeModalFeedPlayer()
                                    viewModel.openAudioDiscovery(audioId: video.audio.audio_id, quality: networkQuality)
                                },
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
                    guard let newId, let idx = videos.firstIndex(where: { $0.video_id == newId }) else { return }
                    activeIndex = idx
                    let upcoming = Array(videos.dropFirst(idx + 1).prefix(5))
                    viewModel.feedPlayback.playVideo(videos[idx], upcoming: upcoming, networkQuality: networkQuality)
                }

                VStack {
                    HStack(spacing: 10) {
                        Button {
                            viewModel.closeModalFeedPlayer(quality: networkQuality)
                        } label: {
                            ArrowLeftVectorIcon()
                                .stroke(Color.white, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                                .frame(width: 22, height: 22)
                                .frame(width: 48, height: 48)
                        }
                        Text(viewModel.modalFeedTitle)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    .background(
                        LinearGradient(
                            colors: [Color.black.opacity(0.6), Color.clear],
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
            let start = min(max(0, viewModel.modalFeedInitialIndex), max(0, viewModel.modalFeedVideos.count - 1))
            activeIndex = start
            if viewModel.modalFeedVideos.indices.contains(start) {
                scrolledVideoId = viewModel.modalFeedVideos[start].video_id
                let upcoming = Array(viewModel.modalFeedVideos.dropFirst(start + 1).prefix(5))
                viewModel.feedPlayback.playVideo(viewModel.modalFeedVideos[start], upcoming: upcoming, networkQuality: networkQuality)
            }
        }
        .telefamSwipeBack {
            viewModel.closeModalFeedPlayer(quality: networkQuality)
        }
        .sheet(isPresented: $showCommentsSheet) {
            CommentsComingSoonSheetIOS()
        }
        .sheet(item: $optionsVideo) { vid in
            FeedVideoOptionsSheetIOS(
                video: vid,
                onReport: { reportVideo = vid },
                onRepost: { Task { await viewModel.toggleRepost(vid) } },
                onBlockCreator: { Task { await viewModel.blockCreator(vid.creator_id) } },
                onMuteCreator: { Task { await viewModel.muteCreator(vid.creator_id) } },
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
                ModalShareSheetIOS(items: [u])
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
    }
}

private struct ModalShareSheetIOS: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
