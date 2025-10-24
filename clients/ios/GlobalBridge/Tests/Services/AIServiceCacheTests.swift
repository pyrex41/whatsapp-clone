//
//  AIServiceCacheTests.swift
//  GlobalBridgeTests
//
//  Comprehensive test suite for AIServiceCache
//

import XCTest
@testable import GlobalBridge

@MainActor
final class AIServiceCacheTests: XCTestCase {

    var cache: AIServiceCache!

    override func setUp() async throws {
        try await super.setUp()
        cache = AIServiceCache.shared
        await cache.clearAll()
    }

    override func tearDown() async throws {
        await cache.clearAll()
        try await super.tearDown()
    }

    // MARK: - Memory Cache Tests

    func testMemoryCacheStoreAndRetrieve() async throws {
        let testData = TestCacheData(id: "1", value: "test value")

        await cache.store(testData, forKey: "test_key", type: .translation)

        let retrieved: TestCacheData? = await cache.retrieve(forKey: "test_key", type: .translation)

        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.id, testData.id)
        XCTAssertEqual(retrieved?.value, testData.value)
    }

    func testMemoryCacheMiss() async throws {
        let retrieved: TestCacheData? = await cache.retrieve(forKey: "nonexistent_key", type: .translation)
        XCTAssertNil(retrieved)
    }

    func testMemoryCacheRemove() async throws {
        let testData = TestCacheData(id: "1", value: "test value")

        await cache.store(testData, forKey: "test_key", type: .translation)
        cache.remove(forKey: "test_key", type: .translation)

        let retrieved: TestCacheData? = await cache.retrieve(forKey: "test_key", type: .translation)
        XCTAssertNil(retrieved)
    }

    // MARK: - Disk Cache Tests

    func testDiskCachePersistence() async throws {
        let testData = TestCacheData(id: "1", value: "persistent value")

        await cache.store(testData, forKey: "persist_key", type: .translation)

        // Simulate app restart by creating new cache instance
        let newCache = AIServiceCache.shared

        let retrieved: TestCacheData? = await newCache.retrieve(forKey: "persist_key", type: .translation)

        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.id, testData.id)
    }

    // MARK: - Cache Type Tests

    func testDifferentCacheTypes() async throws {
        let translation = TestCacheData(id: "1", value: "translation")
        let summary = TestCacheData(id: "2", value: "summary")
        let search = TestCacheData(id: "3", value: "search")

        await cache.store(translation, forKey: "key", type: .translation)
        await cache.store(summary, forKey: "key", type: .summary)
        await cache.store(search, forKey: "key", type: .search)

        let retrievedTranslation: TestCacheData? = await cache.retrieve(forKey: "key", type: .translation)
        let retrievedSummary: TestCacheData? = await cache.retrieve(forKey: "key", type: .summary)
        let retrievedSearch: TestCacheData? = await cache.retrieve(forKey: "key", type: .search)

        XCTAssertEqual(retrievedTranslation?.value, "translation")
        XCTAssertEqual(retrievedSummary?.value, "summary")
        XCTAssertEqual(retrievedSearch?.value, "search")
    }

    // MARK: - Metrics Tests

    func testCacheHitMetrics() async throws {
        let testData = TestCacheData(id: "1", value: "test")

        await cache.store(testData, forKey: "metrics_key", type: .translation)

        // First retrieve - should be memory hit
        let _: TestCacheData? = await cache.retrieve(forKey: "metrics_key", type: .translation)

        let metrics = cache.getMetrics()
        XCTAssertEqual(metrics.memoryHits, 1)
        XCTAssertEqual(metrics.diskHits, 0)
        XCTAssertEqual(metrics.misses, 0)
    }

    func testCacheMissMetrics() async throws {
        let _: TestCacheData? = await cache.retrieve(forKey: "nonexistent", type: .translation)

        let metrics = cache.getMetrics()
        XCTAssertEqual(metrics.memoryHits, 0)
        XCTAssertEqual(metrics.diskHits, 0)
        XCTAssertEqual(metrics.misses, 1)
    }

    func testCacheHitRate() async throws {
        let testData = TestCacheData(id: "1", value: "test")

        await cache.store(testData, forKey: "hit_rate_key", type: .translation)

        // 3 hits
        let _: TestCacheData? = await cache.retrieve(forKey: "hit_rate_key", type: .translation)
        let _: TestCacheData? = await cache.retrieve(forKey: "hit_rate_key", type: .translation)
        let _: TestCacheData? = await cache.retrieve(forKey: "hit_rate_key", type: .translation)

        // 1 miss
        let _: TestCacheData? = await cache.retrieve(forKey: "nonexistent", type: .translation)

        let metrics = cache.getMetrics()
        XCTAssertEqual(metrics.hitRate, 0.75) // 3 hits out of 4 total requests
    }

    // MARK: - Clear Tests

    func testClearAll() async throws {
        await cache.store(TestCacheData(id: "1", value: "test1"), forKey: "key1", type: .translation)
        await cache.store(TestCacheData(id: "2", value: "test2"), forKey: "key2", type: .summary)

        await cache.clearAll()

        let retrieved1: TestCacheData? = await cache.retrieve(forKey: "key1", type: .translation)
        let retrieved2: TestCacheData? = await cache.retrieve(forKey: "key2", type: .summary)

        XCTAssertNil(retrieved1)
        XCTAssertNil(retrieved2)
    }

    func testClearByType() async throws {
        await cache.store(TestCacheData(id: "1", value: "translation"), forKey: "key", type: .translation)
        await cache.store(TestCacheData(id: "2", value: "summary"), forKey: "key", type: .summary)

        await cache.clear(type: .translation)

        let retrievedTranslation: TestCacheData? = await cache.retrieve(forKey: "key", type: .translation)
        let retrievedSummary: TestCacheData? = await cache.retrieve(forKey: "key", type: .summary)

        XCTAssertNil(retrievedTranslation)
        XCTAssertNotNil(retrievedSummary)
    }

    // MARK: - Disk Size Tests

    func testDiskCacheSize() async throws {
        let largeData = TestCacheData(
            id: "large",
            value: String(repeating: "x", count: 10000)
        )

        await cache.store(largeData, forKey: "large_key", type: .translation)

        let size = cache.getDiskCacheSize()
        XCTAssertGreaterThan(size, 0)
    }
}

// MARK: - Test Data

private struct TestCacheData: Codable {
    let id: String
    let value: String
}
