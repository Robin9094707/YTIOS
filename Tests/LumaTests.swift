import XCTest
import AVFoundation
import LumaStreams
@testable import Luma

final class LumaTests: XCTestCase {
    @MainActor
    func testAdaptivePublicVideoPlaysWithPictureAndSound() async throws {
        executionTimeAllowance = 240
        // Blender's public Big Buck Bunny video exercises YouTube's real adaptive streams.
        let streams = try await LumaStreams.YouTube(videoID: "aqz-KE-bpKQ", methods: [.local, .remote]).streams
        print("Decoded streams:", streams.map { "\($0.videoResolution ?? 0)p, video=\(String(describing: $0.videoCodec)), audio=\(String(describing: $0.audioCodec))" })
        let picture = try XCTUnwrap(streams.filter {
            $0.includesVideoTrack && !$0.includesAudioTrack && $0.videoCodec == .avc1
        }.min { ($0.videoResolution ?? 0) < ($1.videoResolution ?? 0) })
        let sound = try XCTUnwrap(streams.first { $0.includesAudioTrack && !$0.includesVideoTrack && $0.audioCodec == .mp4a })
        let item = try await NativeStreamPlayer.item(for: PlaybackChoice(url: picture.url, label: "Integration test", audioURL: sound.url))
        let videoTracks = try await item.asset.loadTracks(withMediaType: .video)
        let audioTracks = try await item.asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(videoTracks.count, 1)
        XCTAssertEqual(audioTracks.count, 1)
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
