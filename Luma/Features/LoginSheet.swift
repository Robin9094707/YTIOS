import SwiftUI
import WebKit
import UniformTypeIdentifiers

@MainActor
final class LoginCoordinator: NSObject, ObservableObject, WKNavigationDelegate, WKHTTPCookieStoreObserver {
    @Published var loading = false
    @Published var message = "Melde dich direkt bei Google an. Luma speichert kein Passwort."
    @Published var error: String?
    private(set) var webView: WKWebView!
    private weak var service: YouTubeService?
    private var verifying = false
    private var lastAttempt: String?
    private var cancelled = false

    init(service: YouTubeService) {
        self.service = service
        super.init()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        configuration.websiteDataStore.httpCookieStore.add(self)
        var url = URLComponents(string: "https://accounts.google.com/ServiceLogin")!
        url.queryItems = [URLQueryItem(name: "service", value: "youtube"), URLQueryItem(name: "continue", value: "https://www.youtube.com/signin?action_handle_signin=true&next=%2F")]
        webView.load(URLRequest(url: url.url!))
    }
    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) { Task { await capture() } }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { loading = true }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loading = false
        if let host = webView.url?.host, CookieParser.isYouTubeDomain(host) { Task { await capture() } }
        else if webView.url?.host == "myaccount.google.com" { webView.load(URLRequest(url: URL(string: "https://www.youtube.com/")!)) }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loading = false
        if (error as NSError).code != NSURLErrorCancelled { self.error = "Die Anmeldeseite konnte nicht geladen werden. Nutze bei Bedarf den Sitzungsimport." }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, url.scheme == "https", let host = url.host?.lowercased(),
              host == "google.com" || host.hasSuffix(".google.com") || CookieParser.isYouTubeDomain(host) else {
            decisionHandler(.cancel); return
        }
        decisionHandler(.allow)
    }
    func capture(force: Bool = false) async {
        guard !verifying, !cancelled, let service, !service.signedIn else { return }
        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        let scoped = cookies.filter { CookieParser.isYouTubeDomain($0.domain) && (!$0.isSecure || $0.domain.contains("youtube.com")) }
        // Prefer the root cookie when a subdomain has an older duplicate.
        var values: [String: String] = [:]
        for cookie in scoped.sorted(by: { $0.domain.count > $1.domain.count }) { values[cookie.name] = cookie.value }
        let raw = values.keys.sorted().map { "\($0)=\(values[$0]!)" }.joined(separator: "; ")
        guard let header = try? CookieParser.header(from: raw) else {
            if force { error = "Noch keine YouTube-Sitzung gefunden. Schließe die Google-Anmeldung ab oder importiere deine Sitzung." }
            return
        }
        guard force || header != lastAttempt else { return }
        lastAttempt = header; verifying = true; message = "Dein Konto wird bei YouTube geprüft …"
        defer { verifying = false }
        do {
            guard !cancelled else { return }
            try await service.signIn(header: header)
            error = nil; message = "Konto erfolgreich verbunden."
        } catch { self.error = "YouTube hat diese Sitzung noch nicht bestätigt. Du kannst die Anmeldung erneut prüfen oder eine bestehende Sitzung importieren." }
    }
    func close() {
        cancelled = true; webView.stopLoading()
        webView.configuration.websiteDataStore.httpCookieStore.remove(self)
    }
}

struct LoginWebView: UIViewRepresentable {
    let coordinator: LoginCoordinator
    func makeUIView(context: Context) -> WKWebView { coordinator.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) { }
}

struct LoginBrowserPanel: View {
    @StateObject private var coordinator: LoginCoordinator
    init(service: YouTubeService) { _coordinator = StateObject(wrappedValue: LoginCoordinator(service: service)) }
    var body: some View {
        VStack(spacing: 10) {
            if coordinator.loading { ProgressView().frame(maxWidth: .infinity) }
            Text(coordinator.message).font(.caption).foregroundStyle(.secondary)
            if let error = coordinator.error { Text(error).font(.caption).foregroundStyle(.orange) }
            LoginWebView(coordinator: coordinator).clipShape(RoundedRectangle(cornerRadius: 18))
            HStack {
                Button("Zurück", systemImage: "chevron.left") { coordinator.webView.goBack() }.buttonStyle(.glass)
                Spacer()
                Button("Anmeldung prüfen") { Task { await coordinator.capture(force: true) } }.buttonStyle(.glassProminent)
            }
        }.onDisappear { coordinator.close() }
    }
}

struct LoginSheet: View {
    @EnvironmentObject private var service: YouTubeService
    @Environment(\.dismiss) private var dismiss
    @State private var mode = 0
    @State private var cookieText = ""
    @State private var importer = false
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Dein Konto.\nDeine Lieblingsvideos.").font(.system(.title, design: .rounded).bold())
                Picker("Verbindung", selection: $mode) {
                    Text("Anmelden").tag(0); Text("Sitzung importieren").tag(1)
                }.pickerStyle(.segmented)
                if mode == 0 {
                    Text("Falls Google die Anmeldung in der App blockiert, wechsle zu „Sitzung importieren“.").font(.caption).foregroundStyle(.secondary)
                    LoginBrowserPanel(service: service)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Importiere eine bestehende Anmeldung mit YouTube-Cookies. Es sind keine API-Schlüssel erforderlich.").font(.subheadline).foregroundStyle(.secondary)
                            Text("1. Melde dich auf deinem Computer bei youtube.com an.\n2. Exportiere die YouTube-Cookies im Netscape-Format.\n3. Öffne die Datei hier oder füge einen Cookie-Header ein.")
                                .font(.subheadline).textSelection(.enabled)
                            Text("Cookies gewähren Zugriff auf dein Konto. Luma speichert sie ausschließlich im Schlüsselbund dieses Geräts und sendet sie nur an YouTube.")
                                .font(.caption).foregroundStyle(.secondary)
                            Button("Cookie-Datei auswählen", systemImage: "doc.badge.arrow.up") { importer = true }.buttonStyle(.glass)
                            TextEditor(text: $cookieText).frame(minHeight: 150).font(.system(.caption, design: .monospaced))
                                .scrollContentBackground(.hidden).padding(10).lumaCard(corner: 18)
                                .autocorrectionDisabled().textInputAutocapitalization(.never).privacySensitive()
                                .accessibilityLabel("YouTube-Cookies")
                            Button { Task { await importSession() } } label: {
                                HStack { if busy { ProgressView() }; Text("Sitzung prüfen und verbinden") }.frame(maxWidth: .infinity).padding(7)
                            }.buttonStyle(.glassProminent).disabled(busy || cookieText.isEmpty)
                            if let error { Text(error).font(.subheadline).foregroundStyle(.orange) }
                        }
                    }
                }
            }.padding(20).background(AmbientBackground())
                .navigationTitle("YouTube verbinden").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fertig") { dismiss() }.disabled(busy) } }
                .fileImporter(isPresented: $importer, allowedContentTypes: [.plainText, .text, .data]) { result in
                    do {
                        let url = try result.get(); let access = url.startAccessingSecurityScopedResource()
                        defer { if access { url.stopAccessingSecurityScopedResource() } }
                        let values = try url.resourceValues(forKeys: [.fileSizeKey])
                        guard (values.fileSize ?? 0) < 1_000_000 else { throw AppFailure.invalidCookies }
                        cookieText = try String(contentsOf: url, encoding: .utf8)
                    } catch { self.error = error.localizedDescription }
                }
                .onChange(of: service.signedIn) { _, connected in if connected { cookieText = ""; dismiss() } }
        }
    }
    private func importSession() async {
        busy = true; error = nil; defer { busy = false }
        do {
            let header = try CookieParser.header(from: cookieText)
            try await service.signIn(header: header); cookieText = ""; dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
