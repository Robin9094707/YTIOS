import XCTest
@testable import Luma

final class LumaTests: XCTestCase {
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
