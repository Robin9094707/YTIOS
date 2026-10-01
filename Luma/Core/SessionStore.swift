import Foundation
import Security
import Combine

enum SecureSession {
    private static let service = "de.robin9094707.YTIOS.session"
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "youtube"]
    }
    static func read() -> String? {
        var q = query
        q[kSecReturnData as String] = true
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func write(_ value: String) throws {
        let data = Data(value.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query
            q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(q as CFDictionary, nil)
            guard added == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(added)) }
        } else if status != errSecSuccess { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
    static func delete() { SecItemDelete(query as CFDictionary) }
}

struct WatchEntry: Codable, Identifiable {
    var id: String { video.id }
    var video: Video
    var seconds: Double
    var duration: Double
    var updated: Date
}

@MainActor
final class LocalLibrary: ObservableObject {
    @Published private(set) var saved: [Video] = []
    @Published private(set) var history: [WatchEntry] = []
    @Published var persistenceError: String?
    private let file: URL?
    private struct Contents: Codable { var saved: [Video]; var history: [WatchEntry] }

    init(inMemory: Bool = false) {
        file = inMemory ? nil : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("LumaLibrary.json")
        if let file, FileManager.default.fileExists(atPath: file.path) {
            do {
                let stored = try JSONDecoder().decode(Contents.self, from: Data(contentsOf: file))
                saved = stored.saved; history = stored.history
            } catch { persistenceError = "Die lokale Mediathek konnte nicht geladen werden. Deine Datei wurde nicht überschrieben." }
        }
    }
    func contains(_ video: Video) -> Bool { saved.contains { $0.id == video.id } }
    func toggle(_ video: Video) {
        if contains(video) { saved.removeAll { $0.id == video.id } }
        else { saved.insert(video, at: 0) }
        persist()
    }
    func record(_ video: Video, seconds: Double, duration: Double) {
        guard seconds.isFinite, duration.isFinite, seconds >= 0, duration >= 0 else { return }
        history.removeAll { $0.video.id == video.id }
        history.insert(WatchEntry(video: video, seconds: seconds, duration: duration, updated: Date()), at: 0)
        history = Array(history.prefix(300))
        persist()
    }
    func progress(for video: Video) -> Double { history.first { $0.video.id == video.id }?.seconds ?? 0 }
    func clearHistory() { history = []; persist() }
    private func persist() {
        guard let file, persistenceError == nil else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(Contents(saved: saved, history: history)).write(to: file, options: [.atomic, .completeFileProtectionUnlessOpen])
        } catch { persistenceError = "Deine Mediathek konnte nicht gespeichert werden: \(error.localizedDescription)" }
    }
}
