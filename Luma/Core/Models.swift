import Foundation
import YouTubeKit

struct Video: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var channel: String
    var channelID: String?
    var thumbnail: URL?
    var duration: String?
    var views: String?
    var published: String?

    init(id: String, title: String = "Video", channel: String = "YouTube", channelID: String? = nil,
         thumbnail: URL? = nil, duration: String? = nil, views: String? = nil, published: String? = nil) {
        self.id = id; self.title = title; self.channel = channel; self.channelID = channelID
        self.thumbnail = thumbnail ?? URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg")
        self.duration = duration; self.views = views; self.published = published
    }

    init(_ value: YTVideo) {
        self.init(id: value.videoId, title: value.title ?? "Video", channel: value.channel?.name ?? "YouTube",
                  channelID: value.channel?.channelId, thumbnail: value.thumbnails.last?.url,
                  duration: value.timeLength, views: value.viewCount, published: value.timePosted)
    }

    var shareURL: URL { URL(string: "https://www.youtube.com/watch?v=\(id)")! }
    var caption: String { [views, published].compactMap { $0 }.joined(separator: " · ") }
}

struct VideoPage {
    var videos: [Video] = []
    var continuation: String?
    var channels: [YTChannel] = []
    var playlists: [YTPlaylist] = []
}

enum FeedSource: Equatable {
    case home, search(String), subscriptions, playlist(String)
}

enum AppFailure: LocalizedError {
    case signedOut, unavailable, invalidCookies, noStream, rejected
    var errorDescription: String? {
        switch self {
        case .signedOut: return "Bitte verbinde dein YouTube-Konto. Deine Sitzung ist möglicherweise abgelaufen."
        case .unavailable: return "YouTube liefert gerade keine Inhalte. Versuche es erneut."
        case .invalidCookies: return "Keine gültige YouTube-Sitzung gefunden. Importiere YouTube-Cookies mit SAPISID."
        case .noStream: return "Kein abspielbarer Stream verfügbar. Das Video kann eingeschränkt sein oder YouTube hat den Zugriff geändert."
        case .rejected: return "YouTube hat die Änderung nicht bestätigt. Bitte erneut versuchen."
        }
    }
}

enum VideoLink {
    static func id(from input: String) -> String? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if validID(text) { return text }
        guard let url = URL(string: text.contains("://") ? text : "https://" + text),
              let host = url.host?.lowercased(), ["https", "http", "luma"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        let candidate: String?
        if host == "youtu.be" { candidate = parts.first }
        else if host == "youtube.com" || host.hasSuffix(".youtube.com") || host == "youtube-nocookie.com" || host.hasSuffix(".youtube-nocookie.com") {
            if ["shorts", "embed", "live", "v"].contains(parts.first ?? "") { candidate = parts.dropFirst().first }
            else { candidate = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "v" })?.value }
        } else if url.scheme == "luma", host == "watch" { candidate = parts.first }
        else { return nil }
        return candidate.flatMap { validID($0) ? $0 : nil }
    }
    static func validID(_ value: String) -> Bool {
        value.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil
    }
}

enum CookieParser {
    static func isYouTubeDomain(_ domain: String) -> Bool {
        let host = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return host == "youtube.com" || host.hasSuffix(".youtube.com")
    }

    static func header(from text: String, now: TimeInterval = Date().timeIntervalSince1970) throws -> String {
        guard text.utf8.count < 1_000_000 else { throw AppFailure.invalidCookies }
        var values: [String: String] = [:]
        if text.contains("\t") {
            for rawLine in text.components(separatedBy: .newlines) {
                var line = rawLine
                if line.hasPrefix("#HttpOnly_") { line.removeFirst(10) }
                else if line.hasPrefix("#") { continue }
                let fields = line.components(separatedBy: "\t")
                guard fields.count >= 7, isYouTubeDomain(fields[0]), let expiry = Double(fields[4]), expiry == 0 || expiry > now else { continue }
                values[fields[5]] = fields[6]
            }
        } else {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let raw = trimmed.lowercased().hasPrefix("cookie:") ? String(trimmed.dropFirst(7)) : trimmed
            guard !raw.contains("\r"), !raw.contains("\n") else { throw AppFailure.invalidCookies }
            for part in raw.split(separator: ";") {
                let pair = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if pair.count == 2 { values[pair[0]] = pair[1] }
            }
        }
        values = values.filter { name, value in
            !name.isEmpty && name.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil &&
            !value.isEmpty && !value.contains(";") && !value.contains("\r") && !value.contains("\n")
        }
        // YouTubeKit signs authenticated requests with SAPISID.
        if values["SAPISID"] == nil, let secure = values["__Secure-3PAPISID"] { values["SAPISID"] = secure }
        guard values["SAPISID"] != nil else { throw AppFailure.invalidCookies }
        return values.keys.sorted().map { "\($0)=\(values[$0]!)" }.joined(separator: "; ")
    }
}

extension Array where Element == Video {
    func unique() -> [Video] {
        var seen = Set<String>()
        return filter { seen.insert($0.id).inserted }
    }
}
