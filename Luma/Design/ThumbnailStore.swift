import Foundation
import UIKit
import ImageIO

/// Reuse decoded thumbnails during scrolling rather than downloading and
/// decoding the same image for each newly visible card.
actor ThumbnailStore {
    static let shared = ThumbnailStore()
    private let cache = NSCache<NSURL, UIImage>()
    private var pending: [URL: Task<UIImage?, Never>] = [:]
    private let session: URLSession
    init() {
        cache.countLimit = 120
        cache.totalCostLimit = 40 * 1024 * 1024
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 10
        session = URLSession(configuration: configuration)
    }
    func image(for url: URL) async -> UIImage? {
        guard url.scheme == "https" else { return nil }
        if let image = cache.object(forKey: url as NSURL) { return image }
        if let task = pending[url] { return await task.value }
        let task = Task<UIImage?, Never> { [session] in
            guard let (data, response) = try? await session.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200, data.count < 8 * 1024 * 1024,
                  let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let bitmap = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 960,
                    kCGImageSourceCreateThumbnailWithTransform: true
                  ] as CFDictionary) else { return nil }
            return UIImage(cgImage: bitmap)
        }
        pending[url] = task
        let image = await task.value
        pending[url] = nil
        if let image { cache.setObject(image, forKey: url as NSURL, cost: (image.cgImage?.bytesPerRow ?? 0) * (image.cgImage?.height ?? 0)) }
        return image
    }
}
