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
    
    func testEmptyPluginUsesDefaultImplementations() async throws {
        let plugin = EmptyPlugin()
        let request = URLRequest(url: URL(string: "https://example.com")!)
        let target = Call<Empty>().path("/test")
        
        // prepare should return the same request
        let preparedRequest = try await plugin.prepare(request, target: target)
        XCTAssertEqual(preparedRequest.url, request.url)
        
        // willSend should not crash
        plugin.willSend(MockCallType(), target: target)
        
        // didReceive should not crash
        let response = HTTPResponse(statusCode: 200, data: Data())
        plugin.didReceive(.success(response), target: target)
        
        // process should return the same result
        let result: Result<HTTPResponse, IrisError> = .success(response)
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
        let response = HTTPResponse(statusCode: 200, data: Data())
        
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
        let response = HTTPResponse(statusCode: 200, data: Data())
        
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
        let response = HTTPResponse(statusCode: 200, data: Data())
        
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
    
    func testWillSendCallTypeProvidesCurlDescription() async throws {
        let curlDescription = SendableBox("")
        let plugin = CurlCapturingPlugin(curlDescription: curlDescription)
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("{}".utf8))
        }
        defer { StubURLProtocol.reset() }

        Iris.configure(
            IrisConfiguration()
                .baseURL("https://example.com")
                .session(makeStubbedSession())
                .plugin(plugin)
        )

        _ = try await Call<Empty>()
            .path("/curl")
            .method(.post)
            .header("X-Debug", "yes")
            .send()

        XCTAssertTrue(curlDescription.value.hasPrefix("$ curl"))
        XCTAssertTrue(curlDescription.value.contains("https://example.com/curl"))
        XCTAssertTrue(curlDescription.value.contains("-X POST"))
        XCTAssertTrue(curlDescription.value.contains("X-Debug: yes"))
    }

    func testWillSendAuthenticateSupportsMoyaStyleCredentialPlugin() async throws {
        let authenticatedRequestURL = SendableBox<URL?>(nil)
        let plugin = BasicAuthenticationPlugin(
            username: "user",
            password: "passwd",
            authenticatedRequestURL: authenticatedRequestURL
        )
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("{}".utf8))
        }
        defer { StubURLProtocol.reset() }

        Iris.configure(
            IrisConfiguration()
                .baseURL("https://example.com")
                .session(makeStubbedSession())
                .plugin(plugin)
        )

        _ = try await Call<Empty>()
            .path("/auth")
            .send()

        XCTAssertEqual(authenticatedRequestURL.value?.absoluteString, "https://example.com/auth")
    }

    func testAsyncPrepareCanAwaitBeforeModifyingLiveRequest() async throws {
        let capturedToken = SendableBox<String?>(nil)
        let plugin = AsyncTokenPlugin(store: AsyncTokenStore(token: "fresh-token"))
        StubURLProtocol.handler = { request in
            capturedToken.value = request.value(forHTTPHeaderField: "Authorization")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("{}".utf8))
        }
        defer { StubURLProtocol.reset() }

        Iris.configure(
            IrisConfiguration()
                .baseURL("https://example.com")
                .session(makeStubbedSession())
                .plugin(plugin)
        )

        _ = try await Call<Empty>()
            .path("/async-auth")
            .send()

        XCTAssertEqual(capturedToken.value, "Bearer fresh-token")
    }

    func testPrepareFailureFailsRequestBeforeNetworkStarts() async {
        let didStart = SendableBox(false)
        StubURLProtocol.onStartLoading = {
            didStart.value = true
        }
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("{}".utf8))
        }
        defer { StubURLProtocol.reset() }

        Iris.configure(
            IrisConfiguration()
                .baseURL("https://example.com")
                .session(makeStubbedSession())
                .plugin(ThrowingPreparePlugin())
        )

        do {
            _ = try await Call<Empty>()
                .path("/prepare-error")
                .send()
            XCTFail("Expected prepare failure")
        } catch let IrisError.underlying(error, response) {
            XCTAssertNil(response)
            XCTAssertTrue(String(describing: error).contains("PrepareFailure"))
        } catch {
            XCTFail("Expected underlying prepare failure, got \(error)")
        }

        XCTAssertFalse(didStart.value)
    }

    // MARK: - OrderTrackingPlugin Tests
    
    func testOrderTrackingPlugin() {
        let plugin = OrderTrackingPlugin()
        let request = URLRequest(url: URL(string: "https://example.com")!)
        let target = Call<Empty>().path("/test")
        let response = HTTPResponse(statusCode: 200, data: Data())
        
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
        let response = HTTPResponse(statusCode: 200, data: Data())
        
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
        let response = HTTPResponse(statusCode: 200, data: Data())
        
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
        let beganCalled = SendableBox(false)
        let receivedTarget = SendableBox<(any TargetType)?>(nil)
        
        let plugin = NetworkActivityPlugin { change, target in
            if change == .began {
                beganCalled.value = true
                receivedTarget.value = target
            }
        }
        
        let target = Call<Empty>().path("/test")
        plugin.willSend(MockCallType(), target: target)
        
        XCTAssertTrue(beganCalled.value)
        XCTAssertNotNil(receivedTarget.value)
    }
    
    func testNetworkActivityPluginEnded() {
        let endedCalled = SendableBox(false)
        let receivedTarget = SendableBox<(any TargetType)?>(nil)
        
        let plugin = NetworkActivityPlugin { change, target in
            if change == .ended {
                endedCalled.value = true
                receivedTarget.value = target
            }
        }
        
        let target = Call<Empty>().path("/test")
        let response = HTTPResponse(statusCode: 200, data: Data())
        plugin.didReceive(.success(response), target: target)
        
        XCTAssertTrue(endedCalled.value)
        XCTAssertNotNil(receivedTarget.value)
    }
    
    // MARK: - Multiple Plugins Tests
    
    func testMultiplePluginsAreCalledInOrder() {
        let plugin1 = OrderTrackingPlugin()
        let plugin2 = OrderTrackingPlugin()
        
        let request = URLRequest(url: URL(string: "https://example.com")!)
        let target = Call<Empty>().path("/test")
        _ = HTTPResponse(statusCode: 200, data: Data())
        
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
        let response = HTTPResponse(statusCode: 200, data: Data())
        
        var result: Result<HTTPResponse, IrisError> = .success(response)
        result = plugin1.process(result, target: target)
        result = plugin2.process(result, target: target)
        
        if case .success(let finalResponse) = result {
            // Last plugin should win
            XCTAssertEqual(finalResponse.statusCode, 202)
        } else {
            XCTFail("Expected success result")
        }
    }
    
    // MARK: - Failure Lifecycle Tests
    
    func testPluginsReceiveTransportFailure() async {
        StubURLProtocol.handler = { _ in
            throw URLError(.notConnectedToInternet)
        }
        defer { StubURLProtocol.reset() }
        
        let plugin = TestingPlugin()
        Iris.configure(
            IrisConfiguration()
                .session(makeStubbedSession())
                .plugin(plugin)
        )
        
        do {
            _ = try await Call<Empty>()
                .baseURL("https://example.com")
                .path("/")
                .send()
            XCTFail("Expected the request to fail")
        } catch {
            XCTAssertEqual(plugin.willSendCalledCount, 1)
            XCTAssertEqual(plugin.didReceiveCalledCount, 1)
            XCTAssertEqual(plugin.processCalledCount, 1)
            
            if case .failure(.underlying) = plugin.result {
                // Expected
            } else {
                XCTFail("Plugin should receive an underlying failure, got \(String(describing: plugin.result))")
            }
            
            guard let irisError = error as? IrisError, case .underlying = irisError else {
                XCTFail("Caller should receive an underlying error, got \(error)")
                return
            }
        }
    }
    
    func testValidatedHTTPErrorIsStatusCodeAndReachesPlugins() async {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 404,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }
        defer { StubURLProtocol.reset() }
        
        let plugin = TestingPlugin()
        Iris.configure(
            IrisConfiguration()
                .session(makeStubbedSession())
                .plugin(plugin)
        )
        
        do {
            _ = try await Call<Empty>()
                .baseURL("https://example.com")
                .path("/missing")
                .validateSuccessCodes()
                .send()
            XCTFail("Expected the request to fail")
        } catch {
            XCTAssertEqual(plugin.didReceiveCalledCount, 1)
            XCTAssertEqual(plugin.processCalledCount, 1)
            
            if case .failure(.statusCode(let response)) = plugin.result {
                XCTAssertEqual(response.statusCode, 404)
            } else {
                XCTFail("Plugin should receive a statusCode failure, got \(String(describing: plugin.result))")
            }
            
            guard let irisError = error as? IrisError, case .statusCode(let response) = irisError else {
                XCTFail("Caller should receive a statusCode error, got \(error)")
                return
            }
            XCTAssertEqual(response.statusCode, 404)
        }
    }

    func testTransportFailureAfterResponseHeadersIsUnderlyingError() async {
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com/interrupted")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        let result = Iris.mapNetworkResult(
            data: Data("partial".utf8),
            request: nil,
            response: response,
            error: URLError(.networkConnectionLost)
        )

        if case .failure(.underlying(_, let response)) = result {
            XCTAssertEqual(response?.statusCode, 200)
        } else {
            XCTFail("Expected underlying failure, got \(result)")
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
    
    func cURLDescription(calling handler: @escaping @Sendable (String) -> Void) -> MockCallType {
        handler(request?.description ?? "")
        return self
    }
}

private struct CurlCapturingPlugin: PluginType {
    let curlDescription: SendableBox<String>

    func willSend(_ request: CallType, target: TargetType) {
        _ = request.cURLDescription { curlDescription.value = $0 }
    }
}

private struct BasicAuthenticationPlugin: PluginType {
    let username: String
    let password: String
    let authenticatedRequestURL: SendableBox<URL?>

    func willSend(_ request: CallType, target: TargetType) {
        let authenticatedRequest = request.authenticate(username: username, password: password, persistence: .none)
        authenticatedRequestURL.value = authenticatedRequest.request?.url
    }
}

private actor AsyncTokenStore {
    private let token: String

    init(token: String) {
        self.token = token
    }

    func currentToken() -> String {
        token
    }
}

private struct AsyncTokenPlugin: PluginType {
    let store: AsyncTokenStore

    func prepare(_ request: URLRequest, target: TargetType) async throws -> URLRequest {
        var request = request
        let token = await store.currentToken()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }
}

private enum PrepareFailure: Error {
    case failed
}

private struct ThrowingPreparePlugin: PluginType {
    func prepare(_ request: URLRequest, target: TargetType) async throws -> URLRequest {
        throw PrepareFailure.failed
    }
}
