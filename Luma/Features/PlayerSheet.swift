import SwiftUI
import AVKit
import YouTubeKit

struct NativePlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.updatesNowPlayingInfoCenter = false
        controller.videoGravity = .resizeAspect
        return controller
    }
    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
    }
}

struct PlayerSheet: View {
    @EnvironmentObject private var playback: PlaybackStore
    @EnvironmentObject private var service: YouTubeService
    @EnvironmentObject private var library: LocalLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var details: MoreVideoInfosResponse?
    @State private var comments: [YTComment] = []
    @State private var commentsToken: String?
    @State private var creationToken: String?
    @State private var captionOptions: [YTCaption] = []
    @State private var commentText = ""
    @State private var busy = false
    @State private var commentsBusy = false
    @State private var detailsError: String?
    @State private var actionError: String?
    @State private var liked = false
    @State private var subscribed = false
    @State private var loginPresented = false
    @State private var playlistsPresented = false
    @State private var queuePresented = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    videoSurface
                    if let video = playback.video {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(details?.videoTitle ?? video.title).font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    if let channelID = details?.channel?.channelId ?? video.channelID {
                                        NavigationLink {
                                            ChannelView(channelID: channelID) { next in playback.open(next) }
                                        } label: { Text(details?.channel?.name ?? video.channel).font(.headline).foregroundStyle(Palette.mint) }
                                    } else { Text(video.channel).font(.headline).foregroundStyle(Palette.mint) }
                                    if let views = details?.viewsCount.shortViewsCount ?? video.views { Text(views).font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer()
                                if let id = details?.channel?.channelId ?? video.channelID {
                                    Button(subscribed ? "Abonniert" : "Abonnieren") {
                                        if service.signedIn { Task { await subscription(id) } } else { loginPresented = true }
                                    }.buttonStyle(.glass).disabled(busy)
                                }
                            }
                        }
                        actionBar(video)
                        playbackOptions
                        if let chapters = details?.chapters, !chapters.isEmpty {
                            sectionTitle("Kapitel")
                            ScrollView(.horizontal) {
                                HStack {
                                    ForEach(Array(chapters.enumerated()), id: \.offset) { _, chapter in
                                        Button {
                                            playback.seek(to: Double(chapter.startTimeSeconds ?? 0))
                                        } label: {
                                            VStack(alignment: .leading, spacing: 5) {
                                                Text(chapter.title ?? "Kapitel").font(.caption.weight(.medium)).lineLimit(1)
                                                Text(TimeText.format(Double(chapter.startTimeSeconds ?? 0))).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                                            }.frame(width: 145, alignment: .leading).padding(14)
                                        }.buttonStyle(.glass)
                                    }
                                }
                            }.scrollIndicators(.hidden)
                        }
                        if let description = details?.videoDescription?.compactMap(\.text).joined(), !description.isEmpty {
                            DisclosureGroup("Beschreibung") { Text(description).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled).padding(.top, 12) }
                                .padding(18).lumaCard(corner: 20)
                        }
                        if let detailsError { InlineError(message: detailsError) { Task { await loadDetails() } } }
                        commentsSection
                        if let recommended = details?.recommendedVideos.compactMap({ $0 as? YTVideo }).map(Video.init).unique(), !recommended.isEmpty {
                            sectionTitle("Weiter entdecken")
                            ForEach(recommended.prefix(16)) { next in VideoRow(video: next) { playback.open(next) } }
                        }
                    }
                }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 30)
            }.background(AmbientBackground())
                .navigationTitle("Dein Moment").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("Minimieren", systemImage: "chevron.down") { dismiss() } }
                    ToolbarItem(placement: .topBarTrailing) { Button("Warteschlange", systemImage: "list.bullet") { queuePresented = true } }
                }
                .task(id: playback.video?.id) { await loadDetails() }
                .sheet(isPresented: $loginPresented) { LoginSheet() }
                .sheet(isPresented: $playlistsPresented) { if let video = playback.video { AddToPlaylistSheet(video: video) } }
                .sheet(isPresented: $queuePresented) { QueueSheet() }
                .alert("YouTube", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
                    Button("OK") { actionError = nil }
                } message: { Text(actionError ?? "") }
        }
    }
    private var videoSurface: some View {
        ZStack {
            NativePlayer(player: playback.player).aspectRatio(16/9, contentMode: .fit)
            if playback.loading {
                VStack(spacing: 10) { ProgressView().tint(.white); Text("Dein Video wird geladen").font(.caption) }
                    .foregroundStyle(.white).padding(18).background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
            }
            if playback.captionsEnabled, let caption = playback.activeCaption {
                VStack { Spacer(); Text(caption).font(.subheadline.weight(.medium)).multilineTextAlignment(.center)
                    .foregroundStyle(.white).padding(7).background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 6)).padding(.bottom, 40).padding(.horizontal, 15) }.allowsHitTesting(false)
            }
        }.background(.black).clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(alignment: .bottom) {
                if let error = playback.error {
                    VStack(spacing: 10) {
                        Text(error).font(.caption).multilineTextAlignment(.center)
                        Button("Stream erneut laden") { playback.retry() }.buttonStyle(.glassProminent)
                    }.foregroundStyle(.white).padding(16).frame(maxWidth: .infinity).background(.black.opacity(0.85))
                }
            }
    }
    private func actionBar(_ video: Video) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                Button { if service.signedIn { Task { await like(video) } } else { loginPresented = true } } label: {
                    Label(liked ? "Gefällt dir" : "Gefällt mir", systemImage: liked ? "hand.thumbsup.fill" : "hand.thumbsup")
                }.buttonStyle(.glass).disabled(busy)
                Button { library.toggle(video) } label: {
                    Label(library.contains(video) ? "Gemerkt" : "Merken", systemImage: library.contains(video) ? "bookmark.fill" : "bookmark")
                }.buttonStyle(.glass)
                Button("Playlist", systemImage: "text.badge.plus") {
                    if service.signedIn { playlistsPresented = true } else { loginPresented = true }
                }.buttonStyle(.glass)
                ShareLink(item: video.shareURL) { Label("Teilen", systemImage: "square.and.arrow.up") }.buttonStyle(.glass)
            }.padding(.vertical, 6)
        }.scrollIndicators(.hidden)
    }
    private var playbackOptions: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach([Float(0.5),0.75,1,1.25,1.5,1.75,2], id: \.self) { rate in
                    Button("\(rate.formatted())×") { playback.setSpeed(rate) }
                }
            } label: { Label("\(playback.speed.formatted())×", systemImage: "speedometer") }.buttonStyle(.glass)
            Menu {
                Button("Automatisch") { playback.setQuality(0) }
                ForEach([360,480,720,1080,1440,2160], id: \.self) { height in
                    Button("Bis \(height)p") { playback.setQuality(height) }
                }
                ForEach(playback.choices) { choice in Button(choice.label) { playback.choose(choice) } }
                Text("Auflösung hängt von den verfügbaren Streams ab.")
            } label: { Label("Qualität", systemImage: "sparkles.rectangle.stack") }.buttonStyle(.glass)
            Menu {
                Button("Aus") { playback.captionsEnabled = false }
                ForEach(captionOptions, id: \.id) { caption in
                    Button(caption.languageName) { Task {
                        do { try await playback.loadCaptions(caption) } catch { actionError = "Untertitel sind momentan nicht verfügbar." }
                    } }
                }
            } label: { Image(systemName: "captions.bubble") }.buttonStyle(.glass).disabled(captionOptions.isEmpty)
            Spacer(minLength: 0)
            Menu {
                Button("Timer aus") { playback.sleep(after: nil) }
                ForEach([15,30,45,60], id: \.self) { minutes in Button("\(minutes) Minuten") { playback.sleep(after: minutes) } }
            } label: { Image(systemName: playback.sleepMinutes == nil ? "moon" : "moon.fill") }.buttonStyle(.glass)
        }.font(.caption)
    }
    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Kommentare", subtitle: details?.commentsCount)
            if service.signedIn, creationToken != nil {
                HStack(alignment: .bottom) {
                    TextField("Dein Kommentar", text: $commentText, axis: .vertical).lineLimit(1...5).padding(12).lumaCard(corner: 14)
                    Button("Senden", systemImage: "arrow.up") { Task { await postComment() } }.labelStyle(.iconOnly).buttonStyle(.glassProminent)
                        .disabled(busy || commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            ForEach(comments, id: \.commentIdentifier) { comment in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(comment.sender?.name ?? "YouTube").font(.caption.weight(.semibold)).foregroundStyle(Palette.mint)
                        Spacer()
                        Text(comment.timePosted ?? "").font(.caption2).foregroundStyle(.tertiary)
                    }
                    Text(comment.text).font(.subheadline).textSelection(.enabled)
                    if let likes = comment.likesCount { Label(likes, systemImage: "hand.thumbsup").font(.caption).foregroundStyle(.secondary) }
                }.padding(16).lumaCard(corner: 18)
            }
            if commentsBusy { ProgressView("Kommentare werden geladen") }
            if commentsToken != nil { Button("Weitere Kommentare") { Task { await loadComments() } }.buttonStyle(.glass).disabled(commentsBusy) }
            else if comments.isEmpty && !commentsBusy { Text("Für dieses Video sind gerade keine Kommentare verfügbar.").font(.caption).foregroundStyle(.secondary) }
        }
    }
    private func loadDetails() async {
        details = nil; comments = []; captionOptions = []; creationToken = nil; commentsToken = nil; detailsError = nil; liked = false; subscribed = false
        guard let id = playback.video?.id else { return }
        do {
            let response = try await MoreVideoInfosResponse.sendThrowingRequest(youtubeModel: service.model, data: [.query: id])
            guard !Task.isCancelled, playback.video?.id == id else { return }
            details = response; liked = response.authenticatedInfos?.likeStatus == .liked
            subscribed = response.authenticatedInfos?.subscriptionStatus == true
            commentsToken = response.commentsContinuationToken
            if commentsToken != nil { await loadComments(initial: true) }
            if let info = try? await VideoInfosResponse.sendThrowingRequest(youtubeModel: service.model, data: [.query: id]), playback.video?.id == id, !Task.isCancelled {
                captionOptions = info.captions
            }
        } catch { if playback.video?.id == id, !Task.isCancelled { detailsError = "Zusätzliche Videoinfos konnten nicht geladen werden." } }
    }
    private func loadComments(initial: Bool = false) async {
        guard !commentsBusy, let token = commentsToken, let id = playback.video?.id else { return }
        commentsBusy = true; defer { commentsBusy = false }
        do {
            let new: [YTComment]; let next: String?
            if initial {
                let r = try await VideoCommentsResponse.sendThrowingRequest(youtubeModel: service.model, data: [.continuation: token])
                guard !Task.isCancelled, playback.video?.id == id else { return }
                new = r.results; next = r.continuationToken; creationToken = r.commentCreationToken
            } else {
                let r = try await VideoCommentsResponse.Continuation.sendThrowingRequest(youtubeModel: service.model, data: [.continuation: token])
                new = r.results; next = r.continuationToken
            }
            guard !Task.isCancelled, playback.video?.id == id else { return }
            var seen = Set(comments.map(\.commentIdentifier))
            comments += new.filter { seen.insert($0.commentIdentifier).inserted }; commentsToken = next
        } catch { if playback.video?.id == id { actionError = "Kommentare konnten nicht geladen werden." } }
    }
    private func like(_ video: Video) async {
        busy = true; defer { busy = false }
        do { let next = !liked; try await service.setLike(videoID: video.id, liked: next); if playback.video?.id == video.id { liked = next } }
        catch { actionError = error.localizedDescription }
    }
    private func subscription(_ id: String) async {
        busy = true; defer { busy = false }
        do { let next = !subscribed; try await service.setSubscription(channelID: id, subscribed: next); subscribed = next }
        catch { actionError = error.localizedDescription }
    }
    private func postComment() async {
        guard let token = creationToken, let id = playback.video?.id else { return }
        busy = true; defer { busy = false }
        do {
            let new = try await service.postComment(text: commentText, token: token)
            if playback.video?.id == id { if let new { comments.insert(new, at: 0) }; commentText = "" }
        } catch { actionError = error.localizedDescription }
    }
}

struct AddToPlaylistSheet: View {
    @EnvironmentObject private var service: YouTubeService
    @Environment(\.dismiss) private var dismiss
    var video: Video
    @State private var playlists: [YTPlaylist] = []
    @State private var title = ""
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("\(video.title)").font(.headline)
                    Button("Später ansehen", systemImage: "clock") { Task { await add("WL") } }.buttonStyle(.glass).disabled(busy)
                    ForEach(playlists, id: \.playlistId) { playlist in
                        Button { Task { await add(playlist.playlistId) } } label: { PlaylistRow(playlist: playlist) }.buttonStyle(.plain).disabled(busy)
                    }
                    sectionTitle("Neue private Playlist")
                    TextField("Name der Playlist", text: $title).padding(15).lumaCard(corner: 16)
                    Button("Erstellen und Video hinzufügen") { Task {
                        busy = true; defer { busy = false }
                        do { try await service.createPlaylist(title: title, videoID: video.id); dismiss() }
                        catch { self.error = error.localizedDescription }
                    } }.buttonStyle(.glassProminent).disabled(busy || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if busy { ProgressView() }
                    if let error { Text(error).foregroundStyle(.orange).font(.caption) }
                }.padding(20)
            }.background(AmbientBackground()).navigationTitle("Zur Playlist hinzufügen").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fertig") { dismiss() }.disabled(busy) } }
                .task { do { playlists = try await service.playlists() } catch { self.error = error.localizedDescription } }
        }
    }
    private func add(_ id: String) async {
        busy = true; defer { busy = false }
        do { try await service.add(videoID: video.id, to: id); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

struct QueueSheet: View {
    @EnvironmentObject private var playback: PlaybackStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                if playback.queue.isEmpty { Text("Halte ein Video gedrückt und füge es zur Warteschlange hinzu.").foregroundStyle(.secondary) }
                ForEach(playback.queue) { video in VideoRow(video: video) { playback.queue.removeAll { $0.id == video.id }; playback.open(video); dismiss() } }
                    .onDelete { playback.queue.remove(atOffsets: $0) }.onMove { playback.queue.move(fromOffsets: $0, toOffset: $1) }
            }.scrollContentBackground(.hidden).background(AmbientBackground()).navigationTitle("Als Nächstes")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { EditButton() }
                    ToolbarItem(placement: .topBarTrailing) { Button("Fertig") { dismiss() } }
                }
        }
    }
}
