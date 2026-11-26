import Foundation
import AVFoundation
import Combine

enum FeedLoadingReasonIOS: Equatable {
    case none
    case initialLoad
    case buffering
    case qualitySwitch
    case reconnecting
}

enum FeedPlaybackStatusIOS: Equatable {
    case idle
    case loading
    case ready
    case playing
    case paused
    case error(String)
}

struct FeedPlaybackStateIOS: Equatable {
    var activeVideoId: String = ""
    var status: FeedPlaybackStatusIOS = .idle
    var loadingReason: FeedLoadingReasonIOS = .none
    var isMuted: Bool = false
    var positionMs: Int64 = 0
    var durationMs: Int64 = 0
    var bufferedPct: Double = 0.0
    var rewatchCount: Int = 0
}

@MainActor
final class FeedPlaybackManager: ObservableObject {
    @Published var playbackState = FeedPlaybackStateIOS()

    let player: AVPlayer = {
        let p = AVPlayer()
        p.automaticallyWaitsToMinimizeStalling = true
        p.actionAtItemEnd = .none
        return p
    }()

    private let mediaCacheURLSession: URLSession
    private var activeVideo: FeedVideoItem?
    private var triedMp4Fallback = false
    private var triedSignedRefresh = false
    private var isAppForeground = true
    private var isFeedVisible = false
    private var userPaused = false
    private var watchAccumulatedMs: Int64 = 0
    private var lastTickWallMs: Int64 = 0
    private var lastReportedMs: Int64 = 0
    private var rewatchDelta = 0
    private var viewReportedForVideoId = ""

    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var failObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var bufferObservation: NSKeyValueObservation?
    private var keepUpObservation: NSKeyValueObservation?
    private var prefetchTask: Task<Void, Never>?

    private var previewPlayers: [String: AVPlayer] = [:]
    private var previewOrder: [String] = []

    var onRefreshSignedURL: ((String) async -> FeedVideoItem?)?
    var onReportWatchProgress: ((_ videoId: String, _ watchMs: Int64, _ positionMs: Int64, _ completionPct: Double, _ rewatchDelta: Int, _ isViewPing: Bool) -> Void)?

    private let resolveURL: (String) -> URL?

    init(resolveURL: @escaping (String) -> URL?) {
        self.resolveURL = resolveURL
        let cache = URLCache(
            memoryCapacity: 24 * 1024 * 1024,
            diskCapacity: 192 * 1024 * 1024,
            diskPath: "telefam_feed_media_cache"
        )
        let cfg = URLSessionConfiguration.default
        cfg.urlCache = cache
        cfg.requestCachePolicy = .returnCacheDataElseLoad
        cfg.timeoutIntervalForRequest = 15
        self.mediaCacheURLSession = URLSession(configuration: cfg)

        configureAudioSession()
        installPeriodicObserver()
    }

    deinit {
        if let obs = timeObserver {
            player.removeTimeObserver(obs)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        if let failObserver {
            NotificationCenter.default.removeObserver(failObserver)
        }
        statusObservation?.invalidate()
        bufferObservation?.invalidate()
        keepUpObservation?.invalidate()
    }

    private func configureAudioSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, options: [])
        try? session.setActive(true)
        #endif
    }

    private func installPeriodicObserver() {
        let interval = CMTime(value: 250, timescale: 1000)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] cmTime in
            Task { @MainActor [weak self] in
                self?.onTimeTick(cmTime)
            }
        }
    }

    func setFeedVisible(_ visible: Bool) {
        isFeedVisible = visible
        if !visible {
            player.pause()
            releaseAllPreviews()
            flushProgress(force: true)
            if playbackState.status == .playing {
                playbackState.status = .paused
            }
        } else if isAppForeground && !userPaused, activeVideo != nil {
            player.play()
        }
    }

    func setAppForeground(_ foreground: Bool) {
        isAppForeground = foreground
        if !foreground {
            player.pause()
            flushProgress(force: true)
            if playbackState.status == .playing {
                playbackState.status = .paused
            }
        } else if isFeedVisible && !userPaused, activeVideo != nil {
            player.play()
        }
    }

    func togglePlayPause() {
        guard activeVideo != nil else { return }
        if player.rate > 0 {
            userPaused = true
            player.pause()
            playbackState.status = .paused
            flushProgress(force: true)
        } else {
            userPaused = false
            configureAudioSession()
            player.play()
            lastTickWallMs = Int64(Date().timeIntervalSince1970 * 1000)
            playbackState.status = .playing
        }
    }

    func toggleMute() {
        setMuted(!playbackState.isMuted)
    }

    func setMuted(_ muted: Bool) {
        player.isMuted = muted
        playbackState.isMuted = muted
    }

    func playVideo(
        _ video: FeedVideoItem,
        upcoming: [FeedVideoItem],
        networkQuality: TelefamNetworkQuality
    ) {
        let sameVideo = (activeVideo?.video_id == video.video_id)
        if !sameVideo {
            flushProgress(force: true)
            activeVideo = video
            triedMp4Fallback = false
            triedSignedRefresh = false
            userPaused = false
            watchAccumulatedMs = 0
            lastReportedMs = 0
            rewatchDelta = 0
            viewReportedForVideoId = ""
            lastTickWallMs = Int64(Date().timeIntervalSince1970 * 1000)
            playbackState = FeedPlaybackStateIOS(
                activeVideoId: video.video_id,
                status: .loading,
                loadingReason: .initialLoad,
                isMuted: playbackState.isMuted,
                positionMs: 0,
                durationMs: max(0, video.duration_ms),
                bufferedPct: 0,
                rewatchCount: 0
            )
            loadVideoURL(for: video, useFallbackMP4: false)
        } else if isFeedVisible && isAppForeground && !userPaused {
            player.play()
        }

        scheduleAheadPrefetch(upcoming: upcoming, networkQuality: networkQuality)
    }

    func retryActive(networkQuality: TelefamNetworkQuality) {
        guard let video = activeVideo else { return }
        triedMp4Fallback = false
        triedSignedRefresh = false
        userPaused = false
        playbackState.status = .loading
        playbackState.loadingReason = networkQuality == .offline ? .reconnecting : .initialLoad
        loadVideoURL(for: video, useFallbackMP4: false)
    }

    func applyRefreshedVideo(_ updated: FeedVideoItem) {
        guard activeVideo?.video_id == updated.video_id else { return }
        activeVideo = updated
        loadVideoURL(for: updated, useFallbackMP4: triedMp4Fallback)
    }

    private func loadVideoURL(for video: FeedVideoItem, useFallbackMP4: Bool) {
        let nowSec = Int64(Date().timeIntervalSince1970)
        if video.url_expires_at > 0 && nowSec >= (video.url_expires_at - 15) && !triedSignedRefresh {
            triedSignedRefresh = true
            playbackState.loadingReason = .reconnecting
            Task { [weak self] in
                guard let self else { return }
                if let refreshed = await self.onRefreshSignedURL?(video.video_id) {
                    self.activeVideo = refreshed
                    self.loadVideoURL(for: refreshed, useFallbackMP4: false)
                }
            }
            return
        }

        let raw = (useFallbackMP4 && !video.fallback_mp4_url.isEmpty)
            ? video.fallback_mp4_url
            : (video.stream_url.isEmpty ? video.fallback_mp4_url : video.stream_url)

        guard let url = resolveURL(raw) else {
            playbackState.status = .error("Error has occurred, try again later.")
            playbackState.loadingReason = .none
            return
        }

        clearItemObservers()
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 12.0

        statusObservation = item.observe(\.status, options: [.new]) { [weak self] observed, _ in
            Task { @MainActor [weak self] in
                guard let self, self.player.currentItem === observed else { return }
                switch observed.status {
                case .readyToPlay:
                    self.playbackState.loadingReason = .none
                    if self.isFeedVisible && self.isAppForeground && !self.userPaused {
                        self.player.play()
                        self.playbackState.status = .playing
                        self.lastTickWallMs = Int64(Date().timeIntervalSince1970 * 1000)
                        if self.viewReportedForVideoId != self.activeVideo?.video_id,
                           let vid = self.activeVideo?.video_id {
                            self.viewReportedForVideoId = vid
                            self.onReportWatchProgress?(vid, 0, 0, 0.0, 0, true)
                        }
                    } else {
                        self.playbackState.status = .ready
                    }
                case .failed:
                    self.handleItemFailure()
                default:
                    break
                }
            }
        }

        bufferObservation = item.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self] observed, _ in
            Task { @MainActor [weak self] in
                guard let self, self.player.currentItem === observed else { return }
                if observed.isPlaybackBufferEmpty {
                    self.playbackState.loadingReason = .buffering
                }
            }
        }

        keepUpObservation = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] observed, _ in
            Task { @MainActor [weak self] in
                guard let self, self.player.currentItem === observed else { return }
                if observed.isPlaybackLikelyToKeepUp {
                    self.playbackState.loadingReason = .none
                }
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.rewatchDelta += 1
                self.playbackState.rewatchCount += 1
                self.flushProgress(force: true)
                self.player.seek(to: .zero)
                if self.isFeedVisible && self.isAppForeground && !self.userPaused {
                    self.player.play()
                }
            }
        }

        failObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleItemFailure()
            }
        }

        player.isMuted = playbackState.isMuted
        player.replaceCurrentItem(with: item)
        if isFeedVisible && isAppForeground && !userPaused {
            player.play()
        }
    }

    private func handleItemFailure() {
        guard let video = activeVideo else { return }
        if !triedSignedRefresh {
            triedSignedRefresh = true
            playbackState.loadingReason = .reconnecting
            Task { [weak self] in
                guard let self else { return }
                if let refreshed = await self.onRefreshSignedURL?(video.video_id) {
                    self.activeVideo = refreshed
                    self.loadVideoURL(for: refreshed, useFallbackMP4: self.triedMp4Fallback)
                } else if !self.triedMp4Fallback && !video.fallback_mp4_url.isEmpty {
                    self.triedMp4Fallback = true
                    self.loadVideoURL(for: video, useFallbackMP4: true)
                } else {
                    self.playbackState.status = .error("Error has occurred, try again later.")
                    self.playbackState.loadingReason = .none
                }
            }
            return
        }
        if !triedMp4Fallback && !video.fallback_mp4_url.isEmpty {
            triedMp4Fallback = true
            playbackState.loadingReason = .qualitySwitch
            loadVideoURL(for: video, useFallbackMP4: true)
            return
        }
        playbackState.status = .error("Error has occurred, try again later.")
        playbackState.loadingReason = .none
    }

    private func clearItemObservers() {
        statusObservation?.invalidate()
        statusObservation = nil
        bufferObservation?.invalidate()
        bufferObservation = nil
        keepUpObservation?.invalidate()
        keepUpObservation = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        if let failObserver {
            NotificationCenter.default.removeObserver(failObserver)
            self.failObserver = nil
        }
    }

    private func onTimeTick(_ cmTime: CMTime) {
        guard let item = player.currentItem else { return }
        let posMs = max(0, Int64(CMTimeGetSeconds(cmTime) * 1000.0))
        let durSec = CMTimeGetSeconds(item.duration)
        let durMs = durSec.isFinite && durSec > 0 ? Int64(durSec * 1000.0) : playbackState.durationMs

        var bufferedPct = 0.0
        if durMs > 0, let range = item.loadedTimeRanges.first?.timeRangeValue {
            let loadedMs = CMTimeGetSeconds(CMTimeAdd(range.start, range.duration)) * 1000.0
            bufferedPct = min(1.0, max(0.0, loadedMs / Double(durMs)))
        }

        let nowWall = Int64(Date().timeIntervalSince1970 * 1000)
        if player.rate > 0 && lastTickWallMs > 0 {
            let delta = max(0, min(1500, nowWall - lastTickWallMs))
            watchAccumulatedMs += delta
        }
        lastTickWallMs = nowWall

        playbackState.positionMs = posMs
        playbackState.durationMs = durMs
        playbackState.bufferedPct = bufferedPct
        if player.rate > 0 {
            playbackState.status = .playing
            playbackState.loadingReason = .none
        }

        if watchAccumulatedMs - lastReportedMs >= 3000 {
            flushProgress(force: false)
        }
    }

    private func flushProgress(force: Bool) {
        guard let vid = activeVideo?.video_id else { return }
        if !force && watchAccumulatedMs == lastReportedMs && rewatchDelta == 0 { return }
        guard watchAccumulatedMs > 400 || rewatchDelta > 0 else { return }

        let dur = max(1, playbackState.durationMs)
        let pct = min(100.0, max(0.0, (Double(playbackState.positionMs) / Double(dur)) * 100.0))
        let delta = rewatchDelta
        rewatchDelta = 0
        lastReportedMs = watchAccumulatedMs
        onReportWatchProgress?(vid, watchAccumulatedMs, playbackState.positionMs, pct, delta, false)
    }

    private func scheduleAheadPrefetch(upcoming: [FeedVideoItem], networkQuality: TelefamNetworkQuality) {
        prefetchTask?.cancel()
        guard networkQuality != .offline, !upcoming.isEmpty else { return }
        let targets = Array(upcoming.prefix(5))
        let session = mediaCacheURLSession
        let resolve = resolveURL

        prefetchTask = Task.detached(priority: .utility) {
            for item in targets {
                if Task.isCancelled { break }
                let raw = item.stream_url.isEmpty ? item.fallback_mp4_url : item.stream_url
                guard let url = resolve(raw) else { continue }
                // Warm AVURLAsset keys + cache initial 512 KB / manifest in shared URLCache
                let asset = AVURLAsset(url: url)
                _ = try? await asset.load(.isPlayable)
                var req = URLRequest(url: url)
                req.setValue("bytes=0-524287", forHTTPHeaderField: "Range")
                _ = try? await session.data(for: req)
            }
        }
    }

    // MARK: - Discovery / Search Preview Pool (Max 2 Muted Players)

    func previewPlayer(for key: String, urlString: String) -> AVPlayer? {
        if let existing = previewPlayers[key] {
            return existing
        }
        guard let url = resolveURL(urlString) else { return nil }
        while previewOrder.count >= 2 {
            let oldest = previewOrder.removeFirst()
            previewPlayers[oldest]?.pause()
            previewPlayers[oldest]?.replaceCurrentItem(with: nil)
            previewPlayers.removeValue(forKey: oldest)
        }
        let p = AVPlayer(url: url)
        p.isMuted = true
        p.actionAtItemEnd = .none
        p.play()
        previewPlayers[key] = p
        previewOrder.append(key)
        return p
    }

    func releasePreview(key: String) {
        previewOrder.removeAll { $0 == key }
        previewPlayers[key]?.pause()
        previewPlayers[key]?.replaceCurrentItem(with: nil)
        previewPlayers.removeValue(forKey: key)
    }

    func releaseAllPreviews() {
        for p in previewPlayers.values {
            p.pause()
            p.replaceCurrentItem(with: nil)
        }
        previewPlayers.removeAll()
        previewOrder.removeAll()
    }
}
