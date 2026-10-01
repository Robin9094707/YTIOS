import SwiftUI

struct PlaybackProgress: View {
    @ObservedObject var playback: PlaybackStore
    @ObservedObject var clock: PlaybackClock
    @State private var scrubbing = false
    @State private var target = 0.0
    var body: some View {
        VStack(spacing: 8) {
            Slider(value: Binding(get: { scrubbing ? target : min(clock.seconds, max(clock.duration, 1)) }, set: { target = $0 }), in: 0...max(clock.duration, 1)) { editing in
                if editing { target = clock.seconds; scrubbing = true }
                else { playback.seek(to: target); scrubbing = false }
            }.tint(Palette.mint).disabled(clock.duration <= 0).accessibilityLabel("Wiedergabeposition")
            HStack(spacing: 18) {
                Text(TimeText.format(scrubbing ? target : clock.seconds)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                Button("15 Sekunden zurück", systemImage: "gobackward.15") { playback.skip(-15) }
                Button(playback.playing ? "Pause" : "Abspielen", systemImage: playback.playing ? "pause.fill" : "play.fill") { playback.toggle() }
                    .font(.title3).frame(width: 40)
                Button("15 Sekunden vor", systemImage: "goforward.15") { playback.skip(15) }
                Spacer()
                Text(TimeText.format(clock.duration)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }.labelStyle(.iconOnly).buttonStyle(.plain).disabled(playback.loading || playback.error != nil)
        }.accessibilityIdentifier("playbackProgress")
    }
}

struct PlaybackCaptions: View {
    @ObservedObject var playback: PlaybackStore
    @ObservedObject var clock: PlaybackClock
    var body: some View {
        VStack {
            Spacer()
            if let caption = playback.captions.first(where: { clock.seconds >= $0.start && clock.seconds < $0.end })?.text {
                Text(caption).font(.subheadline.weight(.medium)).multilineTextAlignment(.center)
                    .foregroundStyle(.white).padding(8).background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 7))
                    .padding(.bottom, 42).padding(.horizontal, 18)
            }
        }.allowsHitTesting(false)
    }
}
