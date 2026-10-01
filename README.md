# YTIOS · Luma

Ein unabhängiger, nativer YouTube-Client für iPhone und iPad mit **echtem iOS 26 Liquid Glass**. Ruhige dunkle Flächen, große Videokarten, violette und türkise Akzente und eine schwebende Systemnavigation. Kein Nachbau der klassischen YouTube-Oberfläche.

## Funktionen

- Entdecken und Suche nach Videos, Kanälen und Playlists; YouTube-Links und Shorts-Links direkt öffnen.
- Angemeldeter Home- und Abo-Feed, Kanalansichten, Abonnieren/Abmelden, Likes, Playlists erstellen und Videos hinzufügen.
- „Später ansehen“, „Gefällt mir“ und YouTube-Verlauf über die Konto-Sitzung.
- Nativer AVPlayer, Vollbild, AirPlay und Bild-in-Bild über die Systemsteuerung.
- Hintergrundaudio, Sperrbildschirm-Steuerung, Geschwindigkeit, verfügbare Stream-Qualitäten, Untertitel und Kapitel, sofern YouTube sie liefert.
- Kommentare lesen und senden, Empfehlungen, Teilen und sortierbare Warteschlange.
- Lokale Merkliste, Fortsetzen des Wiedergabefortschritts, Sleep-Timer und optionales automatisches Abspielen der Warteschlange.
- Dunkel, hell oder Systemdarstellung; Dynamic Type, VoiceOver und reduzierte Transparenz.

Luma enthält keine eigene Werbung und spielt verfügbare Videostreams direkt. **Eine dauerhaft funktionierende werbefreie Wiedergabe und vollständige Funktionsgleichheit mit YouTube lassen sich nicht garantieren.** YouTube ändert seine nicht öffentlichen Endpunkte häufig. Eingebaute Sponsorsegmente gehören zum Video und werden nicht automatisch entfernt. Mitglieder-, Kauf-, Alters- und bestimmte Live-Inhalte können eingeschränkt sein. Uploads, Studio, Live-Chat, Käufe und Offline-Downloads sind in dieser Version nicht enthalten. Die lokale Merkliste und der Wiedergabefortschritt werden nicht automatisch zum YouTube-Konto hochgeladen.

## Konto verbinden

Öffne **Einstellungen → YouTube-Konto verbinden**.

1. **Anmelden:** Die App lädt die echte Google-Anmeldeseite in einer isolierten WebView. Das Passwort wird nicht durch Luma gelesen oder gespeichert. Die Sitzung wird erst gespeichert, wenn YouTube eine authentifizierte Kontoantwort liefert.
2. **Sitzung importieren:** Google kann Anmeldungen in eingebetteten WebViews blockieren. Als unabhängige Alternative exportiere auf deinem eigenen Computer die Cookies einer bestehenden youtube.com-Anmeldung im Netscape-Format. Importiere die Textdatei in Luma. Alternativ akzeptiert die App einen vollständigen `Cookie:`-Header. Die App prüft die Sitzung gegen YouTube; bloße Cookie-Anwesenheit reicht nicht aus.

Cookies sind Kontozugangsdaten. Teile sie mit niemandem, lade sie niemals ins Repository und lösche die Exportdatei anschließend. Die App filtert Netscape-Exporte auf YouTube-Domains und ignoriert abgelaufene Cookies. Der Header wird ausschließlich im iOS-Schlüsselbund mit `AfterFirstUnlockThisDeviceOnly` gespeichert. Abmelden löscht ihn. Für den eingebetteten Login wird ein nicht persistenter WebView-Speicher verwendet. Luma sendet Sitzungs-Cookies ausschließlich an YouTube, nicht an den optionalen Stream-Hilfsserver.

**Keine API-Schlüssel und kein OAuth-Client eines anderen Projekts sind eingebaut.** Ein Google-OAuth-Login über den System-Authentifizierungsdialog ist in dieser Version nicht vorhanden. Ein erfolgreicher CI-Build bestätigt weder deinen individuellen Konto-Login noch die Abspielbarkeit jedes Videos; diese Schritte müssen auf einem echten Gerät mit deinem Konto geprüft werden.

## IPA und GitHub Actions

[Build-Workflow](https://github.com/Robin9094707/YTIOS/actions/workflows/ios.yml)

Bei jedem Push auf `main` sowie manuell unter **Actions → Build Luma IPA → Run workflow**:

1. macOS 26 mit Xcode und XcodeGen verwenden.
2. Exakt gepinnte Open-Source-Abhängigkeiten vorbereiten und den App-Icon-Katalog generieren.
3. Unit-Tests zu Links, Cookie-Import, Domain-/Header-Prüfung, Fortschritt und Duplikaten sowie eine echte anonyme YouTube-Suche ausführen.
4. Die native Navigation im iPhone-Simulator testen und fünf Design-Screenshots erzeugen.
5. Ein echtes **arm64-Gerätearchiv** erstellen und als IPA mit `Payload/Luma.app` verpacken.
6. ZIP-Integrität, Bundle-ID und ausführbare Datei kontrollieren; SHA-256 erzeugen.
7. **Luma-IPA** und **Luma-Verification** als Actions-Artefakte bereitstellen.

Die erzeugte IPA ist **unsigniert**. Sie kann mit einem eigenen Sideloading-Werkzeug und Apple-Account signiert werden. Sie ist kein automatisch installierbarer App-Store-/TestFlight-Build. Es sind keine Zertifikate, Provisioning-Profile oder privaten Schlüssel erforderlich, um den CI-Build auszuführen.

### Lokal auf einem Mac bauen

```sh
brew install xcodegen
python3 scripts/prepare.py
xcodegen generate
open Luma.xcodeproj
```

Für eine Geräteinstallation in Xcode unter Signing die eigene Team-ID wählen und `CODE_SIGNING_ALLOWED` auf `YES` setzen. Bundle-ID bei Bedarf an den verwendeten Account anpassen. Die eingecheckte Konfiguration verlangt mindestens iOS 26.

## Architektur und Abhängigkeiten

- `Luma/Design`: Ambiente, native Glass-Flächen, Karten, Platzhalter und Fehlermeldungen.
- `Luma/Features`: Entdecken, Suche, Mediathek, Kontoanmeldung, Kanal, Player und Einstellungen.
- `Luma/Core`: typisierte Domain-Modelle, YouTube-Service, Keychain, lokale Persistenz und ein gemeinsamer Player.
- [b5i/YouTubeKit](https://github.com/b5i/YouTubeKit), MIT, Commit `6532af39da4c1612b0a1af603792419d8fb0e67f`: nicht öffentliche YouTube-Endpunkte für Konto, Suche, Feeds und Aktionen.
- [alexeichhorn/YouTubeKit](https://github.com/alexeichhorn/YouTubeKit), MIT, Commit `e5b7d0396ce12bf3444f0d209e8436c83373b7af`: Stream-Extraktion. Der Build benennt nur dessen Swift-Modul in `LumaStreams` um, da beide Bibliotheken denselben Modulnamen besitzen.
- [Yattee](https://github.com/yattee/yattee): als Architekturvergleich untersucht; kein Yattee-Code übernommen.

Die Stream-Hilfe ist unter Einstellungen deaktivierbar. Falls lokale Extraktion scheitert, verwendet sie den öffentlichen Dienst `remote-production.youtubekit.dev`. Dieser erhält die Video-ID und öffentliche Antwortdaten, keine Luma-Konto-Cookies. Der Build beschränkt servergesteuerte HTTP-Anfragen auf HTTPS und YouTubes öffentliche Infrastruktur, deaktiviert Weiterleitungen sowie Credential-/Cookie-Speicher. Streaming hängt von Region, Video, YouTubes Änderungen und ggf. der Verfügbarkeit dieses Dienstes ab. Adaptive HLS-Streams können höhere Qualitäten liefern; kombinierte MP4-Fallbacks sind auf die tatsächlich verfügbaren Auflösungen begrenzt.

Die CI-Design-Screenshots verwenden deutlich markierte Vorschau-Daten und prüfen die Oberfläche ohne Konto oder YouTube-Netzwerkzugriff. Der normale App-Start verwendet ausschließlich echte API-Antworten und zeigt Fehler statt erfundener Inhalte.

## Quellen

- [Apple: Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)
- [Google: OAuth for native apps](https://developers.google.com/identity/protocols/oauth2/native-app) – eingebettete User-Agents werden für OAuth nicht unterstützt; die Cookie-Session ist ein separater, inoffizieller Ansatz.
- [Google: playlistItems.list](https://developers.google.com/youtube/v3/docs/playlistItems/list) – die öffentliche Data API bietet keine vollständige YouTube-App-Funktionsgleichheit.

Unabhängiges privates Projekt, nicht mit YouTube oder Google verbunden. MIT-Lizenzen der verwendeten Bibliotheken befinden sich unter `licenses/` und in der App.
