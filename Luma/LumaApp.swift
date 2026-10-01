import SwiftUI

@main
struct LumaApp: App {
    init() { UserDefaults.standard.register(defaults: ["remoteFallback": true, "autoplay": false]) }
    @StateObject private var service = YouTubeService()
    @StateObject private var library = LocalLibrary(inMemory: ProcessInfo.processInfo.arguments.contains("-ui-testing"))
    @StateObject private var playback = PlaybackStore()
    @AppStorage("appearance") private var appearance = "dark"
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(service).environmentObject(library).environmentObject(playback)
                .preferredColorScheme(appearance == "system" ? nil : appearance == "light" ? .light : .dark)
                .tint(Palette.violet)
                .task {
                    playback.connect(service: service, library: library)
                    if !ProcessInfo.processInfo.arguments.contains("-ui-testing") { await service.bootstrap() }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var playback: PlaybackStore
    @EnvironmentObject private var library: LocalLibrary
    @Environment(\.scenePhase) private var scenePhase
    @State private var playerPresented = false
    @State private var settingsPresented = false
    @State private var loginPresented = false
    @State private var libraryErrorShown = false
    @State private var tab = 0
    var body: some View {
        ZStack {
            AmbientBackground()
            TabView(selection: $tab) {
                Tab("Entdecken", systemImage: "sparkles.tv", value: 0) {
                    navigation { FeedView(source: .home, title: "Entdecken", play: open) }
                }
                Tab("Suchen", systemImage: "magnifyingglass", value: 1) {
                    navigation { SearchView(play: open) }
                }
                Tab("Abos", systemImage: "square.stack.3d.up", value: 2) {
                    navigation { SubscriptionView(play: open, login: { loginPresented = true }) }
                }
                Tab("Mediathek", systemImage: "rectangle.stack", value: 3) {
                    navigation { LibraryView(play: open, login: { loginPresented = true }) }
                }
            }
            .tabBarMinimizeBehavior(.onScrollDown)
        }
        .fullScreenCover(isPresented: $playerPresented) { PlayerSheet() }
        .sheet(isPresented: $settingsPresented) { SettingsView().presentationDragIndicator(.visible) }
        .sheet(isPresented: $loginPresented) { LoginSheet().presentationDragIndicator(.visible) }
        .onOpenURL { url in if let id = VideoLink.id(from: url.absoluteString) { open(Video(id: id)) } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { playback.saveProgress() } }
        .alert("Mediathek", isPresented: Binding(get: { library.persistenceError != nil && !libraryErrorShown }, set: { if !$0 { libraryErrorShown = true } })) {
            Button("OK", role: .cancel) { libraryErrorShown = true }
        } message: { Text(library.persistenceError ?? "") }
    }
    private func open(_ video: Video) { playback.open(video); playerPresented = true }
    private func navigation<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        NavigationStack {
            content()
                .background(AmbientBackground())
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        HStack(spacing: 6) {
                            Image(systemName: "play.rectangle.fill").foregroundStyle(Palette.mint)
                            Text("luma").font(.system(.headline, design: .rounded).weight(.bold))
                        }.accessibilityLabel("Luma")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Einstellungen", systemImage: "slider.horizontal.3") { settingsPresented = true }
                            .accessibilityIdentifier("settingsButton")
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 8) {
                    if playback.video != nil { MiniPlayer(open: { playerPresented = true }).padding(.horizontal, 14).padding(.bottom, 4) }
                }
        }
    }
}

struct MiniPlayer: View {
    @EnvironmentObject private var playback: PlaybackStore
    var open: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Button(action: open) {
                HStack(spacing: 12) {
                    if let video = playback.video { Thumbnail(video: video).frame(width: 52, height: 44).clipShape(RoundedRectangle(cornerRadius: 12)) }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(playback.video?.title ?? "").font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(playback.error != nil ? "Wiedergabe nicht verfügbar" : playback.video?.channel ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain)
            if playback.loading { ProgressView() }
            else { Button(playback.playing ? "Pause" : "Abspielen", systemImage: playback.playing ? "pause.fill" : "play.fill") { playback.toggle() }.labelStyle(.iconOnly) }
            Button("Schließen", systemImage: "xmark") { playback.stop() }.labelStyle(.iconOnly).foregroundStyle(.secondary)
        }.padding(12).lumaGlass(corner: 24)
    }
}
