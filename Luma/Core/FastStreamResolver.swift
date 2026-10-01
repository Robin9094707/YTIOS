import Foundation

/// A small player response often contains an HLS URL or direct MP4 URLs already.
/// This path never downloads the watch page or YouTube's multi-megabyte JS player.
enum FastStreamResolver {
    private struct Response: Decodable {
        var streamingData: StreamingData?
        struct StreamingData: Decodable {
            var hlsManifestUrl: URL?
            var formats: [Format]?
            var adaptiveFormats: [Format]?
        }
        struct Format: Decodable {
            var url: URL?
            var mimeType: String
            var height: Int?
            var bitrate: Int?
        }
    }

    static func decode(_ data: Data) throws -> [PlaybackChoice] {
        guard let payload = try JSONDecoder().decode(Response.self, from: data).streamingData else { return [] }
        if let url = payload.hlsManifestUrl, url.scheme == "https" {
            return [PlaybackChoice(url: url, label: "HLS · adaptiv")]
        }
        let formats = (payload.formats ?? []) + (payload.adaptiveFormats ?? [])
        let direct = formats.filter { $0.url?.scheme == "https" && $0.mimeType.contains("video/mp4") && $0.mimeType.contains("avc1") }
        let audio = formats.filter { $0.url?.scheme == "https" && $0.mimeType.contains("audio/mp4") && $0.mimeType.contains("mp4a") }
            .max { ($0.bitrate ?? 0) < ($1.bitrate ?? 0) }
        return direct.compactMap { format in
            guard let url = format.url else { return nil }
            if format.mimeType.contains("mp4a") {
                return PlaybackChoice(url: url, label: "\(format.height ?? 0)p · MP4", height: format.height)
            }
            guard let audioURL = audio?.url else { return nil }
            return PlaybackChoice(url: url, label: "\(format.height ?? 0)p · Bild + Ton", audioURL: audioURL, height: format.height)
        }
    }

    static func resolve(videoID: String, visitor: String) async throws -> [PlaybackChoice] {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 6
        configuration.timeoutIntervalForResource = 8
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        return await withTaskGroup(of: [PlaybackChoice].self) { group in
            for client in ["VISIONOS", "ANDROID_VR"] {
                group.addTask {
                    do {
                        var context: [String: Any] = ["clientName": client, "clientVersion": client == "VISIONOS" ? "1.02" : "1.65.10", "hl": "de", "gl": "DE"]
                        if !visitor.isEmpty { context["visitorData"] = visitor }
                        if client == "ANDROID_VR" { context["androidSdkVersion"] = 32; context["deviceModel"] = "Quest 3" }
                        else { context["deviceMake"] = "Apple"; context["deviceModel"] = "RealityDevice17,1"; context["osName"] = "visionOS"; context["osVersion"] = "26.5.23O471" }
                        var request = URLRequest(url: URL(string: "https://www.youtube.com/youtubei/v1/player?prettyPrint=false")!)
                        request.httpMethod = "POST"
                        request.httpShouldHandleCookies = false
                        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
                        request.setValue(client == "VISIONOS" ? "101" : "28", forHTTPHeaderField: "X-YouTube-Client-Name")
                        request.setValue(client == "VISIONOS" ? "1.02" : "1.65.10", forHTTPHeaderField: "X-YouTube-Client-Version")
                        request.setValue(client == "VISIONOS" ? "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15" : "com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip", forHTTPHeaderField: "User-Agent")
                        if !visitor.isEmpty { request.setValue(visitor, forHTTPHeaderField: "X-Goog-Visitor-Id") }
                        request.httpBody = try JSONSerialization.data(withJSONObject: ["context": ["client": context], "videoId": videoID, "contentCheckOk": true, "racyCheckOk": true])
                        let (data, response) = try await session.data(for: request)
                        guard (response as? HTTPURLResponse)?.statusCode == 200, !Task.isCancelled else { return [] }
                        return try decode(data)
                    } catch { return [] }
                }
            }
            for await result in group where !result.isEmpty {
                group.cancelAll()
                return result
            }
            return []
        }
    }
}

struct StreamCache {
    private struct Entry { var choices: [PlaybackChoice]; var expires: Date }
    private var entries: [String: Entry] = [:]
    mutating func get(_ id: String, now: Date = Date()) -> [PlaybackChoice]? {
        guard let entry = entries[id] else { return nil }
        guard entry.expires > now else { entries[id] = nil; return nil }
        return entry.choices
    }
    mutating func insert(_ choices: [PlaybackChoice], for id: String, now: Date = Date()) {
        guard !choices.isEmpty else { return }
        let urls = choices.flatMap { [$0.url] + ($0.audioURL.map { [$0] } ?? []) }
        let signedExpiry = urls.compactMap { url -> Date? in
            guard let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "expire" })?.value,
                  let seconds = Double(value) else { return nil }
            return Date(timeIntervalSince1970: seconds).addingTimeInterval(-60)
        }.min()
        let expires = min(signedExpiry ?? now.addingTimeInterval(600), now.addingTimeInterval(600))
        guard expires > now else { return }
        entries[id] = Entry(choices: choices, expires: expires)
        if entries.count > 16, let oldest = entries.min(by: { $0.value.expires < $1.value.expires })?.key { entries[oldest] = nil }
    }
    mutating func remove(_ id: String) { entries[id] = nil }
    mutating func clear() { entries.removeAll() }
}
