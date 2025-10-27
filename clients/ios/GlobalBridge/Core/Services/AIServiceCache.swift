//
//  AIServiceCache.swift
//  GlobalBridge
//
//  Intelligent caching layer for AI service responses with multi-tier storage
//  - Memory cache: NSCache for fast in-memory access
//  - Disk cache: FileManager for persistent storage across sessions
//  - TTL-based expiry with automatic cleanup
//  - Cache hit rate metrics for performance monitoring
//

 //import Foundation
import Combine
import UIKit
@preconcurrency import ObjectiveC

/// Multi-tier caching system for AI service responses
@MainActor
final class AIServiceCache {

    // MARK: - Singleton

    static let shared = AIServiceCache()

    // MARK: - Properties

    /// In-memory cache for fast access (LRU eviction via NSCache)
    private let memoryCache = NSCache<NSString, CachedItem>()

    /// File manager for disk operations
    private let fileManager = FileManager.default

    /// Disk cache directory
    private let diskCacheDirectory: URL

    /// Cache configuration
    private let config: CacheConfiguration

    /// Metrics tracking
    private var metrics = CacheMetrics()

    /// Memory warning observer - nonisolated to allow access from deinit
    nonisolated(unsafe) private var memoryWarningObserver: NSObjectProtocol?

    // MARK: - Configuration

    struct CacheConfiguration {
        let memoryCacheSizeMB: Int
        let diskCacheSizeMB: Int
        let defaultTTLSeconds: TimeInterval

        static let `default` = CacheConfiguration(
            memoryCacheSizeMB: 20,      // 20MB memory cache
            diskCacheSizeMB: 50,        // 50MB disk cache (as per requirements)
            defaultTTLSeconds: 3600     // 1 hour default TTL
        )
    }

    // MARK: - Cache Types

    enum CacheType: String {
        case translation = "translations"
        case summary = "summaries"
        case search = "search"
        case tasks = "tasks"

        var ttl: TimeInterval {
            switch self {
            case .translation:
                return 86400  // 24 hours (translations are stable)
            case .summary:
                return 3600   // 1 hour (summaries change with new messages)
            case .search:
                return 1800   // 30 minutes (search results can change)
            case .tasks:
                return 7200   // 2 hours (tasks are relatively stable)
            }
        }
    }

    // MARK: - Initialization

    private init(config: CacheConfiguration = .default) {
        self.config = config

        // Setup disk cache directory
        let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.diskCacheDirectory = cacheDir.appendingPathComponent("AIServiceCache", isDirectory: true)

        // Configure memory cache
        memoryCache.totalCostLimit = config.memoryCacheSizeMB * 1024 * 1024 // Convert to bytes
        memoryCache.name = "com.globalbridge.aiservice.memory"

        // Create disk cache directory if needed
        try? fileManager.createDirectory(at: diskCacheDirectory, withIntermediateDirectories: true)

        // Setup memory warning observer
        setupMemoryWarningObserver()

        // Cleanup expired items on init
        Task {
            await cleanupExpiredItems()
        }

        print("✅ [AI_CACHE] Initialized with \(config.memoryCacheSizeMB)MB memory, \(config.diskCacheSizeMB)MB disk")
    }

    deinit {
        // deinit is nonisolated; safely remove observer
        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Public Interface

    /// Store an item in cache
    func store<T: Codable>(_ item: T, forKey key: String, type: CacheType) async {
        let cacheKey = cacheKey(forKey: key, type: type)
        let expiresAt = Date().addingTimeInterval(type.ttl)

        let cachedItem = CachedItem(
            data: item,
            expiresAt: expiresAt,
            type: type.rawValue
        )

        // Store in memory
        memoryCache.setObject(cachedItem, forKey: cacheKey as NSString)

        // Store on disk asynchronously
        await storeToDisk(cachedItem, forKey: cacheKey)

        print("💾 [AI_CACHE] Stored \(type.rawValue) - key: \(key)")
    }

    /// Retrieve an item from cache
    func retrieve<T: Codable>(forKey key: String, type: CacheType) async -> T? {
        let cacheKey = cacheKey(forKey: key, type: type)

        // Check memory cache first
        if let cachedItem = memoryCache.object(forKey: cacheKey as NSString) {
            metrics.recordHit(inMemory: true)

            // Check if expired
            if cachedItem.isExpired {
                print("⏰ [AI_CACHE] Expired in memory - key: \(key)")
                remove(forKey: key, type: type)
                metrics.recordMiss()
                return nil
            }

            print("✅ [AI_CACHE] Hit (memory) - key: \(key)")
            return cachedItem.data as? T
        }

        // Check disk cache
        if let cachedItem = await retrieveFromDisk(forKey: cacheKey, as: CachedItem.self) {
            metrics.recordHit(inMemory: false)

            // Check if expired
            if cachedItem.isExpired {
                print("⏰ [AI_CACHE] Expired on disk - key: \(key)")
                await removeFromDisk(forKey: cacheKey)
                metrics.recordMiss()
                return nil
            }

            // Populate memory cache
            memoryCache.setObject(cachedItem, forKey: cacheKey as NSString)

            print("✅ [AI_CACHE] Hit (disk) - key: \(key)")
            return cachedItem.data as? T
        }

        // Cache miss
        metrics.recordMiss()
        print("❌ [AI_CACHE] Miss - key: \(key)")
        return nil
    }

    /// Remove an item from cache
    func remove(forKey key: String, type: CacheType) {
        let cacheKey = cacheKey(forKey: key, type: type)
        memoryCache.removeObject(forKey: cacheKey as NSString)

        Task {
            await removeFromDisk(forKey: cacheKey)
        }

        print("🗑️ [AI_CACHE] Removed - key: \(key)")
    }

    /// Clear all caches
    func clearAll() async {
        memoryCache.removeAllObjects()

        try? fileManager.removeItem(at: diskCacheDirectory)
        try? fileManager.createDirectory(at: diskCacheDirectory, withIntermediateDirectories: true)

        metrics.reset()

        print("🗑️ [AI_CACHE] Cleared all caches")
    }

    /// Clear cache for specific type
    func clear(type: CacheType) async {
        let typeDirectory = diskCacheDirectory.appendingPathComponent(type.rawValue)
        try? fileManager.removeItem(at: typeDirectory)

        print("🗑️ [AI_CACHE] Cleared \(type.rawValue) cache")
    }

    /// Get cache metrics
    func getMetrics() -> CacheMetrics {
        return metrics
    }

    /// Get disk cache size in bytes
    func getDiskCacheSize() -> Int64 {
        var totalSize: Int64 = 0

        guard let enumerator = fileManager.enumerator(at: diskCacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }

        for case let fileURL as URL in enumerator {
            guard let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
                continue
            }
            totalSize += Int64(fileSize)
        }

        return totalSize
    }

    // MARK: - Private Methods

    private func cacheKey(forKey key: String, type: CacheType) -> String {
        // Hash the key to create a safe filename and prevent collisions
        let hash = key.data(using: .utf8)?.base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "") ?? key

        return "\(type.rawValue)_\(hash)"
    }

    private func diskURL(forKey key: String) -> URL {
        // Extract type from key prefix
        let components = key.components(separatedBy: "_")
        let typeDir = components.first ?? "unknown"

        let typeDirectory = diskCacheDirectory.appendingPathComponent(typeDir)
        try? fileManager.createDirectory(at: typeDirectory, withIntermediateDirectories: true)

        return typeDirectory.appendingPathComponent(key)
    }

    private func storeToDisk(_ item: CachedItem, forKey key: String) async {
        let url = diskURL(forKey: key)

        do {
            let data = try JSONEncoder().encode(item)
            try data.write(to: url, options: .atomic)

            // Check disk cache size and cleanup if needed
            await enforceDiskCacheLimit()
        } catch {
            print("❌ [AI_CACHE] Failed to store to disk: \(error)")
        }
    }

    private func retrieveFromDisk<T: Codable>(forKey key: String, as type: T.Type) async -> T? {
        let url = diskURL(forKey: key)

        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            let item = try JSONDecoder().decode(T.self, from: data)
            return item
        } catch {
            print("❌ [AI_CACHE] Failed to retrieve from disk: \(error)")
            return nil
        }
    }

    private func removeFromDisk(forKey key: String) async {
        let url = diskURL(forKey: key)
        try? fileManager.removeItem(at: url)
    }

    private func cleanupExpiredItems() async {
        guard let enumerator = fileManager.enumerator(at: diskCacheDirectory, includingPropertiesForKeys: nil) else {
            return
        }

        // Use allObjects to avoid makeIterator() issues in async context
        let fileURLs = enumerator.allObjects.compactMap { $0 as? URL }

        var removedCount = 0

        for fileURL in fileURLs {
            guard let data = try? Data(contentsOf: fileURL),
                  let cachedItem = try? JSONDecoder().decode(CachedItem.self, from: data) else {
                continue
            }

            if cachedItem.isExpired {
                try? fileManager.removeItem(at: fileURL)
                removedCount += 1
            }
        }

        if removedCount > 0 {
            print("🧹 [AI_CACHE] Cleaned up \(removedCount) expired items")
        }
    }

    private func enforceDiskCacheLimit() async {
        let currentSize = getDiskCacheSize()
        let limitBytes = Int64(config.diskCacheSizeMB) * 1024 * 1024

        guard currentSize > limitBytes else {
            return
        }

        print("⚠️ [AI_CACHE] Disk cache exceeds limit: \(currentSize) > \(limitBytes)")

        // Get all files sorted by modification date (oldest first)
        guard let enumerator = fileManager.enumerator(
            at: diskCacheDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else {
            return
        }

        // Use allObjects to avoid makeIterator() issues in async context
        let fileURLs = enumerator.allObjects.compactMap { $0 as? URL }

        var files: [(url: URL, date: Date)] = []
        for fileURL in fileURLs {
            guard let date = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else {
                continue
            }
            files.append((url: fileURL, date: date))
        }

        // Sort by date (oldest first)
        files.sort { $0.date < $1.date }

        // Remove oldest files until under limit
        var deletedSize: Int64 = 0
        var deletedCount = 0

        for file in files {
            guard currentSize - deletedSize > limitBytes else {
                break
            }

            if let fileSize = try? file.url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                try? fileManager.removeItem(at: file.url)
                deletedSize += Int64(fileSize)
                deletedCount += 1
            }
        }

        print("🧹 [AI_CACHE] Removed \(deletedCount) files (\(deletedSize) bytes) to enforce limit")
    }

    private func setupMemoryWarningObserver() {
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("⚠️ [AI_CACHE] Memory warning - clearing memory cache")
            Task { @MainActor in
                self?.memoryCache.removeAllObjects()
            }
        }
    }
}

// MARK: - Supporting Types

/// Wrapper for cached items with metadata
private class CachedItem: NSObject, Codable {
    let data: Any
    let expiresAt: Date
    let type: String
    let cachedAt: Date

    var isExpired: Bool {
        return Date() > expiresAt
    }

    init(data: Any, expiresAt: Date, type: String) {
        self.data = data
        self.expiresAt = expiresAt
        self.type = type
        self.cachedAt = Date()
    }

    enum CodingKeys: String, CodingKey {
        case data, expiresAt, type, cachedAt
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.expiresAt = try container.decode(Date.self, forKey: .expiresAt)
        self.type = try container.decode(String.self, forKey: .type)
        self.cachedAt = try container.decode(Date.self, forKey: .cachedAt)

        // Decode data as JSON
        let jsonData = try container.decode(Data.self, forKey: .data)
        self.data = try JSONSerialization.jsonObject(with: jsonData)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(expiresAt, forKey: .expiresAt)
        try container.encode(type, forKey: .type)
        try container.encode(cachedAt, forKey: .cachedAt)

        // Encode data as JSON - handle both Codable types and raw JSON objects
        let jsonData: Data

        // Try to encode as Codable first (for EnhancedTranslationResult, etc.)
        if let codableData = data as? (any Codable) {
            // Use a type-erasing helper to encode
            jsonData = try encodeAnyCodable(codableData)
        } else {
            // For raw JSON objects (Dictionary, Array), use JSONSerialization
            jsonData = try JSONSerialization.data(withJSONObject: data)
        }
        try container.encode(jsonData, forKey: .data)
    }

    // Helper to encode any Codable type
    private func encodeAnyCodable(_ value: any Codable) throws -> Data {
        // Use a type-erasing encoder
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        // Try to mirror and encode based on actual type
        let mirror = Mirror(reflecting: value)
        if let displayStyle = mirror.displayStyle, displayStyle == .struct || displayStyle == .class {
            // For structs/classes, we need to use type-specific encoding
            // We'll encode to JSON then back to Data
            return try encoder.encode(AnyEncodable(value))
        } else {
            return try JSONSerialization.data(withJSONObject: value)
        }
    }
}

// Type-erasing wrapper for Codable
private struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void

    init<T: Encodable>(_ value: T) {
        _encode = { encoder in
            try value.encode(to: encoder)
        }
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}

/// Cache performance metrics
struct CacheMetrics {
    private(set) var memoryHits: Int = 0
    private(set) var diskHits: Int = 0
    private(set) var misses: Int = 0

    var totalHits: Int {
        return memoryHits + diskHits
    }

    var totalRequests: Int {
        return totalHits + misses
    }

    var hitRate: Double {
        guard totalRequests > 0 else { return 0.0 }
        return Double(totalHits) / Double(totalRequests)
    }

    var memoryHitRate: Double {
        guard totalRequests > 0 else { return 0.0 }
        return Double(memoryHits) / Double(totalRequests)
    }

    mutating func recordHit(inMemory: Bool) {
        if inMemory {
            memoryHits += 1
        } else {
            diskHits += 1
        }
    }

    mutating func recordMiss() {
        misses += 1
    }

    mutating func reset() {
        memoryHits = 0
        diskHits = 0
        misses = 0
    }
}
