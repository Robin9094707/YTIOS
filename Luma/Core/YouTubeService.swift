import Foundation
import Combine
import YouTubeKit

@MainActor
final class YouTubeService: ObservableObject {
    let model = YouTubeModel()
    @Published private(set) var accountName: String?
    @Published private(set) var avatar: URL?
    @Published private(set) var sessionNeedsRenewal = false
    @Published private(set) var accountRevision = 0
    private var homeUsesSearch = false
    private let discoveryQuery = "Technik Musik Gaming"
    var signedIn: Bool { accountName != nil && !sessionNeedsRenewal }

    func bootstrap() async {
        guard let header = SecureSession.read() else { return }
        model.cookies = header; model.alwaysUseCookies = true
        do { try await verify() }
        catch { sessionNeedsRenewal = true }
    }
    func signIn(header: String) async throws {
        let previous = model.cookies
        model.cookies = header; model.alwaysUseCookies = true
        do {
            let response = try await AccountInfosResponse.sendThrowingRequest(youtubeModel: model, data: [:], useCookies: true)
            guard !response.isDisconnected else { throw AppFailure.signedOut }
            try SecureSession.write(header)
            accountName = response.name ?? "YouTube-Konto"; avatar = response.avatar.last?.url
            sessionNeedsRenewal = false; model.visitorData = ""; accountRevision += 1
        } catch {
            model.cookies = previous; model.alwaysUseCookies = !previous.isEmpty
            throw error
        }
    }
    private func verify() async throws {
        let response = try await AccountInfosResponse.sendThrowingRequest(youtubeModel: model, data: [:], useCookies: true)
        guard !response.isDisconnected else { throw AppFailure.signedOut }
        accountName = response.name ?? "YouTube-Konto"; avatar = response.avatar.last?.url
        sessionNeedsRenewal = false; accountRevision += 1
    }
    func signOut() {
        SecureSession.delete(); model.cookies = ""; model.alwaysUseCookies = false; model.visitorData = ""
        accountName = nil; avatar = nil; sessionNeedsRenewal = false; accountRevision += 1
    }
    func requireAccount() throws { guard signedIn else { throw AppFailure.signedOut } }
    private func check(_ disconnected: Bool) throws {
        if disconnected { sessionNeedsRenewal = true; throw AppFailure.signedOut }
    }
    func ensureVisitor() async throws {
        guard model.visitorData.isEmpty else { return }
        let response = try await SearchResponse.sendThrowingRequest(youtubeModel: model, data: [.query: "music"])
        model.visitorData = response.visitorData ?? ""
    }
    func feed(_ source: FeedSource, continuation: String? = nil) async throws -> VideoPage {
        switch source {
        case .home:
            if continuation != nil && homeUsesSearch { return try await feed(.search(discoveryQuery), continuation: continuation) }
            if continuation == nil && !signedIn {
                homeUsesSearch = true
                var page = try await feed(.search(discoveryQuery))
                page.notice = "Öffentliche Entdeckungen · Verbinde dein Konto für deinen persönlichen Feed."
                return page
            }
            if let continuation {
                let r = try await HomeScreenResponse.Continuation.sendThrowingRequest(youtubeModel: model, data: [.continuation: continuation])
                return VideoPage(videos: r.results.map(Video.init).unique(), continuation: r.continuationToken)
            }
            let r = try await HomeScreenResponse.sendThrowingRequest(youtubeModel: model, data: [:])
            model.visitorData = r.visitorData ?? model.visitorData
            if r.results.isEmpty {
                homeUsesSearch = true
                var page = try await feed(.search(discoveryQuery))
                page.notice = "Dein Home-Feed ist gerade leer. Entdecke hier öffentliche Videos."
                return page
            }
            homeUsesSearch = false
            return VideoPage(videos: r.results.map(Video.init).unique(), continuation: r.continuationToken)
        case .search(let query):
            if let continuation {
                let r = try await SearchResponse.Continuation.sendThrowingRequest(youtubeModel: model, data: [.continuation: continuation])
                return mapSearch(r.results, token: r.continuationToken)
            }
            let r = try await SearchResponse.sendThrowingRequest(youtubeModel: model, data: [.query: query])
            model.visitorData = r.visitorData ?? model.visitorData
            return mapSearch(r.results, token: r.continuationToken)
        case .subscriptions:
            try requireAccount()
            if let continuation {
                let r = try await AccountSubscriptionsFeedResponse.Continuation.sendThrowingRequest(youtubeModel: model, data: [.continuation: continuation], useCookies: true)
                try check(r.isDisconnected)
                return VideoPage(videos: r.results.map(Video.init).unique(), continuation: r.continuationToken)
            }
            let r = try await AccountSubscriptionsFeedResponse.sendThrowingRequest(youtubeModel: model, data: [:], useCookies: true)
            try check(r.isDisconnected)
            return VideoPage(videos: r.results.map(Video.init).unique(), continuation: r.continuationToken)
        case .playlist(let id):
            if let continuation {
                let r = try await PlaylistInfosResponse.Continuation.sendThrowingRequest(youtubeModel: model, data: [.continuation: continuation])
                return VideoPage(videos: r.results.map(Video.init).unique(), continuation: r.continuationToken)
            }
            let r = try await PlaylistInfosResponse.sendThrowingRequest(youtubeModel: model, data: [.browseId: id])
            return VideoPage(videos: r.results.map(Video.init).unique(), continuation: r.continuationToken)
        }
    }
    private func mapSearch(_ values: [any YTSearchResult], token: String?) -> VideoPage {
        VideoPage(videos: values.compactMap { $0 as? YTVideo }.map(Video.init).unique(), continuation: token,
                  channels: values.compactMap { $0 as? YTChannel }, playlists: values.compactMap { $0 as? YTPlaylist })
    }
    func playlists() async throws -> [YTPlaylist] {
        try requireAccount()
        let r = try await AccountPlaylistsResponse.sendThrowingRequest(youtubeModel: model, data: [:], useCookies: true)
        try check(r.isDisconnected)
        var seen = Set<String>()
        return r.results.filter { seen.insert($0.playlistId).inserted }
    }
    func setLike(videoID: String, liked: Bool) async throws {
        try requireAccount()
        if liked {
            let r = try await LikeVideoResponse.sendThrowingRequest(youtubeModel: model, data: [.query: videoID], useCookies: true)
            try check(r.isDisconnected)
        } else {
            let r = try await RemoveLikeFromVideoResponse.sendThrowingRequest(youtubeModel: model, data: [.query: videoID], useCookies: true)
            try check(r.isDisconnected)
        }
    }
    func setSubscription(channelID: String, subscribed: Bool) async throws {
        try requireAccount()
        if subscribed {
            let r = try await SubscribeChannelResponse.sendThrowingRequest(youtubeModel: model, data: [.browseId: channelID], useCookies: true)
            try check(r.isDisconnected)
            guard r.success else { throw AppFailure.rejected }
        } else {
            let r = try await UnsubscribeChannelResponse.sendThrowingRequest(youtubeModel: model, data: [.browseId: channelID], useCookies: true)
            try check(r.isDisconnected)
            guard r.success else { throw AppFailure.rejected }
        }
    }
    func add(videoID: String, to playlistID: String) async throws {
        try requireAccount()
        let r = try await AddVideoToPlaylistResponse.sendThrowingRequest(youtubeModel: model, data: [.browseId: playlistID, .movingVideoId: videoID], useCookies: true)
        try check(r.isDisconnected)
        guard r.success else { throw AppFailure.rejected }
    }
    func createPlaylist(title: String, videoID: String? = nil) async throws {
        try requireAccount()
        var data: [HeadersList.AddQueryInfo.ContentTypes: String] = [.query: title, .params: "PRIVATE"]
        if let videoID { data[.movingVideoId] = videoID }
        let r = try await CreatePlaylistResponse.sendThrowingRequest(youtubeModel: model, data: data, useCookies: true)
        try check(r.isDisconnected)
        guard r.createdPlaylistId != nil else { throw AppFailure.rejected }
    }
    func postComment(text: String, token: String) async throws -> YTComment? {
        try requireAccount()
        let r = try await CreateCommentResponse.sendThrowingRequest(youtubeModel: model, data: [.params: token, .text: text], useCookies: true)
        try check(r.isDisconnected)
        guard r.success else { throw AppFailure.rejected }
        return r.newComment
    }
    func history() async throws -> [Video] {
        try requireAccount()
        let r = try await HistoryResponse.sendThrowingRequest(youtubeModel: model, data: [:], useCookies: true)
        try check(r.isDisconnected)
        return r.results.flatMap { $0.videosArray.map { Video($0.video) } }.unique()
    }
}
