import SwiftUI
import WebKit

struct SettingsView: View {
    @EnvironmentObject private var service: YouTubeService
    @EnvironmentObject private var library: LocalLibrary
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance = "dark"
    @AppStorage("autoplay") private var autoplay = false
    @AppStorage("remoteFallback") private var remoteFallback = true
    @State private var login = false
    @State private var confirmLogout = false
    @State private var confirmClear = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        Image(systemName: "play.rectangle.fill").font(.system(size: 40)).foregroundStyle(Palette.mint)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("luma").font(.system(.title, design: .rounded).bold())
                            Text("Ein schönerer Platz für deine Videos.").font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 8)
                }
                Section("Dein Konto") {
                    if let name = service.accountName { Label(name, systemImage: "person.crop.circle") }
                    if service.sessionNeedsRenewal { Text("Die Sitzung muss erneut verbunden werden.").foregroundStyle(.orange) }
                    Button(service.signedIn ? "Sitzung erneuern" : "YouTube-Konto verbinden") { login = true }
                        .accessibilityIdentifier("connectAccountButton")
                    if service.accountName != nil || service.sessionNeedsRenewal { Button("Abmelden", role: .destructive) { confirmLogout = true } }
                }
                Section("Dein Look") {
                    Picker("Erscheinungsbild", selection: $appearance) {
                        Text("Dunkel").tag("dark"); Text("Hell").tag("light"); Text("Wie iOS").tag("system")
                    }
                    Text("Liquid Glass passt sich deinem Hintergrund an. Die iOS-Einstellungen für reduzierte Transparenz werden berücksichtigt.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Wiedergabe") {
                    Toggle("Warteschlange automatisch abspielen", isOn: $autoplay)
                    Toggle("Alternative Stream-Hilfe", isOn: $remoteFallback)
                    Text("Falls die lokale Stream-Erkennung scheitert, hilft der öffentliche YouTubeKit-Server. Dabei werden Video-ID und öffentliche YouTube-Antworten verarbeitet. Deine Konto-Cookies werden nicht weitergegeben.").font(.caption).foregroundStyle(.secondary)
                    Text("Luma spielt verfügbare Videostreams direkt, ohne eigene Werbeeinblendungen. Eingebaute Sponsoren bleiben Teil des Videos. Manche Live-, Alters-, Mitglieder- oder Kaufvideos können nicht abgespielt werden.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Auf diesem Gerät") {
                    LabeledContent("Gemerkte Videos", value: "\(library.saved.count)")
                    LabeledContent("Verlauf", value: "\(library.history.count) Videos")
                    Button("Lokalen Wiedergabeverlauf löschen", role: .destructive) { confirmClear = true }
                    Text("Die lokale Merkliste und der Wiedergabefortschritt werden auf diesem Gerät gespeichert. Sie werden nicht automatisch mit deinem YouTube-Konto synchronisiert.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Über Luma") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                    Link("Quellcode", destination: URL(string: "https://github.com/Robin9094707/YTIOS")!)
                    NavigationLink("Open-Source-Lizenzen") {
                        ScrollView { Text(notices).font(.caption).textSelection(.enabled).padding(20) }.navigationTitle("Lizenzen")
                    }
                    Text("Privater, unabhängiger Client. Luma ist keine offizielle YouTube-App und nicht mit Google verbunden.").font(.caption).foregroundStyle(.secondary)
                }
            }.scrollContentBackground(.hidden).background(AmbientBackground()).navigationTitle("Dein Luma")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fertig") { dismiss() } } }
                .sheet(isPresented: $login) { LoginSheet() }
                .confirmationDialog("YouTube-Konto auf diesem Gerät abmelden?", isPresented: $confirmLogout, titleVisibility: .visible) {
                    Button("Abmelden", role: .destructive) { service.signOut() }
                }
                .confirmationDialog("Lokalen Wiedergabeverlauf löschen?", isPresented: $confirmClear, titleVisibility: .visible) {
                    Button("Verlauf löschen", role: .destructive) { library.clearHistory() }
                }
        }
    }
    private var notices: String {
        guard let url = Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt") else { return "YouTubeKit — MIT-Lizenz" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? "YouTubeKit — MIT-Lizenz"
    }
}
