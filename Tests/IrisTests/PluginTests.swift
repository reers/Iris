//
//  PluginTests.swift
//  IrisTests
//
//  Tests for the plugin system and various plugin implementations.
//

import XCTest
@testable import Iris

final class PluginTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        Iris.configuration = IrisConfiguration()
    }
    
    override func tearDown() {
        Iris.configuration = IrisConfiguration()
        super.tearDown()
    }
    
    // MARK: - Default Implementation Tests
    
    func testEmptyPluginUsesDefaultImplementations() {
        let plugin = EmptyPlugin()
        let request = URLRequest(url: URL(string: "https://example.com")!)
        let target = Call<Empty>().path("/test")
        
        // prepare should return the same request
        let preparedRequest = plugin.prepare(request, target: target)
        XCTAssertEqual(preparedRequest.url, request.url)
        
        // willSend should not crash
        plugin.willSend(MockCallType(), target: target)
        
        // didReceive should not crash
        let response = RawResponse(statusCode: 200, data: Data())
        plugin.didReceive(.success(response), target: target)
        
        // process should return the same result
        let result: Result<RawResponse, IrisError> = .success(response)
        let processedResult = plugin.process(result, target: target)
        if case .success(let processedResponse) = processedResult {
            XCTAssertEqual(processedResponse.statusCode, 200)
        } else {
            XCTFail("Expected success result")
        }
    }
    
    // MARK: - TestingPlugin Tests
    
    func testTestingPluginPrepare() {
        let plugin = TestingPlugin()
        var request = URLRequest(url: URL(string: "https://example.com")!)
        let target = Call<Empty>().path("/test")
        
        request = plugin.prepare(request, target: target)
        
        XCTAssertEqual(request.value(forHTTPHeaderField: "prepared"), "yes")
        XCTAssertEqual(plugin.prepareCalledCount, 1)
    }
    
    func testTestingPluginWillSend() {
        let plugin = TestingPlugin()
        var request = URLRequest(url: URL(string: "https://example.com")!)
        let target = Call<Empty>().path("/test")
        
        // First prepare the request
        request = plugin.prepare(request, target: target)
        
        // Then call willSend
        let mockCallType = MockCallType(request: request)
        plugin.willSend(mockCallType, target: target)
        
        XCTAssertNotNil(plugin.request)
        XCTAssertTrue(plugin.didPrepare)
        XCTAssertEqual(plugin.willSendCalledCount, 1)
    }
    
    func testTestingPluginDidReceive() {
        let plugin = TestingPlugin()
        let target = Call<Empty>().path("/test")
        let response = RawResponse(statusCode: 200, data: Data())
        
        plugin.didReceive(.success(response), target: target)
        
        XCTAssertNotNil(plugin.result)
        XCTAssertEqual(plugin.didReceiveCalledCount, 1)
        
        if case .success(let receivedResponse) = plugin.result {
            XCTAssertEqual(receivedResponse.statusCode, 200)
        } else {
            XCTFail("Expected success result")
        }
    }
    
    func testTestingPluginProcess() {
        let plugin = TestingPlugin()
        let target = Call<Empty>().path("/test")
        let response = RawResponse(statusCode: 200, data: Data())
        
        let processedResult = plugin.process(.success(response), target: target)
        
        XCTAssertEqual(plugin.processCalledCount, 1)
        
        if case .success(let processedResponse) = processedResult {
            // TestingPlugin changes status code to -1
            XCTAssertEqual(processedResponse.statusCode, -1)
        } else {
            XCTFail("Expected success result")
        }
    }
    
    func testTestingPluginReset() {
        let plugin = TestingPlugin()
        let target = Call<Empty>().path("/test")
        let request = URLRequest(url: URL(string: "https://example.com")!)
        let response = RawResponse(statusCode: 200, data: Data())
        
        // Call all methods
        _ = plugin.prepare(request, target: target)
        plugin.willSend(MockCallType(), target: target)
        plugin.didReceive(.success(response), target: target)
        _ = plugin.process(.success(response), target: target)
        
        // Verify state before reset
        XCTAssertGreaterThan(plugin.prepareCalledCount, 0)
        
        // Reset
        plugin.reset()
        
        // Verify state after reset
        XCTAssertNil(plugin.request)
        XCTAssertNil(plugin.result)
        XCTAssertFalse(plugin.didPrepare)
        XCTAssertEqual(plugin.prepareCalledCount, 0)
        XCTAssertEqual(plugin.willSendCalledCount, 0)
        XCTAssertEqual(plugin.didReceiveCalledCount, 0)
        XCTAssertEqual(plugin.processCalledCount, 0)
    }
    
    // MARK: - OrderTrackingPlugin Tests
    
    func testOrderTrackingPlugin() {
        let plugin = OrderTrackingPlugin()
        let request = URLRequest(url: URL(string: "https://example.com")!)
        let target = Call<Empty>().path("/test")
        let response = RawResponse(statusCode: 200, data: Data())
        
        _ = plugin.prepare(request, target: target)
        plugin.willSend(MockCallType(), target: target)
        plugin.didReceive(.success(response), target: target)
        _ = plugin.process(.success(response), target: target)
        
        XCTAssertEqual(plugin.callOrder, ["prepare", "willSend", "didReceive", "process"])
    }
    
    // MARK: - HeaderModifyingPlugin Tests
    
    func testHeaderModifyingPlugin() {
        let plugin = HeaderModifyingPlugin(headerKey: "X-Custom", headerValue: "CustomValue")
        var request = URLRequest(url: URL(string: "https://example.com")!)
        let target = Call<Empty>().path("/test")
        
        request = plugin.prepare(request, target: target)
        
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Custom"), "CustomValue")
    }
    
    // MARK: - ResponseModifyingPlugin Tests
    
    func testResponseModifyingPlugin() {
        let plugin = ResponseModifyingPlugin(newStatusCode: 201)
        let target = Call<Empty>().path("/test")
        let response = RawResponse(statusCode: 200, data: Data())
        
        let processedResult = plugin.process(.success(response), target: target)
        
        if case .success(let processedResponse) = processedResult {
            XCTAssertEqual(processedResponse.statusCode, 201)
        } else {
            XCTFail("Expected success result")
        }
    }
    
    func testResponseModifyingPluginPreservesFailure() {
        let plugin = ResponseModifyingPlugin(newStatusCode: 201)
        let target = Call<Empty>().path("/test")
        let error = IrisError.requestMapping("test")
        
        let processedResult = plugin.process(.failure(error), target: target)
        
        if case .failure = processedResult {
            // Expected - failure should pass through
        } else {
            XCTFail("Expected failure result")
        }
    }
    
    // MARK: - ErrorInjectingPlugin Tests
    
    func testErrorInjectingPlugin() {
        let injectedError = IrisError.requestMapping("injected error")
        let plugin = ErrorInjectingPlugin(error: injectedError)
        let target = Call<Empty>().path("/test")
        let response = RawResponse(statusCode: 200, data: Data())
        
        let processedResult = plugin.process(.success(response), target: target)
        
        if case .failure(let error) = processedResult {
            if case .requestMapping(let url) = error {
                XCTAssertEqual(url, "injected error")
            } else {
                XCTFail("Expected requestMapping error")
            }
        } else {
            XCTFail("Expected failure result")
        }
    }
    
    // MARK: - NetworkActivityPlugin Tests
    
    func testNetworkActivityPluginBegan() {
        var beganCalled = false
        var receivedTarget: TargetType?
        
        let plugin = NetworkActivityPlugin { change, target in
            if change == .began {
                beganCalled = true
                receivedTarget = target
            }
        }
        
        let target = Call<Empty>().path("/test")
        plugin.willSend(MockCallType(), target: target)
        
        XCTAssertTrue(beganCalled)
        XCTAssertNotNil(receivedTarget)
    }
    
    func testNetworkActivityPluginEnded() {
        var endedCalled = false
        var receivedTarget: TargetType?
        
        let plugin = NetworkActivityPlugin { change, target in
            if change == .ended {
                endedCalled = true
                receivedTarget = target
            }
        }
        
        let target = Call<Empty>().path("/test")
        let response = RawResponse(statusCode: 200, data: Data())
        plugin.didReceive(.success(response), target: target)
        
        XCTAssertTrue(endedCalled)
        XCTAssertNotNil(receivedTarget)
    }
    
    // MARK: - Multiple Plugins Tests
    
    func testMultiplePluginsAreCalledInOrder() {
        let plugin1 = OrderTrackingPlugin()
        let plugin2 = OrderTrackingPlugin()
        
        let request = URLRequest(url: URL(string: "https://example.com")!)
        let target = Call<Empty>().path("/test")
        _ = RawResponse(statusCode: 200, data: Data())
        
        // Simulate plugin chain for prepare
        var modifiedRequest = request
        modifiedRequest = plugin1.prepare(modifiedRequest, target: target)
        modifiedRequest = plugin2.prepare(modifiedRequest, target: target)
        
        // Both plugins should have "prepare" in their call order
        XCTAssertEqual(plugin1.callOrder, ["prepare"])
        XCTAssertEqual(plugin2.callOrder, ["prepare"])
    }
    
    func testPluginChainModifiesRequest() {
        let plugin1 = HeaderModifyingPlugin(headerKey: "X-First", headerValue: "first")
        let plugin2 = HeaderModifyingPlugin(headerKey: "X-Second", headerValue: "second")
        
        var request = URLRequest(url: URL(string: "https://example.com")!)
        let target = Call<Empty>().path("/test")
        
        request = plugin1.prepare(request, target: target)
        request = plugin2.prepare(request, target: target)
        
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-First"), "first")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Second"), "second")
    }
    
    func testPluginChainModifiesResponse() {
        let plugin1 = ResponseModifyingPlugin(newStatusCode: 201)
        let plugin2 = ResponseModifyingPlugin(newStatusCode: 202)
        
        let target = Call<Empty>().path("/test")
        let response = RawResponse(statusCode: 200, data: Data())
        
        var result: Result<RawResponse, IrisError> = .success(response)
        result = plugin1.process(result, target: target)
        result = plugin2.process(result, target: target)
        
        if case .success(let finalResponse) = result {
            // Last plugin should win
            XCTAssertEqual(finalResponse.statusCode, 202)
        } else {
            XCTFail("Expected success result")
        }
    }
}

// MARK: - Mock CallType

/// A mock implementation of CallType for testing plugins.
private struct MockCallType: CallType {
    var request: URLRequest?
    var sessionHeaders: [String: String] = [:]
    
    init(request: URLRequest? = nil) {
        self.request = request
    }
    
    func authenticate(username: String, password: String, persistence: URLCredential.Persistence) -> MockCallType {
        return self
    }
    
    func authenticate(with credential: URLCredential) -> MockCallType {
        return self
    }
    
    func cURLDescription(calling handler: @escaping (String) -> Void) -> MockCallType {
        handler(request?.description ?? "")
        return self
    }
}
