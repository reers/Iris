//
//  ConfigurationTests.swift
//  IrisTests
//
//  Tests for IrisConfiguration and the chainable configuration API.
//

import XCTest
import Alamofire
@testable import Iris

final class ConfigurationTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Reset global configuration
        Iris.configuration = IrisConfiguration()
    }
    
    override func tearDown() {
        // Reset global configuration
        Iris.configuration = IrisConfiguration()
        super.tearDown()
    }
    
    // MARK: - Default Values Tests
    
    func testDefaultConfiguration() {
        let config = IrisConfiguration()
        
        XCTAssertNil(config.baseURL)
        XCTAssertTrue(config.defaultHeaders.isEmpty)
        XCTAssertEqual(config.defaultTimeout, 30)
        XCTAssertNotNil(config.jsonDecoder)
        XCTAssertNotNil(config.jsonEncoder)
        XCTAssertTrue(config.plugins.isEmpty)
        XCTAssertNotNil(config.session)
        XCTAssertNil(config.stubBehavior)
        XCTAssertNil(config.retryPolicy)
    }
    
    // MARK: - BaseURL Configuration Tests
    
    func testBaseURLFromURL() {
        let url = URL(string: "https://api.example.com")!
        let config = IrisConfiguration()
            .baseURL(url)
        
        XCTAssertEqual(config.baseURL, url)
    }
    
    func testBaseURLFromString() {
        let config = IrisConfiguration()
            .baseURL("https://api.example.com")
        
        XCTAssertEqual(config.baseURL?.absoluteString, "https://api.example.com")
    }
    
    func testBaseURLFromInvalidString() {
        let config = IrisConfiguration()
            .baseURL("")
        
        XCTAssertNil(config.baseURL)
    }
    
    // MARK: - Headers Configuration Tests
    
    func testSingleHeader() {
        let config = IrisConfiguration()
            .header("Accept", "application/json")
        
        XCTAssertEqual(config.defaultHeaders["Accept"], "application/json")
    }
    
    func testMultipleHeaders() {
        let config = IrisConfiguration()
            .header("Accept", "application/json")
            .header("Content-Type", "application/json")
        
        XCTAssertEqual(config.defaultHeaders["Accept"], "application/json")
        XCTAssertEqual(config.defaultHeaders["Content-Type"], "application/json")
    }
    
    func testHeadersDictionary() {
        let headers = ["Accept": "application/json", "Content-Type": "application/json"]
        let config = IrisConfiguration()
            .headers(headers)
        
        XCTAssertEqual(config.defaultHeaders, headers)
    }
    
    func testHeadersMerge() {
        let config = IrisConfiguration()
            .header("Accept", "application/json")
            .headers(["Content-Type": "application/json", "Accept": "text/html"])
        
        // New values should override old values
        XCTAssertEqual(config.defaultHeaders["Accept"], "text/html")
        XCTAssertEqual(config.defaultHeaders["Content-Type"], "application/json")
    }
    
    func testHeadersMergeOverridesExistingHeadersIgnoringCase() {
        let config = IrisConfiguration()
            .header("Accept", "application/json")
            .headers(["accept": "text/plain"])

        XCTAssertEqual(config.defaultHeaders["Accept"], "text/plain")
        XCTAssertNil(config.defaultHeaders["accept"])
    }

    // MARK: - Timeout Configuration Tests
    
    func testTimeout() {
        let config = IrisConfiguration()
            .timeout(60)
        
        XCTAssertEqual(config.defaultTimeout, 60)
    }
    
    // MARK: - Plugin Configuration Tests
    
    func testSinglePlugin() {
        let plugin = TestingPlugin()
        let config = IrisConfiguration()
            .plugin(plugin)
        
        XCTAssertEqual(config.plugins.count, 1)
    }
    
    func testMultiplePlugins() {
        let plugin1 = TestingPlugin()
        let plugin2 = TestingPlugin()
        let config = IrisConfiguration()
            .plugin(plugin1)
            .plugin(plugin2)
        
        XCTAssertEqual(config.plugins.count, 2)
    }
    
    func testPluginsArray() {
        let plugins = [TestingPlugin(), TestingPlugin(), TestingPlugin()]
        let config = IrisConfiguration()
            .plugins(plugins)
        
        XCTAssertEqual(config.plugins.count, 3)
    }
    
    // MARK: - Session Configuration Tests
    
    func testCustomSession() {
        let customSession = Session()
        let config = IrisConfiguration()
            .session(customSession)
        
        XCTAssertTrue(config.session === customSession)
    }
    
    // MARK: - Stub Configuration Tests
    
    func testStubImmediate() {
        let config = IrisConfiguration()
            .stub(.immediate)
        
        if case .immediate = config.stubBehavior {
            // Expected
        } else {
            XCTFail("Expected immediate stub behavior")
        }
    }
    
    func testStubDelayed() {
        let config = IrisConfiguration()
            .stub(.delayed(1.5))
        
        if case .delayed(let delay) = config.stubBehavior {
            XCTAssertEqual(delay, 1.5)
        } else {
            XCTFail("Expected delayed stub behavior")
        }
    }
    
    // MARK: - JSON Decoder Configuration Tests
    
    func testCustomDecoder() {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        let config = IrisConfiguration()
            .decoder(decoder)
        
        XCTAssertTrue(config.jsonDecoder === decoder)
    }
    
    // MARK: - JSON Encoder Configuration Tests
    
    func testCustomEncoder() {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        
        let config = IrisConfiguration()
            .encoder(encoder)
        
        XCTAssertTrue(config.jsonEncoder === encoder)
    }
    
    // MARK: - Global Configuration Tests
    
    func testGlobalConfiguration() {
        let config = IrisConfiguration()
            .baseURL("https://api.example.com")
            .header("Accept", "application/json")
            .timeout(45)
        
        Iris.configure(config)
        
        XCTAssertEqual(Iris.configuration.baseURL?.absoluteString, "https://api.example.com")
        XCTAssertEqual(Iris.configuration.defaultHeaders["Accept"], "application/json")
        XCTAssertEqual(Iris.configuration.defaultTimeout, 45)
    }
    
    func testGlobalConfigurationReplacement() {
        let config1 = IrisConfiguration()
            .baseURL("https://api1.example.com")
        
        let config2 = IrisConfiguration()
            .baseURL("https://api2.example.com")
        
        Iris.configure(config1)
        XCTAssertEqual(Iris.configuration.baseURL?.absoluteString, "https://api1.example.com")
        
        Iris.configure(config2)
        XCTAssertEqual(Iris.configuration.baseURL?.absoluteString, "https://api2.example.com")
    }
    
    // MARK: - Chaining Tests
    
    func testCompleteChaining() {
        let plugin = TestingPlugin()
        let session = Session()
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        
        let config = IrisConfiguration()
            .baseURL("https://api.example.com")
            .header("Accept", "application/json")
            .header("Content-Type", "application/json")
            .timeout(60)
            .plugin(plugin)
            .session(session)
            .decoder(decoder)
            .encoder(encoder)
            .stub(.immediate)
        
        XCTAssertEqual(config.baseURL?.absoluteString, "https://api.example.com")
        XCTAssertEqual(config.defaultHeaders["Accept"], "application/json")
        XCTAssertEqual(config.defaultHeaders["Content-Type"], "application/json")
        XCTAssertEqual(config.defaultTimeout, 60)
        XCTAssertEqual(config.plugins.count, 1)
        XCTAssertTrue(config.session === session)
        XCTAssertTrue(config.jsonDecoder === decoder)
        XCTAssertTrue(config.jsonEncoder === encoder)
        if case .immediate = config.stubBehavior {
            // Expected
        } else {
            XCTFail("Expected immediate stub behavior")
        }
    }
    
    // MARK: - Init with Parameters Tests
    
    func testInitWithParameters() {
        let url = URL(string: "https://api.example.com")!
        let headers = ["Accept": "application/json"]
        let timeout: TimeInterval = 45
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        let plugins: [any PluginType] = [TestingPlugin()]
        let session = Session()
        let stubBehavior = StubBehavior.immediate
        
        let config = IrisConfiguration(
            baseURL: url,
            defaultHeaders: headers,
            defaultTimeout: timeout,
            jsonDecoder: decoder,
            jsonEncoder: encoder,
            plugins: plugins,
            session: session,
            stubBehavior: stubBehavior
        )
        
        XCTAssertEqual(config.baseURL, url)
        XCTAssertEqual(config.defaultHeaders, headers)
        XCTAssertEqual(config.defaultTimeout, timeout)
        XCTAssertTrue(config.jsonDecoder === decoder)
        XCTAssertTrue(config.jsonEncoder === encoder)
        XCTAssertEqual(config.plugins.count, 1)
        XCTAssertTrue(config.session === session)
        if case .immediate = config.stubBehavior {
            // Expected
        } else {
            XCTFail("Expected immediate stub behavior")
        }
    }

    func testRetryBuilder() {
        let config = IrisConfiguration()
            .retry(count: 3, interval: 0.25, backoff: .linear)

        XCTAssertEqual(config.retryPolicy?.count, 3)
        XCTAssertEqual(config.retryPolicy?.interval, 0.25)
        XCTAssertEqual(config.retryPolicy?.backoff, .linear)
    }
}
