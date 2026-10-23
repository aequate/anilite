import SwiftUI
import UIKit
import ImageIO
import AniliteKit

/// Loads artwork with a shared disk cache, decodes it downsampled to the size it is shown
/// at (so a 2000px cover never sits in memory for a 120pt card) and extracts palettes.
actor ImagePipeline {
    static let shared = ImagePipeline()

    /// Decoded images. NSCache is thread-safe and evicts under memory pressure.
    nonisolated let memory: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 90 * 1_024 * 1_024
        cache.countLimit = 400
        return cache
    }()

    private let session: URLSession
    private var inflight: [String: Task<UIImage?, Never>] = [:]
    private var palettes: [String: ArtworkPalette] = [:]

    /// Pixel scale used for cache keys. Most iPhones are 3x; 2x devices simply get a
    /// slightly sharper image.
    nonisolated static let scale: CGFloat = 3

    init() {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 8 * 1_024 * 1_024, diskCapacity: 250 * 1_024 * 1_024, diskPath: "anilite-artwork")
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.httpMaximumConnectionsPerHost = 6
        config.timeoutIntervalForRequest = 20
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
    }

    nonisolated static func key(_ url: String, _ points: CGFloat) -> NSString {
        "\(url)#\(Int(points * scale))" as NSString
    }

    /// Synchronous memory-cache lookup so cells can render instantly when scrolling back.
    nonisolated func cached(_ url: String?, points: CGFloat) -> UIImage? {
        guard let url else { return nil }
        return memory.object(forKey: Self.key(url, points))
    }

    func image(for url: String, points: CGFloat) async -> UIImage? {
        let key = Self.key(url, points)
        if let hit = memory.object(forKey: key) { return hit }
        let k = key as String
        if let running = inflight[k] { return await running.value }
        let session = self.session
        let maxPixel = points * Self.scale
        let task = Task<UIImage?, Never>(priority: .userInitiated) {
            guard let u = URL(string: url) else { return nil }
            do {
                let (data, response) = try await session.data(from: u)
                if let http = response as? HTTPURLResponse, http.statusCode >= 400 { return nil }
                return ImagePipeline.downsample(data, maxPixel: maxPixel)
            } catch {
                return nil
            }
        }
        inflight[k] = task
        let result = await task.value
        inflight[k] = nil
        if let result {
            let cost = Int(result.size.width * result.size.height * result.scale * result.scale * 4)
            memory.setObject(result, forKey: key, cost: cost)
        }
        return result
    }

    /// Warms the cache for upcoming rows without blocking.
    nonisolated func prefetch(_ urls: [String], points: CGFloat) {
        for url in urls.prefix(12) {
            Task(priority: .utility) { _ = await self.image(for: url, points: points) }
        }
    }

    /// Palette sampled from the actual artwork, falling back to AniList's cover colour.
    func palette(for url: String?, hint: String?) async -> ArtworkPalette {
        guard let url else { return .from(hex: hint) }
        if let known = palettes[url] { return known }
        guard let image = await image(for: url, points: 80), let cg = image.cgImage else { return .from(hex: hint) }
        let pixels = ImagePipeline.samplePixels(cg, side: 28)
        let palette = pixels.isEmpty ? ArtworkPalette.from(hex: hint) : ArtworkPalette.from(pixels: pixels, hint: hint)
        palettes[url] = palette
        return palette
    }

    nonisolated static func downsample(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixel)
        ] as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return UIImage(cgImage: cg, scale: scale, orientation: .up)
    }

    nonisolated static func samplePixels(_ image: CGImage, side: Int) -> [RGB] {
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        let drawn: Bool = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress,
                  let ctx = CGContext(data: base, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return [] }
        var pixels: [RGB] = []
        pixels.reserveCapacity(side * side)
        for i in stride(from: 0, to: bytes.count, by: 4) where bytes[i + 3] > 200 {
            pixels.append(RGB(r: Double(bytes[i]) / 255, g: Double(bytes[i + 1]) / 255, b: Double(bytes[i + 2]) / 255))
        }
        return pixels
    }

    func clearMemory() {
        memory.removeAllObjects()
        palettes.removeAll()
    }

    func clearDisk() {
        session.configuration.urlCache?.removeAllCachedResponses()
    }

    var diskUsageBytes: Int { session.configuration.urlCache?.currentDiskUsage ?? 0 }
}

/// Artwork view backed by `ImagePipeline`. Shows the title's cover colour while loading
/// and cross-fades the image in.
struct RemoteImage: View {
    var url: String?
    /// Largest side in points the image is displayed at.
    var points: CGFloat
    var placeholder: Color

    @State private var image: UIImage?

    init(_ url: String?, points: CGFloat = 200, placeholder: Color = Theme.ink2) {
        self.url = url
        self.points = points
        self.placeholder = placeholder
        _image = State(initialValue: ImagePipeline.shared.cached(url, points: points))
    }

    var body: some View {
        placeholder
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            .clipped()
            .task(id: url) {
                guard let url else { return }
                if image != nil, ImagePipeline.shared.cached(url, points: points) === image { return }
                let loaded = await ImagePipeline.shared.image(for: url, points: points)
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.22)) { image = loaded }
            }
            .accessibilityHidden(true)
    }
}
