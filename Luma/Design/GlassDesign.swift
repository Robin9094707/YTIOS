import SwiftUI

enum Palette {
    static let violet = Color(red: 0.66, green: 0.53, blue: 1)
    static let mint = Color(red: 0.38, green: 0.89, blue: 0.83)
}

struct AmbientBackground: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                (scheme == .dark ? Color(red: 0.035, green: 0.043, blue: 0.072) : Color(red: 0.95, green: 0.96, blue: 0.99))
                Circle().fill(Palette.violet.opacity(scheme == .dark ? 0.19 : 0.14))
                    .frame(width: proxy.size.width * 1.2).blur(radius: 95).offset(x: -170, y: -210)
                Circle().fill(Palette.mint.opacity(scheme == .dark ? 0.09 : 0.10))
                    .frame(width: proxy.size.width).blur(radius: 110).offset(x: proxy.size.width * 0.45, y: proxy.size.height * 0.4)
            }
        }.ignoresSafeArea().allowsHitTesting(false)
    }
}

struct GlassSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduce
    var corner: CGFloat
    func body(content: Content) -> some View {
        if reduce {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: corner))
        } else {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: corner))
        }
    }
}
extension View {
    func lumaGlass(corner: CGFloat = 24) -> some View { modifier(GlassSurface(corner: corner)) }
    func lumaCard(corner: CGFloat = 24) -> some View {
        background(.thinMaterial, in: RoundedRectangle(cornerRadius: corner))
            .overlay(RoundedRectangle(cornerRadius: corner).strokeBorder(.primary.opacity(0.07), lineWidth: 1))
    }
}

struct Thumbnail: View {
    var video: Video
    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.violet.opacity(0.55), Color.indigo.opacity(0.45), Palette.mint.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
            if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
                Image(systemName: video.title.contains("Musik") ? "waveform" : video.title.contains("Code") ? "curlybraces" : "mountain.2.fill")
                    .font(.system(size: 75, weight: .ultraLight)).foregroundStyle(.white.opacity(0.8))
                Circle().stroke(.white.opacity(0.10), lineWidth: 1).padding(25)
            } else {
                AsyncImage(url: video.thumbnail) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                    else { Image(systemName: "play.rectangle").font(.largeTitle).foregroundStyle(.white.opacity(0.65)) }
                }
            }
        }.clipped().accessibilityHidden(true)
    }
}

struct VideoCard: View {
    @EnvironmentObject private var playback: PlaybackStore
    @EnvironmentObject private var library: LocalLibrary
    var video: Video
    var featured = false
    var play: () -> Void
    var body: some View {
        Button(action: play) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    Thumbnail(video: video).aspectRatio(16/9, contentMode: .fit)
                    LinearGradient(colors: [.clear, .black.opacity(featured ? 0.70 : 0.25)], startPoint: .center, endPoint: .bottom)
                    HStack {
                        if featured {
                            Label("Für deinen Moment", systemImage: "sparkles")
                                .font(.caption.weight(.medium)).padding(.horizontal, 12).padding(.vertical, 8).lumaGlass(corner: 20)
                        }
                        Spacer()
                        if let duration = video.duration {
                            Text(duration).font(.caption.monospacedDigit().weight(.semibold))
                                .padding(.horizontal, 8).padding(.vertical, 4).background(.black.opacity(0.55), in: Capsule())
                        }
                    }.foregroundStyle(.white).padding(14)
                }
                VStack(alignment: .leading, spacing: 7) {
                    Text(video.title).font(featured ? .title3.weight(.bold) : .headline).lineLimit(2).multilineTextAlignment(.leading)
                    HStack(spacing: 7) {
                        Circle().fill(Palette.violet.opacity(0.3)).frame(width: 22, height: 22)
                            .overlay(Text(String(video.channel.prefix(1))).font(.caption2.weight(.bold)))
                        Text(video.channel).font(.subheadline).lineLimit(1)
                        Spacer()
                        Image(systemName: "play.fill").font(.caption).foregroundStyle(Palette.mint)
                    }.foregroundStyle(.secondary)
                    if !video.caption.isEmpty { Text(video.caption).font(.caption).foregroundStyle(.tertiary).lineLimit(1) }
                }.padding(16)
            }.lumaCard().clipShape(RoundedRectangle(cornerRadius: 24))
        }.buttonStyle(.plain)
            .accessibilityLabel("\(video.title), \(video.channel)")
            .contextMenu {
                Button(library.contains(video) ? "Aus Merkliste entfernen" : "Lokal merken", systemImage: "bookmark") { library.toggle(video) }
                Button("Zur Warteschlange", systemImage: "text.line.first.and.arrowtriangle.forward") { playback.enqueue(video) }
                ShareLink(item: video.shareURL) { Label("Teilen", systemImage: "square.and.arrow.up") }
            }
    }
}

struct VideoRow: View {
    var video: Video
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Thumbnail(video: video).frame(width: 116, height: 70).clipShape(RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 5) {
                    Text(video.title).font(.subheadline.weight(.semibold)).lineLimit(2).multilineTextAlignment(.leading)
                    Text(video.channel).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "play.fill").font(.caption).foregroundStyle(Palette.mint)
            }.padding(11).lumaCard(corner: 20)
        }.buttonStyle(.plain)
    }
}

struct EmptyState: View {
    var title: String
    var message: String
    var symbol = "sparkles.tv"
    var actionTitle: String?
    var action: (() -> Void)?
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: symbol).font(.system(size: 45, weight: .light)).foregroundStyle(Palette.violet)
                .frame(width: 100, height: 100).lumaGlass(corner: 32)
            Text(title).font(.title2.bold()).multilineTextAlignment(.center)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 340)
            if let actionTitle, let action { Button(actionTitle, action: action).buttonStyle(.glassProminent).tint(Palette.violet) }
        }.frame(maxWidth: .infinity).padding(.horizontal, 24).padding(.vertical, 48)
    }
}

struct InlineError: View {
    var message: String
    var retry: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Gerade nicht verfügbar", systemImage: "exclamationmark.circle").font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary)
            Button("Erneut versuchen", action: retry).buttonStyle(.glass)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(20).lumaCard()
    }
}

enum TimeText {
    static func format(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let value = max(0, Int(seconds))
        return value >= 3600 ? String(format: "%d:%02d:%02d", value/3600, value%3600/60, value%60) : String(format: "%d:%02d", value/60, value%60)
    }
}
