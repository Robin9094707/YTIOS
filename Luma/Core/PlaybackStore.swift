import Foundation
import AVFoundation
import MediaPlayer
import Combine
import YouTubeKit
import LumaStreams

struct PlaybackChoice: Identifiable {
    var id: String { url.absoluteString }
    let url: URL
    let label: String
    var audioURL: URL? = nil
    var height: Int? = nil
}

/// AVFoundation keeps separate adaptive video and audio tracks on one playback clock.
enum NativeStreamPlayer {
    static func item(for choice: PlaybackChoice) async throws -> AVPlayerItem {
        guard let audioURL = choice.audioURL else { return AVPlayerItem(url: choice.url) }
        let video = AVURLAsset(url: choice.url)
        let audio = AVURLAsset(url: audioURL)
        async let videoTracks = video.loadTracks(withMediaType: .video)
        async let audioTracks = audio.loadTracks(withMediaType: .audio)
        async let videoDuration = video.load(.duration)
        async let audioDuration = audio.load(.duration)
        guard let sourceVideo = try await videoTracks.first,
              let sourceAudio = try await audioTracks.first else { throw AppFailure.noStream }
        let length = try await CMTimeMinimum(videoDuration, audioDuration)
        guard length.seconds.isFinite, length.seconds > 0 else { throw AppFailure.noStream }
        try Task.checkCancellation()
        let composition = AVMutableComposition()
        guard let picture = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let sound = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw AppFailure.noStream
        }
        let range = CMTimeRange(start: .zero, duration: length)
        try picture.insertTimeRange(range, of: sourceVideo, at: .zero)
        try sound.insertTimeRange(range, of: sourceAudio, at: .zero)
        picture.preferredTransform = try await sourceVideo.load(.preferredTransform)
        try Task.checkCancellation()
        return AVPlayerItem(asset: composition)
    }
}

struct CaptionCue: Identifiable {
    var id: Double { start }
    var start: Double
    var end: Double
    var text: String
}

@MainActor
final class PlaybackStore: ObservableObject {
    let player = AVPlayer()
    @Published private(set) var video: Video?
    @Published private(set) var loading = false
    @Published private(set) var playing = false
    @Published private(set) var error: String?
    @Published private(set) var seconds = 0.0
    @Published private(set) var duration = 0.0
    @Published private(set) var choices: [PlaybackChoice] = []
    @Published private(set) var sourceLabel = ""
    @Published var queue: [Video] = []
    @Published var speed: Float = 1
    @Published var quality = 0
    @Published var captions: [CaptionCue] = []
    @Published var captionsEnabled = false
    private var loadTask: Task<Void, Never>?
    private var itemTask: Task<Void, Never>?
    private var itemToken = UUID()
    private var timeoutTask: Task<Void, Never>?
    private var sleepTask: Task<Void, Never>?
    private var itemObservation: NSKeyValueObservation?
    private var controlObservation: NSKeyValueObservation?
    private var periodicObserver: Any?
    private var endedObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var library: LocalLibrary?
    private var service: YouTubeService?
    private var token = UUID()
    private var fallbackTried = false
    private var attemptedURLs = Set<URL>()
    private var resumeAt = 0.0
    private var lastSaved = 0.0
    private var remoteTargets: [(MPRemoteCommand, Any)] = []
    private var resumeAfterInterruption = false
    @Published private(set) var sleepMinutes: Int?

    init() {
        player.allowsExternalPlayback = true
        controlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor in self?.playing = player.timeControlStatus == .playing }
        }
        periodicObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                self.seconds = max(0, time.seconds.isFinite ? time.seconds : 0)
                let total = self.player.currentItem?.duration.seconds ?? 0
                self.duration = total.isFinite ? max(0,total) : 0
                if abs(self.seconds - self.lastSaved) >= 10 { self.saveProgress(); self.lastSaved = self.seconds }
                self.updateNowPlaying()
            }
        }
        endedObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor in
                guard let self, let item = note.object as? AVPlayerItem, item === self.player.currentItem else { return }
                self.saveProgress()
                if UserDefaults.standard.bool(forKey: "autoplay"), !self.queue.isEmpty { self.next() }
            }
        }
        interruptionObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor in
                guard let self, let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
                if type == .began { self.resumeAfterInterruption = self.playing; self.player.pause() }
                else if self.resumeAfterInterruption,
                        let options = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt,
                        AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) {
                    self.player.playImmediately(atRate: self.speed)
                }
            }
        }
        configureRemoteCommands()
    }

    func connect(service: YouTubeService, library: LocalLibrary) { self.service = service; self.library = library }
    func open(_ video: Video) {
        saveProgress(); loadTask?.cancel(); itemTask?.cancel(); timeoutTask?.cancel()
        player.pause(); player.replaceCurrentItem(with: nil)
        token = UUID(); self.video = video; loading = true; error = nil
        choices = []; attemptedURLs = []; fallbackTried = false
        captions = []; captionsEnabled = false; seconds = 0; duration = 0; lastSaved = 0
        resumeAt = library?.progress(for: video) ?? 0
        sourceLabel = "Stream wird geladen"
        let currentToken = token
        loadTask = Task {
            do {
                let audio = AVAudioSession.sharedInstance()
                try audio.setCategory(.playback, mode: .moviePlayback)
                try audio.setActive(true)
                if let service {
                    try? await service.ensureVisitor()
                    if let info = try? await VideoInfosResponse.sendThrowingRequest(youtubeModel: service.model, data: [.query: video.id]) {
                        guard currentToken == token, !Task.isCancelled else { return }
                        if self.video?.title == "Video", let title = info.title { self.video?.title = title }
                        if let url = info.streamingURL {
                            choices = [PlaybackChoice(url: url, label: "HLS · adaptiv")]
                            install(choices[0], generation: currentToken)
                            return
                        }
                    }
                }
                try await extract(generation: currentToken)
            } catch {
                guard currentToken == token, !Task.isCancelled else { return }
                loading = false; self.error = AppFailure.noStream.localizedDescription
            }
        }
    }

    private func extract(generation: UUID) async throws {
        guard let video, generation == token else { return }
        fallbackTried = true
        let remote = UserDefaults.standard.bool(forKey: "remoteFallback")
        let streams = try await LumaStreams.YouTube(videoID: video.id, methods: remote ? [.local, .remote] : [.local]).streams
        try Task.checkCancellation()
        guard generation == token else { return }
        let supported = streams.filter { $0.includesVideoAndAudioTrack && $0.isNativelyPlayable }
            .sorted { ($0.videoResolution ?? 0) > ($1.videoResolution ?? 0) }
        choices = supported.map { PlaybackChoice(url: $0.url, label: "\($0.videoResolution ?? 0)p · MP4", height: $0.videoResolution) }
        let audio = streams.filter { $0.includesAudioTrack && !$0.includesVideoTrack && $0.audioCodec == .mp4a }
            .max { ($0.averageBitrate ?? $0.bitrate ?? 0) < ($1.averageBitrate ?? $1.bitrate ?? 0) }
        if let audio {
            let pictures = streams.filter { $0.includesVideoTrack && !$0.includesAudioTrack && $0.videoCodec == .avc1 }
                .sorted { ($0.videoResolution ?? 0) > ($1.videoResolution ?? 0) }
            choices += pictures.map {
                PlaybackChoice(url: $0.url, label: "\($0.videoResolution ?? 0)p · Bild + Ton", audioURL: audio.url, height: $0.videoResolution)
            }
        }
        guard let choice = choices.first else { throw AppFailure.noStream }
        let initial = choices.first(where: { ($0.height ?? 0) <= (quality > 0 ? quality : 1080) }) ?? choice
        install(initial, generation: generation)
    }

    private func install(_ choice: PlaybackChoice, generation: UUID) {
        guard generation == token else { return }
        attemptedURLs.insert(choice.url)
        timeoutTask?.cancel(); itemTask?.cancel(); itemObservation = nil
        itemToken = UUID()
        let request = itemToken
        player.pause()
        sourceLabel = choice.label; loading = true; error = nil
        timeoutTask = Task {
            try? await Task.sleep(for: .seconds(45))
            guard !Task.isCancelled, generation == token, request == itemToken, loading else { return }
            tryNextSource(generation: generation)
        }
        itemTask = Task {
            do {
                let item = try await NativeStreamPlayer.item(for: choice)
                guard generation == token, request == itemToken, !Task.isCancelled else { return }
                attach(item, generation: generation, request: request)
            } catch {
                guard generation == token, request == itemToken, !Task.isCancelled else { return }
                tryNextSource(generation: generation)
            }
        }
    }

    private func attach(_ item: AVPlayerItem, generation: UUID, request: UUID) {
        item.preferredForwardBufferDuration = 12
        if quality > 0 { item.preferredMaximumResolution = CGSize(width: CGFloat(quality) * 16 / 9, height: CGFloat(quality)) }
        itemObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self, generation == self.token, request == self.itemToken, item === self.player.currentItem else { return }
                switch item.status {
                case .readyToPlay:
                    self.timeoutTask?.cancel(); self.loading = false
                    let total = item.duration.seconds
                    if total.isFinite, self.resumeAt > 0, self.resumeAt < total - 10 {
                        self.player.seek(to: CMTime(seconds: self.resumeAt, preferredTimescale: 600))
                    }
                    self.resumeAt = 0; self.player.playImmediately(atRate: self.speed); self.updateNowPlaying()
                case .failed: self.tryNextSource(generation: generation)
                default: break
                }
            }
        }
        player.replaceCurrentItem(with: item)
    }

    private func tryNextSource(generation: UUID) {
        guard generation == token else { return }
        itemObservation = nil; timeoutTask?.cancel()
        if let next = choices.first(where: { !attemptedURLs.contains($0.url) }) { install(next, generation: generation) }
        else if !fallbackTried {
            loadTask?.cancel()
            loadTask = Task {
                do { try await extract(generation: generation) }
                catch {
                    guard generation == token, !Task.isCancelled else { return }
                    loading = false; self.error = AppFailure.noStream.localizedDescription
                }
            }
        } else { player.pause(); loading = false; error = AppFailure.noStream.localizedDescription }
    }

    func choose(_ choice: PlaybackChoice) { resumeAt = seconds; install(choice, generation: token) }
    func retry() { if let video { open(video) } }
    func toggle() { if playing { player.pause(); saveProgress() } else { player.playImmediately(atRate: speed) } }
    func seek(to time: Double) {
        guard time.isFinite else { return }
        player.seek(to: CMTime(seconds: max(0, duration > 0 ? min(time,duration) : time), preferredTimescale: 600))
    }
    func skip(_ amount: Double) { seek(to: seconds + amount) }
    func setSpeed(_ value: Float) { speed = value; if playing { player.rate = value }; updateNowPlaying() }
    func setQuality(_ height: Int) {
        quality = height
        player.currentItem?.preferredMaximumResolution = height > 0 ? CGSize(width: CGFloat(height)*16/9, height: CGFloat(height)) : .zero
        // A composed MP4 has a fixed resolution; selecting a cap must replace its video track.
        if player.currentItem?.asset is AVComposition,
           let choice = choices.filter({ $0.audioURL != nil && ($0.height ?? 0) <= (height > 0 ? height : 1080) })
            .max(by: { ($0.height ?? 0) < ($1.height ?? 0) }) {
            choose(choice)
        }
    }
    func enqueue(_ video: Video) { if !queue.contains(where: { $0.id == video.id }) { queue.append(video) } }
    func next() { guard !queue.isEmpty else { return }; open(queue.removeFirst()) }
    func stop() {
        saveProgress(); token = UUID(); loadTask?.cancel(); itemTask?.cancel(); timeoutTask?.cancel(); sleepTask?.cancel()
        itemObservation = nil; player.pause(); player.replaceCurrentItem(with: nil)
        video = nil; playing = false; loading = false; sleepMinutes = nil; captions = []
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
    func saveProgress() {
        if let video, seconds > 0 { library?.record(video, seconds: seconds, duration: duration) }
    }
    func sleep(after minutes: Int?) {
        sleepTask?.cancel(); sleepMinutes = minutes
        guard let minutes else { return }
        sleepTask = Task {
            try? await Task.sleep(for: .seconds(minutes*60))
            guard !Task.isCancelled else { return }
            player.pause(); saveProgress(); sleepMinutes = nil
        }
    }
    var activeCaption: String? { captions.first { seconds >= $0.start && seconds < $0.end }?.text }
    func loadCaptions(_ caption: YTCaption) async throws {
        let generation = token
        var url = URLComponents(url: caption.url, resolvingAgainstBaseURL: false)!
        var items = url.queryItems?.filter { $0.name != "fmt" } ?? []
        items.append(URLQueryItem(name: "fmt", value: "json3")); url.queryItems = items
        let (data, response) = try await URLSession.shared.data(from: url.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw AppFailure.unavailable }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let events = json?["events"] as? [[String: Any]] ?? []
        let cues = events.compactMap { event -> CaptionCue? in
            guard let start = event["tStartMs"] as? Double, let length = event["dDurationMs"] as? Double,
                  let segments = event["segs"] as? [[String: Any]] else { return nil }
            let text = segments.compactMap { $0["utf8"] as? String }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : CaptionCue(start: start/1000, end: (start+length)/1000, text: text)
        }
        guard generation == token else { return }
        guard !cues.isEmpty else { throw AppFailure.unavailable }
        captions = cues; captionsEnabled = true
    }
    private func updateNowPlaying() {
        guard let video else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: video.title, MPMediaItemPropertyArtist: video.channel,
            MPMediaItemPropertyPlaybackDuration: duration, MPNowPlayingInfoPropertyElapsedPlaybackTime: seconds,
            MPNowPlayingInfoPropertyPlaybackRate: playing ? speed : 0
        ]
    }
    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        func register(_ command: MPRemoteCommand, action: @escaping @MainActor (MPRemoteCommandEvent) -> Void) {
            let target = command.addTarget { event in Task { @MainActor in action(event) }; return .success }
            remoteTargets.append((command, target))
        }
        register(center.playCommand) { [weak self] _ in guard let self else { return }; self.player.playImmediately(atRate: self.speed) }
        register(center.pauseCommand) { [weak self] _ in self?.player.pause(); self?.saveProgress() }
        register(center.togglePlayPauseCommand) { [weak self] _ in self?.toggle() }
        center.skipForwardCommand.preferredIntervals = [15]; center.skipBackwardCommand.preferredIntervals = [15]
        register(center.skipForwardCommand) { [weak self] _ in self?.skip(15) }
        register(center.skipBackwardCommand) { [weak self] _ in self?.skip(-15) }
        register(center.nextTrackCommand) { [weak self] _ in self?.next() }
        register(center.changePlaybackPositionCommand) { [weak self] event in
            if let event = event as? MPChangePlaybackPositionCommandEvent { self?.seek(to: event.positionTime) }
        }
    }
}
