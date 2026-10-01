import XCTest
import AVFoundation
import LumaStreams
import Combine
@testable import Luma

final class LumaTests: XCTestCase {
    func testStartupChoosesAdaptiveOr720pInsteadOfLargestFile() {
        let url = URL(string: "https://example.com/video")!
        let choices = [2160, 1080, 720, 360].map { PlaybackChoice(url: url.appendingPathComponent(String($0)), label: "Test", height: $0) }
        XCTAssertEqual(PlaybackChoice.initial(in: choices)?.height, 720)
        XCTAssertEqual(PlaybackChoice.initial(in: choices, cap: 480)?.height, 360)
        XCTAssertEqual(PlaybackChoice.initial(in: choices, cap: 2160)?.height, 2160)
        let hls = PlaybackChoice(url: url.appendingPathComponent("hls"), label: "HLS")
        XCTAssertEqual(PlaybackChoice.initial(in: choices + [hls])?.id, hls.id)
    }

    func testFastPlayerResponseCanStartWithoutSignatureJavaScript() throws {
        let hls = Data(#"{"streamingData":{"hlsManifestUrl":"https://example.com/master.m3u8"}}"#.utf8)
        XCTAssertEqual(try FastStreamResolver.decode(hls).first?.url.path, "/master.m3u8")
        let adaptive = Data(#"{"streamingData":{"adaptiveFormats":[{"url":"https://example.com/video","mimeType":"video/mp4; codecs=\"avc1.4d401f\"","height":720},{"url":"https://example.com/audio","mimeType":"audio/mp4; codecs=\"mp4a.40.2\""},{"mimeType":"video/mp4; codecs=\"avc1.4d401f\"","height":1080,"signatureCipher":"unresolved"}]}}"#.utf8)
        let choices = try FastStreamResolver.decode(adaptive)
        XCTAssertEqual(choices.count, 1)
        XCTAssertEqual(choices.first?.audioURL?.path, "/audio")
        XCTAssertEqual(choices.first?.height, 720)
        XCTAssertTrue(try FastStreamResolver.decode(Data(#"{"playabilityStatus":{"status":"LOGIN_REQUIRED"}}"#.utf8)).isEmpty)
    }

    func testStreamCacheRejectsExpiringSignedURLsAndHonorsTTL() {
        var cache = StreamCache()
        let now = Date(timeIntervalSince1970: 1000)
        let choice = PlaybackChoice(url: URL(string: "https://example.com/video?expire=1200")!, label: "Video", audioURL: URL(string: "https://example.com/audio?expire=1100")!)
        cache.insert([choice], for: "one", now: now)
        XCTAssertNotNil(cache.get("one", now: now.addingTimeInterval(39)))
        XCTAssertNil(cache.get("one", now: now.addingTimeInterval(41)))
        cache.insert([PlaybackChoice(url: URL(string: "https://example.com/video")!, label: "Video")], for: "two", now: now)
        XCTAssertNil(cache.get("two", now: now.addingTimeInterval(601)))
        cache.insert([choice], for: "three", now: now); cache.clear()
        XCTAssertNil(cache.get("three", now: now))
    }

    @MainActor
    func testPlaybackClockDoesNotInvalidateTheWholePlayerStore() {
        let playback = PlaybackStore()
        var broadcasts = 0
        let subscription = playback.objectWillChange.sink { broadcasts += 1 }
        playback.clock.seconds = 30
        playback.clock.duration = 3600
        XCTAssertEqual(playback.seconds, 30)
        XCTAssertEqual(playback.duration, 3600)
        XCTAssertEqual(broadcasts, 0)
        playback.seek(to: 420)
        XCTAssertEqual(playback.seconds, 420, "The slider must not jump back while the asynchronous seek is pending")
        playback.seek(to: 9000)
        XCTAssertEqual(playback.seconds, 3600)
        playback.seek(to: .nan)
        XCTAssertEqual(playback.seconds, 3600)
        withExtendedLifetime(subscription) { }
    }

    @MainActor
    func testAdaptivePlayerDecodesPictureAndAdvancesSound() async throws {
        let bundle = Bundle(for: LumaTests.self)
        let picture = try XCTUnwrap(bundle.url(forResource: "Picture", withExtension: "mp4"))
        let sound = try XCTUnwrap(bundle.url(forResource: "Sound", withExtension: "m4a"))
        try await assertPlayback(PlaybackChoice(url: picture, label: "Generated integration fixture", audioURL: sound))
    }

    @MainActor
    func testAdaptivePublicVideoPlaysWithPictureAndSound() async throws {
        executionTimeAllowance = 240
        let playback = PlaybackStore()
        playback.connect(service: YouTubeService(), library: LocalLibrary(inMemory: true))
        playback.open(Video(id: "aqz-KE-bpKQ", title: "Big Buck Bunny"))
        defer { playback.stop() }
        let started = Date()
        var output: AVPlayerItemVideoOutput?
        for _ in 0..<180 {
            if let error = playback.error { XCTFail(error); return }
            if let item = playback.player.currentItem, output == nil {
                let videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
                item.add(videoOutput); output = videoOutput
            }
            if playback.seconds >= 2 { break }
            try await Task.sleep(for: .seconds(1))
        }
        print("Public video time to two seconds of playback:", Date().timeIntervalSince(started), "source:", playback.sourceLabel)
        XCTAssertGreaterThanOrEqual(playback.seconds, 2)
        XCTAssertNotNil(output?.copyPixelBuffer(forItemTime: playback.player.currentTime(), itemTimeForDisplay: nil))
    }

    @MainActor
    private func assertPlayback(_ choice: PlaybackChoice) async throws {
        let item = try await NativeStreamPlayer.item(for: choice)
        let videoTracks = try await item.asset.loadTracks(withMediaType: .video)
        let audioTracks = try await item.asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(videoTracks.count, 1)
        XCTAssertEqual(audioTracks.count, 1)
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        item.add(output)
        let player = AVPlayer(playerItem: item)
        defer { player.pause(); player.replaceCurrentItem(with: nil) }
        for _ in 0..<60 {
            if item.status != .unknown { break }
            try await Task.sleep(for: .seconds(1))
        }
        XCTAssertEqual(item.status, .readyToPlay, item.error?.localizedDescription ?? "Player did not become ready")
        guard item.status == .readyToPlay else { return }
        player.play()
        for _ in 0..<30 {
            if player.currentTime().seconds >= 2 { break }
            try await Task.sleep(for: .seconds(1))
        }
        XCTAssertGreaterThanOrEqual(player.currentTime().seconds, 2, "Both tracks must actually advance on AVPlayer's playback clock")
        XCTAssertNotNil(output.copyPixelBuffer(forItemTime: player.currentTime(), itemTimeForDisplay: nil), "The player must decode an actual picture frame")
    }

    @MainActor
    func testAnonymousSearchDecodesLiveYouTube() async throws {
        let service = YouTubeService()
        let page = try await service.feed(.search("Big Buck Bunny"))
        XCTAssertFalse(page.videos.isEmpty, "The current YouTube response must decode into real videos")
        XCTAssertTrue(page.videos.allSatisfy { VideoLink.validID($0.id) })
    }

    func testVideoLinksAcceptRealHostsAndRejectLookalikes() {
        let id = "dQw4w9WgXcQ"
        for link in [id, "https://youtu.be/\(id)?t=30", "https://www.youtube.com/watch?v=\(id)&list=PLabc", "https://m.youtube.com/shorts/\(id)", "https://www.youtube.com/live/\(id)", "luma://watch/\(id)"] {
            XCTAssertEqual(VideoLink.id(from: link), id, link)
        }
        for link in ["https://evil-youtube.com/watch?v=\(id)", "https://youtube.com.evil.com/watch?v=\(id)", "https://youtube.com/watch?v=short", "file://youtube.com/watch?v=\(id)", "https://example.com/\(id)"] {
            XCTAssertNil(VideoLink.id(from: link), link)
        }
    }

    func testCookieImportFiltersForeignDomainsAndExpiredTokens() throws {
        let text = """
        # Netscape HTTP Cookie File
        .youtube.com\tTRUE\t/\tTRUE\t0\tSAPISID\tvalid-session
        #HttpOnly_.youtube.com\tTRUE\t/\tTRUE\t0\tSID\tvalid-sid
        .google.com\tTRUE\t/\tTRUE\t0\tFOREIGN\tnot-imported
        evil-youtube.com\tTRUE\t/\tTRUE\t0\tEVIL\tnot-imported
        .youtube.com\tTRUE\t/\tTRUE\t10\tOLD\texpired
        """
        let header = try CookieParser.header(from: text, now: 100)
        XCTAssertEqual(header, "SAPISID=valid-session; SID=valid-sid")
    }

    func testCookieHeaderCannotInjectAnotherHeader() throws {
        XCTAssertThrowsError(try CookieParser.header(from: "SAPISID=valid\r\nAuthorization: evil"))
        XCTAssertThrowsError(try CookieParser.header(from: "SID=alone"))
        XCTAssertEqual(try CookieParser.header(from: "Cookie: SAPISID=one=two; SID=three"), "SAPISID=one=two; SID=three")
        XCTAssertTrue(try CookieParser.header(from: "__Secure-3PAPISID=secure").contains("SAPISID=secure"))
    }

    @MainActor
    func testLocalLibraryKeepsLatestProgressAndTogglesBookmarks() {
        let library = LocalLibrary(inMemory: true)
        let video = Video(id: "dQw4w9WgXcQ", title: "Example")
        library.toggle(video); XCTAssertTrue(library.contains(video))
        library.toggle(video); XCTAssertFalse(library.contains(video))
        library.record(video, seconds: 30, duration: 90)
        library.record(video, seconds: 45, duration: 90)
        XCTAssertEqual(library.history.count, 1)
        XCTAssertEqual(library.progress(for: video), 45)
        library.record(video, seconds: .nan, duration: 90)
        XCTAssertEqual(library.progress(for: video), 45)
        library.clearHistory(); XCTAssertTrue(library.history.isEmpty)
    }

    func testPaginationDeduplicatesByVideoID() {
        let video = Video(id: "dQw4w9WgXcQ")
        XCTAssertEqual([video, video, Video(id: "jNQXAC9IVRw")].unique().count, 2)
    }
}
