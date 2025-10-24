//
//  FeatureFlagsServiceTests.swift
//  GlobalBridgeTests
//
//  Comprehensive test suite for FeatureFlagsService
//  Tests network operations, API integration, authentication, and error handling
//

import XCTest
@testable import GlobalBridge

@MainActor
final class FeatureFlagsServiceTests: XCTestCase {

    var sut: FeatureFlagsService!
    var mockSession: URLSession!
    var mockAuthManager: MockAuthManager!

    override func setUp() {
        super.setUp()

        // Configure mock URLSession
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        mockSession = URLSession(configuration: config)

        // Create mock auth manager
        mockAuthManager = MockAuthManager()

        // Create service with mocks
        sut = FeatureFlagsService(
            baseURL: URL(string: "http://localhost:4000")!,
            session: mockSession,
            authManager: mockAuthManager
        )
    }

    override func tearDown() {
        sut = nil
        mockSession = nil
        mockAuthManager = nil
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testDefaultBaseURLDebugBuild() {
        // Given/When
        let url = FeatureFlagsService.defaultBaseURL

        // Then
        #if DEBUG
        XCTAssertEqual(url.absoluteString, "http://localhost:4000")
        #else
        XCTAssertEqual(url.absoluteString, "https://globalbridge-backend.fly.dev")
        #endif
    }

    func testServiceInitializationWithDefaults() {
        // Given/When
        let service = FeatureFlagsService()

        // Then
        XCTAssertEqual(service.baseURL, FeatureFlagsService.defaultBaseURL)
    }

    func testServiceInitializationWithCustomURL() {
        // Given
        let customURL = URL(string: "https://custom.backend.com")!

        // When
        let service = FeatureFlagsService(baseURL: customURL)

        // Then
        XCTAssertEqual(service.baseURL, customURL)
    }

    // MARK: - Success Cases

    func testFetchFeaturesSuccess() async throws {
        // Given
        let expectedJSON = """
        {
            "tier": "pro",
            "features": {
                "translation_enabled": true,
                "translation_limit": 500,
                "thread_summarization": true,
                "semantic_search": false
            }
        }
        """

        mockAuthManager.mockToken = "valid_jwt_token"

        MockURLProtocol.requestHandler = { request in
            // Verify request
            XCTAssertEqual(request.url?.path, "/api/v1/features")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer valid_jwt_token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!

            return (response, expectedJSON.data(using: .utf8))
        }

        // When
        let result = try await sut.fetchFeatures()

        // Then
        XCTAssertEqual(result.tier, "pro")
        XCTAssertTrue(result.translationEnabled)
        XCTAssertEqual(result.translationLimit, 500)
        XCTAssertTrue(result.threadSummarization)
        XCTAssertFalse(result.semanticSearch)
    }

    func testFetchFeaturesWithoutAuthToken() async throws {
        // Given
        mockAuthManager.mockToken = nil

        let expectedJSON = """
        {
            "tier": "free",
            "features": {
                "translation_enabled": false,
                "translation_limit": null,
                "thread_summarization": false,
                "semantic_search": false
            }
        }
        """

        MockURLProtocol.requestHandler = { request in
            // Verify no auth header
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!

            return (response, expectedJSON.data(using: .utf8))
        }

        // When
        let result = try await sut.fetchFeatures()

        // Then
        XCTAssertEqual(result.tier, "free")
        XCTAssertFalse(result.translationEnabled)
        XCTAssertNil(result.translationLimit)
    }

    func testFetchFeaturesEnterpriseTier() async throws {
        // Given
        let expectedJSON = """
        {
            "tier": "enterprise",
            "features": {
                "translation_enabled": true,
                "translation_limit": null,
                "thread_summarization": true,
                "semantic_search": true
            }
        }
        """

        mockAuthManager.mockToken = "enterprise_token"

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, expectedJSON.data(using: .utf8))
        }

        // When
        let result = try await sut.fetchFeatures()

        // Then
        XCTAssertEqual(result.tier, "enterprise")
        XCTAssertTrue(result.translationEnabled)
        XCTAssertNil(result.translationLimit) // Unlimited
        XCTAssertTrue(result.threadSummarization)
        XCTAssertTrue(result.semanticSearch)
    }

    // MARK: - Error Cases

    func testFetchFeaturesUnauthorized() async {
        // Given
        mockAuthManager.mockToken = "invalid_token"

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, nil)
        }

        // When/Then
        do {
            _ = try await sut.fetchFeatures()
            XCTFail("Should throw unauthorized error")
        } catch let error as FeatureFlagsServiceError {
            XCTAssertEqual(error, .unauthorized)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testFetchFeaturesHTTPError403() async {
        // Given
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!
            return (response, nil)
        }

        // When/Then
        do {
            _ = try await sut.fetchFeatures()
            XCTFail("Should throw HTTP error")
        } catch let error as FeatureFlagsServiceError {
            if case .httpError(let statusCode) = error {
                XCTAssertEqual(statusCode, 403)
            } else {
                XCTFail("Wrong error type")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testFetchFeaturesHTTPError500() async {
        // Given
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, nil)
        }

        // When/Then
        do {
            _ = try await sut.fetchFeatures()
            XCTFail("Should throw HTTP error")
        } catch let error as FeatureFlagsServiceError {
            if case .httpError(let statusCode) = error {
                XCTAssertEqual(statusCode, 500)
            } else {
                XCTFail("Wrong error type")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testFetchFeaturesNetworkError() async {
        // Given
        MockURLProtocol.requestHandler = { request in
            throw NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet, userInfo: nil)
        }

        // When/Then
        do {
            _ = try await sut.fetchFeatures()
            XCTFail("Should throw network error")
        } catch let error as FeatureFlagsServiceError {
            if case .networkError(_) = error {
                // Success
            } else {
                XCTFail("Wrong error type")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testFetchFeaturesInvalidJSON() async {
        // Given
        let invalidJSON = "{ invalid json }"

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, invalidJSON.data(using: .utf8))
        }

        // When/Then
        do {
            _ = try await sut.fetchFeatures()
            XCTFail("Should throw decoding error")
        } catch {
            // Expected to fail decoding
            XCTAssertNotNil(error)
        }
    }

    func testFetchFeaturesInvalidResponse() async {
        // Given
        MockURLProtocol.requestHandler = { request in
            // Return non-HTTPURLResponse
            throw FeatureFlagsServiceError.invalidResponse
        }

        // When/Then
        do {
            _ = try await sut.fetchFeatures()
            XCTFail("Should throw invalid response error")
        } catch {
            XCTAssertNotNil(error)
        }
    }

    // MARK: - Check Feature Tests

    func testCheckFeatureSuccess() async throws {
        // Given
        let expectedJSON = """
        {
            "data": {
                "feature": "translation_enabled",
                "has_access": true,
                "tier": "pro"
            }
        }
        """

        mockAuthManager.mockToken = "valid_token"

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/v1/features/translation_enabled")

            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, expectedJSON.data(using: .utf8))
        }

        // When
        let hasAccess = try await sut.checkFeature("translation_enabled")

        // Then
        XCTAssertTrue(hasAccess)
    }

    func testCheckFeatureNoAccess() async throws {
        // Given
        let expectedJSON = """
        {
            "data": {
                "feature": "semantic_search",
                "has_access": false,
                "tier": "free"
            }
        }
        """

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, expectedJSON.data(using: .utf8))
        }

        // When
        let hasAccess = try await sut.checkFeature("semantic_search")

        // Then
        XCTAssertFalse(hasAccess)
    }

    func testCheckFeatureUnauthorized() async {
        // Given
        mockAuthManager.mockToken = nil

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, nil)
        }

        // When/Then
        do {
            _ = try await sut.checkFeature("any_feature")
            XCTFail("Should throw unauthorized error")
        } catch let error as FeatureFlagsServiceError {
            XCTAssertEqual(error, .unauthorized)
        } catch {
            XCTFail("Unexpected error type")
        }
    }

    // MARK: - FeaturesResponse Tests

    func testFeaturesResponseToFeaturesDictionary() {
        // Given
        let response = FeaturesResponse(
            tier: "pro",
            translationEnabled: true,
            translationLimit: 500,
            threadSummarization: true,
            semanticSearch: false
        )

        // When
        let dictionary = response.toFeaturesDictionary()

        // Then
        XCTAssertEqual(dictionary.count, 3)
        XCTAssertEqual(dictionary["translation_enabled"], true)
        XCTAssertEqual(dictionary["thread_summarization"], true)
        XCTAssertEqual(dictionary["semantic_search"], false)
    }

    // MARK: - Error Description Tests

    func testServiceErrorDescriptions() {
        XCTAssertNotNil(FeatureFlagsServiceError.invalidResponse.errorDescription)
        XCTAssertNotNil(FeatureFlagsServiceError.unauthorized.errorDescription)
        XCTAssertNotNil(FeatureFlagsServiceError.httpError(statusCode: 500).errorDescription)

        let networkError = NSError(domain: "test", code: 1, userInfo: nil)
        XCTAssertNotNil(FeatureFlagsServiceError.networkError(networkError).errorDescription)
    }
}

// MARK: - Mock Objects

class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data?))?

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            fatalError("Handler not set")
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)

            if let data = data {
                client?.urlProtocol(self, didLoad: data)
            }

            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
        // No-op
    }
}

class MockAuthManager: AuthManager {
    var mockToken: String?

    override func getAccessToken() async -> String? {
        return mockToken
    }
}

// MARK: - Test Extensions

extension FeatureFlagsServiceError: Equatable {
    public static func == (lhs: FeatureFlagsServiceError, rhs: FeatureFlagsServiceError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidResponse, .invalidResponse),
             (.unauthorized, .unauthorized):
            return true
        case (.httpError(let lhsCode), .httpError(let rhsCode)):
            return lhsCode == rhsCode
        default:
            return false
        }
    }
}
