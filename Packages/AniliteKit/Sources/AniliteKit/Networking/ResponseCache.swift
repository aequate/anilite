import Foundation

/// Two-tier cache for raw GraphQL response bodies: a small in-memory LRU plus files on disk.
/// Entries remember when they were stored so callers can decide between fresh and stale.
public actor ResponseCache {
    public struct Entry: Sendable {
        public let data: Data
        public let storedAt: Date
        public func age(at now: Date) -> TimeInterval { now.timeIntervalSince(storedAt) }
    }

    private var memory: [String: Entry] = [:]
    private var order: [String] = []
    private let memoryLimit: Int
    private let directory: URL?
    private let diskLimitBytes: Int
    private let clock: AppClock

    /// - Parameter directory: nil keeps the cache memory-only (used in tests and previews).
    public init(directory: URL?, memoryLimit: Int = 64, diskLimitBytes: Int = 60 * 1_024 * 1_024, clock: AppClock = .live) {
        self.directory = directory
        self.memoryLimit = memoryLimit
        self.diskLimitBytes = diskLimitBytes
        self.clock = clock
        if let directory {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("AniliteResponses", isDirectory: true)
    }

    public func entry(for key: String) -> Entry? {
        if let hit = memory[key] {
            touch(key)
            return hit
        }
        guard let url = fileURL(for: key),
              let data = try? Data(contentsOf: url),
              data.count > 8 else { return nil }
        // First 8 bytes: storage timestamp (big-endian milliseconds since 1970).
        let header = data.prefix(8)
        let millis = header.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        let entry = Entry(data: Data(data.dropFirst(8)), storedAt: Date(timeIntervalSince1970: TimeInterval(millis) / 1000))
        insertMemory(key, entry)
        return entry
    }

    public func store(_ data: Data, for key: String) {
        let entry = Entry(data: data, storedAt: clock.now())
        insertMemory(key, entry)
        guard let url = fileURL(for: key) else { return }
        var millis = UInt64(max(0, entry.storedAt.timeIntervalSince1970 * 1000))
        var header = [UInt8](repeating: 0, count: 8)
        for i in stride(from: 7, through: 0, by: -1) {
            header[i] = UInt8(millis & 0xff)
            millis >>= 8
        }
        var blob = Data(header)
        blob.append(data)
        try? blob.write(to: url, options: .atomic)
    }

    public func remove(_ key: String) {
        memory[key] = nil
        order.removeAll { $0 == key }
        if let url = fileURL(for: key) { try? FileManager.default.removeItem(at: url) }
    }

    public func removeAll() {
        memory.removeAll()
        order.removeAll()
        guard let directory else { return }
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files { try? FileManager.default.removeItem(at: file) }
    }

    /// Deletes the oldest files once the disk cache grows past its budget.
    public func prune() {
        guard let directory else { return }
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys) else { return }
        var items: [(url: URL, size: Int, date: Date)] = files.compactMap { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            return (url, values?.fileSize ?? 0, values?.contentModificationDate ?? .distantPast)
        }
        var total = items.reduce(0) { $0 + $1.size }
        guard total > diskLimitBytes else { return }
        items.sort { $0.date < $1.date }
        for item in items where total > diskLimitBytes {
            try? FileManager.default.removeItem(at: item.url)
            total -= item.size
        }
    }

    public var diskUsageBytes: Int {
        guard let directory,
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    private func fileURL(for key: String) -> URL? {
        directory?.appendingPathComponent(key + ".bin")
    }

    private func insertMemory(_ key: String, _ entry: Entry) {
        memory[key] = entry
        touch(key)
        while order.count > memoryLimit {
            let evicted = order.removeFirst()
            memory[evicted] = nil
        }
    }

    private func touch(_ key: String) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}
