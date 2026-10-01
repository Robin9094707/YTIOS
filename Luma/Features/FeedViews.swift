import SwiftUI
import YouTubeKit

enum PreviewData {
    static let videos = [
        Video(id: "aqz-KE-bpKQ", title: "Ein neuer Blick auf die Welt", channel: "Open Cinema", duration: "10:34", views: "2,4 Mio. Aufrufe", published: "vor 2 Tagen"),
        Video(id: "dQw4w9WgXcQ", title: "Musik für deinen Feierabend", channel: "Soundscapes", duration: "3:32", views: "820.000 Aufrufe", published: "vor 1 Woche"),
        Video(id: "jNQXAC9IVRw", title: "Code, Ideen und kleine Wunder", channel: "Creative Lab", duration: "12:08", views: "41.000 Aufrufe", published: "gestern")
    ]
}

struct FeedView: View {
    @EnvironmentObject private var service: YouTubeService
    var source: FeedSource
    var title: String
    var play: (Video) -> Void
    @State private var page = VideoPage()
    @State private var loading = false
    @State private var moreLoading = false
    @State private var error: String?
    @State private var generation = UUID()
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                if source == .home { masthead }
                if loading && page.videos.isEmpty { skeleton }
                if let error { InlineError(message: error) { Task { await load() } } }
                if !loading, error == nil, page.videos.isEmpty, page.channels.isEmpty, page.playlists.isEmpty {
                    EmptyState(title: "Noch keine Videos", message: source == .subscriptions ? "Hier erscheinen die neuesten Videos deiner abonnierten Kanäle." : "Probiere einen anderen Suchbegriff oder lade die Seite neu.")
                }
                if !page.channels.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 14) {
                            ForEach(page.channels, id: \.channelId) { channel in
                                NavigationLink { ChannelView(channelID: channel.channelId, play: play) } label: {
                                    VStack(spacing: 10) {
                                        AsyncImage(url: channel.thumbnails.last?.url) { image in image.resizable().scaledToFill() } placeholder: {
                                            Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(Palette.violet)
                                        }.frame(width: 58, height: 58).clipShape(Circle())
                                        Text(channel.name ?? "Kanal").font(.caption.weight(.medium)).lineLimit(1)
                                    }.frame(width: 115).padding(12).lumaCard()
                                }.buttonStyle(.plain)
                            }
                        }
                    }.scrollIndicators(.hidden)
                }
                if source == .home, let featured = page.videos.first {
                    VideoCard(video: featured, featured: true) { play(featured) }
                    sectionTitle("Dein nächster guter Fund", subtitle: "Videos, die Raum bekommen.")
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 285), spacing: 18)], spacing: 20) {
                    ForEach(source == .home ? Array(page.videos.dropFirst()) : page.videos) { video in
                        VideoCard(video: video) { play(video) }
                    }
                }
                ForEach(page.playlists, id: \.playlistId) { playlist in
                    NavigationLink { FeedView(source: .playlist(playlist.playlistId), title: playlist.title ?? "Playlist", play: play) } label: {
                        PlaylistRow(playlist: playlist)
                    }.buttonStyle(.plain)
                }
                if page.continuation != nil {
                    Button { Task { await loadMore() } } label: {
                        HStack { if moreLoading { ProgressView() }; Text("Mehr entdecken") }.frame(maxWidth: .infinity).padding(10)
                    }.buttonStyle(.glass).disabled(moreLoading)
                }
            }.padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 24)
        }
        .navigationTitle(title).navigationBarTitleDisplayMode(.large)
        .refreshable { await load() }
        .task(id: sourceKey) { await load() }
        .onChange(of: service.accountRevision) { _, _ in Task { await load() } }
    }
    private var sourceKey: String { String(describing: source) }
    private var masthead: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Capsule().fill(Palette.mint).frame(width: 6, height: 6)
                Text(ProcessInfo.processInfo.arguments.contains("-ui-testing") ? "DESIGN-VORSCHAU" : "DEIN MOMENT. DEIN YOUTUBE.")
                    .font(.system(size: 10, weight: .semibold, design: .rounded)).tracking(2).foregroundStyle(.secondary)
            }
            Text("Weniger Lärm.\nMehr Lieblingsvideos.")
                .font(.system(.largeTitle, design: .rounded).weight(.bold)).tracking(-1)
                .fixedSize(horizontal: false, vertical: true)
            Text("Mach es dir schön.").font(.subheadline).foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                HStack(spacing: 9) {
                    topic("Musik", symbol: "waveform", query: "Musik")
                    topic("Technik", symbol: "cpu", query: "Technik")
                    topic("Gaming", symbol: "gamecontroller", query: "Gaming")
                    topic("Shorts", symbol: "play.rectangle.on.rectangle", query: "#shorts")
                }.padding(.vertical, 6)
            }.scrollIndicators(.hidden)
        }.padding(.bottom, 6)
    }
    private func topic(_ title: String, symbol: String, query: String) -> some View {
        NavigationLink { FeedView(source: .search(query), title: title, play: play) } label: {
            Label(title, systemImage: symbol).font(.subheadline.weight(.medium)).padding(.horizontal, 4).padding(.vertical, 4)
        }.buttonStyle(.glass)
    }
    private var skeleton: some View {
        VStack(spacing: 20) {
            RoundedRectangle(cornerRadius: 24).fill(.primary.opacity(0.04)).aspectRatio(16/9, contentMode: .fit).overlay(ProgressView("Deine Videos werden geladen"))
            RoundedRectangle(cornerRadius: 24).fill(.primary.opacity(0.04)).frame(height: 120)
        }.accessibilityLabel("Inhalte werden geladen")
    }
    private func load() async {
        generation = UUID(); let requestGeneration = generation
        loading = true; error = nil; page = VideoPage()
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
            page = VideoPage(videos: PreviewData.videos); loading = false; return
        }
        do {
            let response = try await service.feed(source)
            guard !Task.isCancelled, requestGeneration == generation else { return }
            page = response
        } catch {
            guard !Task.isCancelled, requestGeneration == generation else { return }
            self.error = error.localizedDescription
        }
        if requestGeneration == generation { loading = false }
    }
    private func loadMore() async {
        guard !moreLoading, let token = page.continuation else { return }
        let requestGeneration = generation; moreLoading = true
        defer { moreLoading = false }
        do {
            let next = try await service.feed(source, continuation: token)
            guard requestGeneration == generation, !Task.isCancelled else { return }
            page.videos = (page.videos + next.videos).unique(); page.continuation = next.continuation
            var channelIDs = Set(page.channels.map(\.channelId)); var playlistIDs = Set(page.playlists.map(\.playlistId))
            page.channels += next.channels.filter { channelIDs.insert($0.channelId).inserted }
            page.playlists += next.playlists.filter { playlistIDs.insert($0.playlistId).inserted }
        } catch { if requestGeneration == generation { self.error = error.localizedDescription } }
    }
}

func sectionTitle(_ title: String, subtitle: String? = nil) -> some View {
    VStack(alignment: .leading, spacing: 5) {
        Text(title).font(.title3.bold())
        if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
    }
}

struct SearchView: View {
    var play: (Video) -> Void
    @State private var text = ""
    @State private var query = ""
    @AppStorage("recentSearches") private var recentSearches = ""
    var body: some View {
        Group {
            if query.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        EmptyState(title: "Was inspiriert dich?", message: "Suche nach Videos, Kanälen und Playlists. Du kannst auch einen YouTube-Link einfügen.", symbol: "magnifyingglass")
                        if !recentSearches.isEmpty {
                            sectionTitle("Zuletzt gesucht")
                            ForEach(recentSearches.components(separatedBy: "\n"), id: \.self) { value in
                                Button { text = value; submit() } label: {
                                    HStack { Image(systemName: "clock"); Text(value); Spacer(); Image(systemName: "arrow.up.left") }.padding(16).lumaCard(corner: 18)
                                }.buttonStyle(.plain)
                            }
                            Button("Suchverlauf löschen", role: .destructive) { recentSearches = "" }.font(.caption)
                        }
                    }.padding(20)
                }.navigationTitle("Suchen")
            } else { FeedView(source: .search(query), title: query, play: play).id(query) }
        }
        .searchable(text: $text, prompt: "Videos, Kanäle oder YouTube-Link")
        .onSubmit(of: .search) { submit() }
        .onChange(of: text) { _, new in if new.isEmpty { query = "" } }
    }
    private func submit() {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        if let id = VideoLink.id(from: value) { play(Video(id: id)); return }
        query = value
        let old = recentSearches.components(separatedBy: "\n").filter { !$0.isEmpty && $0 != value }
        recentSearches = Array(([value] + old).prefix(8)).joined(separator: "\n")
    }
}

struct SubscriptionView: View {
    @EnvironmentObject private var service: YouTubeService
    var play: (Video) -> Void
    var login: () -> Void
    var body: some View {
        Group {
            if service.signedIn { FeedView(source: .subscriptions, title: "Deine Abos", play: play) }
            else {
                ScrollView {
                    EmptyState(title: "Deine Lieblingskanäle", message: "Verbinde dein YouTube-Konto. Hier findest du dann die neuesten Videos deiner Abos.", symbol: "square.stack.3d.up", actionTitle: "Konto verbinden", action: login)
                }.navigationTitle("Abos")
            }
        }
    }
}

struct PlaylistRow: View {
    var playlist: YTPlaylist
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "rectangle.stack.fill").font(.title2).foregroundStyle(Palette.mint).frame(width: 54, height: 54).lumaGlass(corner: 16)
            VStack(alignment: .leading, spacing: 5) {
                Text(playlist.title ?? "Playlist").font(.headline).lineLimit(2)
                Text(playlist.videoCount ?? "YouTube-Playlist").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
        }.padding(15).lumaCard(corner: 22)
    }
}

struct LibraryView: View {
    @EnvironmentObject private var service: YouTubeService
    @EnvironmentObject private var library: LocalLibrary
    var play: (Video) -> Void
    var login: () -> Void
    @State private var playlists: [YTPlaylist] = []
    @State private var remoteHistory: [Video] = []
    @State private var error: String?
    @State private var loading = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 16) {
                    Image(systemName: "person.crop.circle.fill").font(.system(size: 43)).foregroundStyle(Palette.violet)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(service.accountName ?? "Deine Mediathek").font(.title3.bold())
                        Text(service.signedIn ? "Mit YouTube verbunden" : "Lieblingsvideos bleiben bei dir.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }.padding(20).lumaCard()
                if !service.signedIn { Button("YouTube-Konto verbinden", action: login).buttonStyle(.glassProminent) }
                sectionTitle("Lokal gemerkt", subtitle: "Deine persönliche Merkliste auf diesem Gerät.")
                if library.saved.isEmpty { Text("Halte ein Video gedrückt oder tippe im Player auf Merken.").font(.subheadline).foregroundStyle(.secondary) }
                ForEach(library.saved) { video in VideoRow(video: video) { play(video) } }
                if !library.history.isEmpty {
                    sectionTitle("Weiterschauen", subtitle: "Mit gespeichertem Wiedergabefortschritt.")
                    ForEach(library.history.prefix(12)) { entry in
                        VStack(spacing: 5) {
                            VideoRow(video: entry.video) { play(entry.video) }
                            if entry.duration > 0 { ProgressView(value: min(entry.seconds/entry.duration,1)).tint(Palette.mint).padding(.horizontal, 12) }
                        }
                    }
                }
                if service.signedIn {
                    sectionTitle("YouTube-Playlists")
                    NavigationLink { FeedView(source: .playlist("WL"), title: "Später ansehen", play: play) } label: {
                        Label("Später ansehen", systemImage: "clock").frame(maxWidth: .infinity, alignment: .leading).padding(18).lumaCard()
                    }.buttonStyle(.plain)
                    NavigationLink { FeedView(source: .playlist("LL"), title: "Gefällt mir", play: play) } label: {
                        Label("Gefällt mir", systemImage: "hand.thumbsup").frame(maxWidth: .infinity, alignment: .leading).padding(18).lumaCard()
                    }.buttonStyle(.plain)
                    if loading { ProgressView() }
                    ForEach(playlists, id: \.playlistId) { playlist in
                        NavigationLink { FeedView(source: .playlist(playlist.playlistId), title: playlist.title ?? "Playlist", play: play) } label: { PlaylistRow(playlist: playlist) }.buttonStyle(.plain)
                    }
                    Button("YouTube-Verlauf laden", systemImage: "clock.arrow.circlepath") { Task { await loadHistory() } }.buttonStyle(.glass)
                    ForEach(remoteHistory) { video in VideoRow(video: video) { play(video) } }
                }
                if let error { InlineError(message: error) { Task { await loadPlaylists() } } }
            }.padding(20).padding(.bottom, 20)
        }.navigationTitle("Mediathek")
            .task(id: service.accountRevision) { await loadPlaylists() }
            .refreshable { await loadPlaylists() }
    }
    private func loadPlaylists() async {
        playlists = []; remoteHistory = []; error = nil
        guard service.signedIn else { return }
        loading = true; defer { loading = false }
        let revision = service.accountRevision
        do { let results = try await service.playlists(); if revision == service.accountRevision { playlists = results } }
        catch { if revision == service.accountRevision { self.error = error.localizedDescription } }
    }
    private func loadHistory() async {
        let revision = service.accountRevision
        do { let results = try await service.history(); if revision == service.accountRevision { remoteHistory = results } }
        catch { if revision == service.accountRevision { self.error = error.localizedDescription } }
    }
}

struct ChannelView: View {
    @EnvironmentObject private var service: YouTubeService
    var channelID: String
    var play: (Video) -> Void
    @State private var info: ChannelInfosResponse?
    @State private var videos: [Video] = []
    @State private var error: String?
    @State private var busy = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let info {
                    HStack(spacing: 18) {
                        AsyncImage(url: info.avatarThumbnails.last?.url) { image in image.resizable().scaledToFill() } placeholder: { Image(systemName: "person.crop.circle.fill").resizable() }
                            .frame(width: 82, height: 82).clipShape(Circle())
                        VStack(alignment: .leading, spacing: 6) {
                            Text(info.name ?? "Kanal").font(.title2.bold())
                            Text(info.subscriberCount ?? "").font(.subheadline).foregroundStyle(.secondary)
                            if service.signedIn {
                                Button(info.subscribeStatus == true ? "Abonniert" : "Abonnieren") { Task { await subscribe() } }.buttonStyle(.glassProminent).disabled(busy)
                            }
                        }
                    }.padding(20).lumaCard()
                    if let description = info.shortDescription { Text(description).font(.subheadline).foregroundStyle(.secondary) }
                }
                if let error { InlineError(message: error) { Task { await load() } } }
                if busy && videos.isEmpty { ProgressView("Kanal wird geladen") }
                ForEach(videos) { video in VideoCard(video: video) { play(video) } }
            }.padding(20)
        }.navigationTitle(info?.name ?? "Kanal").navigationBarTitleDisplayMode(.inline).background(AmbientBackground()).task { await load() }
    }
    private func load() async {
        busy = true; error = nil; defer { busy = false }
        do {
            let initial = try await ChannelInfosResponse.sendThrowingRequest(youtubeModel: service.model, data: [.browseId: channelID])
            let response = try await initial.getChannelContentThrowing(forType: .videos, youtubeModel: service.model)
            info = response
            videos = (response.currentContent as? ChannelInfosResponse.Videos)?.items.compactMap { $0 as? YTVideo }.map(Video.init).unique() ?? []
        } catch { self.error = error.localizedDescription }
    }
    private func subscribe() async {
        busy = true; defer { busy = false }
        do {
            let next = info?.subscribeStatus != true
            try await service.setSubscription(channelID: channelID, subscribed: next)
            info?.subscribeStatus = next
        } catch { self.error = error.localizedDescription }
    }
}
