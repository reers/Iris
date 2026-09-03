//
//  CallTests.swift
//  IrisTests
//
//  Tests for the Call chainable API.
//

import XCTest
@testable import Iris

final class CallTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Reset global configuration
        Iris.configuration = IrisConfiguration()
    }
    
    // MARK: - Basic Configuration Tests
    
    func testPathConfiguration() {
        let request = Call<Empty>()
            .path("/users")
        
        XCTAssertEqual(request.path, "/users")
    }
    
    func testMethodConfiguration() {
        let request = Call<Empty>()
            .method(.post)
        
        XCTAssertEqual(request.method, .post)
    }
    
    func testTimeoutConfiguration() {
        let request = Call<Empty>()
            .timeout(60)
        
        XCTAssertEqual(request.timeout, 60)
    }
    
    func testTimeoutFallsBackToConfiguration() {
        Iris.configure(IrisConfiguration().timeout(45))
        
        let request = Call<Empty>()
        
        XCTAssertEqual(request.timeout, 45)
    }
    
    func testRequestTimeoutOverridesConfiguration() {
        Iris.configure(IrisConfiguration().timeout(45))
        
        let request = Call<Empty>()
            .timeout(10)
        
        XCTAssertEqual(request.timeout, 10)
    }
    
    func testServiceTimeoutOverridesConfiguration() {
        Iris.configure(IrisConfiguration().timeout(45))
        let service = IrisService(timeout: 15)
        
        let request = service.call(Empty.self)
        
        XCTAssertEqual(request.timeout, 15)
    }
    
    func testRequestTimeoutOverridesServiceTimeout() {
        let service = IrisService(timeout: 15)
        
        let request = service.call(Empty.self)
            .timeout(5)
        
        XCTAssertEqual(request.timeout, 5)
    }
    
    func testDefaultValues() {
        let request = Call<Empty>()
        
        XCTAssertEqual(request.path, "")
        XCTAssertEqual(request.method, .get)
        XCTAssertEqual(request.timeout, 30)
        XCTAssertNil(request.headers)
        XCTAssertTrue(request.sampleData.isEmpty)
    }
    
    // MARK: - Headers Configuration Tests
    
    func testHeadersConfiguration() {
        let headers = ["Content-Type": "application/json", "Accept": "application/json"]
        let request = Call<Empty>()
            .headers(headers)
        
        XCTAssertEqual(request.headers, headers)
    }
    
    func testSingleHeaderConfiguration() {
        let request = Call<Empty>()
            .header("X-Custom", "value")
        
        XCTAssertEqual(request.headers?["X-Custom"], "value")
    }
    
    func testMultipleHeadersChaining() {
        let request = Call<Empty>()
            .header("Header1", "value1")
            .header("Header2", "value2")
        
        XCTAssertEqual(request.headers?["Header1"], "value1")
        XCTAssertEqual(request.headers?["Header2"], "value2")
    }
    
    func testServiceHeadersMergeBetweenGlobalAndRequestHeaders() async throws {
        var capturedHeaders: [String: String] = [:]
        StubURLProtocol.handler = { request in
            capturedHeaders = request.allHTTPHeaderFields ?? [:]
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
                .baseURL("https://global.example.com")
                .headers([
                    "X-Global": "global",
                    "X-Shared": "global"
                ])
                .session(makeStubbedSession())
        )
        let service = IrisService(
            headers: [
                "X-Service": "service",
                "X-Shared": "service"
            ]
        )
        
        _ = try await service.call(Empty.self)
            .path("/headers")
            .headers([
                "X-Request": "request",
                "X-Shared": "request"
            ])
            .send()
        
        XCTAssertEqual(capturedHeaders["X-Global"], "global")
        XCTAssertEqual(capturedHeaders["X-Service"], "service")
        XCTAssertEqual(capturedHeaders["X-Request"], "request")
        XCTAssertEqual(capturedHeaders["X-Shared"], "request")
    }
    
    func testServiceBaseURLOverridesConfigurationBaseURL() {
        Iris.configure(IrisConfiguration().baseURL("https://global.example.com"))
        let service = IrisService(baseURL: URL(string: "https://service.example.com")!)
        
        let request = service.call(Empty.self)
        
        XCTAssertEqual(request.configuredBaseURL?.absoluteString, "https://service.example.com")
    }
    
    func testRequestBaseURLOverridesServiceBaseURL() {
        let service = IrisService(baseURL: URL(string: "https://service.example.com")!)
        
        let request = service.call(Empty.self)
            .baseURL("https://request.example.com")
        
        XCTAssertEqual(request.configuredBaseURL?.absoluteString, "https://request.example.com")
    }
    
    func testAuthorizationHeader() {
        let request = Call<Empty>()
            .authorization("Basic abc123")
        
        XCTAssertEqual(request.headers?["Authorization"], "Basic abc123")
    }
    
    func testBearerTokenHeader() {
        let request = Call<Empty>()
            .bearerToken("token123")
        
        XCTAssertEqual(request.headers?["Authorization"], "Bearer token123")
    }
    
    // MARK: - Task Configuration Tests
    
    func testQueryParameters() {
        let request = Call<Empty>()
            .query(["page": 1, "limit": 10])
        
        if case .requestParameters(let params, let encoding) = request.task {
            XCTAssertEqual(params["page"] as? Int, 1)
            XCTAssertEqual(params["limit"] as? Int, 10)
            XCTAssertTrue(encoding is URLEncoding)
        } else {
            XCTFail("Expected callParameters task")
        }
    }
    
    func testBodyDictionary() {
        // Explicitly cast to [String: Any] to use the dictionary overload
        // instead of the Encodable overload
        let params: [String: Any] = ["name": "test"]
        let request = Call<Empty>()
            .body(params)
        
        if case .requestParameters(let requestParams, let encoding) = request.task {
            XCTAssertEqual(requestParams["name"] as? String, "test")
            XCTAssertTrue(encoding is JSONEncoding)
        } else {
            XCTFail("Expected callParameters task")
        }
    }
    
    func testBodyEncodable() {
        struct User: Encodable {
            let name: String
        }
        
        let request = Call<Empty>()
            .body(User(name: "test"))
        
        if case .requestJSONEncodable(let encodable) = request.task {
            XCTAssertNotNil(encodable)
        } else {
            XCTFail("Expected callJSONEncodable task")
        }
    }
    
    func testBodyEncodableWithCustomEncoder() {
        struct User: Encodable {
            let name: String
        }
        
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        
        let request = Call<Empty>()
            .body(User(name: "test"), encoder: encoder)
        
        if case .requestCustomJSONEncodable = request.task {
            // Expected
        } else {
            XCTFail("Expected callCustomJSONEncodable task")
        }
    }
    
    func testBodyData() {
        let data = "test data".data(using: .utf8)!
        let request = Call<Empty>()
            .body(data)
        
        if case .requestData(let bodyData) = request.task {
            XCTAssertEqual(bodyData, data)
        } else {
            XCTFail("Expected callData task")
        }
    }
    
    func testFormBody() {
        let request = Call<Empty>()
            .formBody(["username": "test", "password": "secret"])
        
        if case .requestParameters(let params, let encoding) = request.task {
            XCTAssertEqual(params["username"] as? String, "test")
            XCTAssertTrue(encoding is URLEncoding)
        } else {
            XCTFail("Expected callParameters task")
        }
    }
    
    func testCompositeRequest() {
        let request = Call<Empty>()
            .composite(query: ["id": 1], body: ["name": "test"])
        
        if case .requestCompositeParameters(let bodyParams, _, let urlParams) = request.task {
            XCTAssertEqual(urlParams["id"] as? Int, 1)
            XCTAssertEqual(bodyParams["name"] as? String, "test")
        } else {
            XCTFail("Expected callCompositeParameters task")
        }
    }
    
    // MARK: - Upload Configuration Tests
    
    func testUploadFile() {
        let fileURL = URL(string: "file:///test.txt")!
        let request = Call<Empty>()
            .upload(file: fileURL)
        
        if case .uploadFile(let url) = request.task {
            XCTAssertEqual(url, fileURL)
        } else {
            XCTFail("Expected uploadFile task")
        }
    }
    
    func testUploadMultipartFormData() {
        let formData = MultipartFormData(parts: [
            MultipartFormBodyPart(provider: .data(Data()), name: "file")
        ])
        let request = Call<Empty>()
            .upload(multipart: formData)
        
        if case .uploadMultipartFormData(let data) = request.task {
            XCTAssertEqual(data.parts.count, 1)
        } else {
            XCTFail("Expected uploadMultipartFormData task")
        }
    }
    
    func testUploadMultipartBodyParts() {
        let parts = [
            MultipartFormBodyPart(provider: .data(Data()), name: "file", fileName: "test.txt", mimeType: "text/plain")
        ]
        let request = Call<Empty>()
            .upload(multipart: parts)
        
        if case .uploadMultipartFormData(let data) = request.task {
            XCTAssertEqual(data.parts.count, 1)
            XCTAssertEqual(data.parts[0].name, "file")
            XCTAssertEqual(data.parts[0].fileName, "test.txt")
        } else {
            XCTFail("Expected uploadMultipartFormData task")
        }
    }
    
    func testUploadMultipartWithQuery() {
        let formData = MultipartFormData(parts: [])
        let request = Call<Empty>()
            .upload(multipart: formData, query: ["id": 1])
        
        if case .uploadCompositeMultipartFormData(_, let params) = request.task {
            XCTAssertEqual(params["id"] as? Int, 1)
        } else {
            XCTFail("Expected uploadCompositeMultipartFormData task")
        }
    }
    
    // MARK: - Download Configuration Tests
    
    func testDownloadDestination() {
        let destination: DownloadDestination = { url, _ in (url, []) }
        let request = Call<Empty>()
            .download(to: destination)
        
        if case .downloadDestination = request.task {
            // Expected
        } else {
            XCTFail("Expected downloadDestination task")
        }
    }
    
    func testDownloadWithParameters() {
        let destination: DownloadDestination = { url, _ in (url, []) }
        let request = Call<Empty>()
            .download(parameters: ["format": "pdf"], to: destination)
        
        if case .downloadParameters(let params, _, _) = request.task {
            XCTAssertEqual(params["format"] as? String, "pdf")
        } else {
            XCTFail("Expected downloadParameters task")
        }
    }
    
    // MARK: - Validation Configuration Tests
    
    func testValidationTypeNone() {
        let request = Call<Empty>()
            .validate(.none)
        
        XCTAssertEqual(request.validationType, .none)
    }
    
    func testValidateSuccessCodes() {
        let request = Call<Empty>()
            .validateSuccessCodes()
        
        XCTAssertEqual(request.validationType, .successCodes)
    }
    
    func testValidateSuccessAndRedirectCodes() {
        let request = Call<Empty>()
            .validateSuccessAndRedirectCodes()
        
        XCTAssertEqual(request.validationType, .successAndRedirectCodes)
    }
    
    func testValidateCustomStatusCodes() {
        let request = Call<Empty>()
            .validate(statusCodes: [200, 201, 204])
        
        XCTAssertEqual(request.validationType, .customCodes([200, 201, 204]))
    }
    
    // MARK: - BaseURL Configuration Tests
    
    func testBaseURLFromURL() {
        let url = URL(string: "https://api.example.com")!
        let request = Call<Empty>()
            .baseURL(url)
        
        XCTAssertEqual(request.baseURL, url)
    }
    
    func testBaseURLFromString() {
        let request = Call<Empty>()
            .baseURL("https://api.example.com")
        
        XCTAssertEqual(request.baseURL.absoluteString, "https://api.example.com")
    }
    
    func testBaseURLFallsBackToGlobalConfiguration() {
        Iris.configure(IrisConfiguration().baseURL("https://global.example.com"))
        
        let request = Call<Empty>()
        
        XCTAssertEqual(request.baseURL.absoluteString, "https://global.example.com")
    }
    
    func testBaseURLOverridesGlobalConfiguration() {
        Iris.configure(IrisConfiguration().baseURL("https://global.example.com"))
        
        let request = Call<Empty>()
            .baseURL("https://local.example.com")
        
        XCTAssertEqual(request.baseURL.absoluteString, "https://local.example.com")
    }
    
    func testResolveAbsolutePathDoesNotNeedBaseURL() throws {
        let url = try Iris.resolveURL(baseURL: nil, path: "https://api.github.com/users/1")
        
        XCTAssertEqual(url.absoluteString, "https://api.github.com/users/1")
    }
    
    func testResolveAbsolutePathIgnoresBaseURL() throws {
        let base = URL(string: "https://api.example.com")!
        let url = try Iris.resolveURL(baseURL: base, path: "https://api.github.com/users/1")
        
        XCTAssertEqual(url.absoluteString, "https://api.github.com/users/1")
    }
    
    func testResolveRelativePathUsesBaseURL() throws {
        let base = URL(string: "https://api.example.com")!
        let url = try Iris.resolveURL(baseURL: base, path: "/users/1")
        
        XCTAssertEqual(url.absoluteString, "https://api.example.com/users/1")
    }
    
    func testResolveRelativePathWithoutBaseURLThrows() {
        XCTAssertThrowsError(try Iris.resolveURL(baseURL: nil, path: "/users/1")) { error in
            guard case IrisError.requestMapping = error else {
                XCTFail("Expected requestMapping, got \(error)")
                return
            }
        }
    }
    
    // MARK: - Decoder Configuration Tests
    
    func testCustomDecoder() {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        let request = Call<Empty>()
            .decoder(decoder)
        
        XCTAssertNotNil(request.decoder)
    }
    
    // MARK: - Stub Configuration Tests
    
    func testStubData() {
        let data = "stub data".data(using: .utf8)!
        let request = Call<Empty>()
            .stub(data)
        
        XCTAssertEqual(request.sampleData, data)
    }
    
    func testStubFromEncodable() {
        struct User: Encodable {
            let name: String
        }
        
        let request = Call<Empty>()
            .stub(User(name: "test"))
        
        XCTAssertFalse(request.sampleData.isEmpty)
    }
    
    func testStubUsesConfigurationEncoder() throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        Iris.configure(IrisConfiguration().encoder(encoder))
        
        struct Probe: Encodable {
            let userName: String
        }
        
        let request = Call<Empty>()
            .stub(Probe(userName: "ada"))
        let json = try JSONSerialization.jsonObject(with: request.sampleData) as! [String: String]
        
        XCTAssertEqual(json["user_name"], "ada")
        XCTAssertNil(json["userName"])
    }
    
    func testStubEncoderOverridesConfiguration() throws {
        let configEncoder = JSONEncoder()
        configEncoder.keyEncodingStrategy = .convertToSnakeCase
        Iris.configure(IrisConfiguration().encoder(configEncoder))
        
        struct Probe: Encodable {
            let userName: String
        }
        
        let request = Call<Empty>()
            .stub(Probe(userName: "ada"), encoder: JSONEncoder())
        let json = try JSONSerialization.jsonObject(with: request.sampleData) as! [String: String]
        
        XCTAssertEqual(json["userName"], "ada")
        XCTAssertNil(json["user_name"])
    }
    
    func testStubFromString() {
        let request = Call<Empty>()
            .stub("{\"name\": \"test\"}")
        
        XCTAssertEqual(String(data: request.sampleData, encoding: .utf8), "{\"name\": \"test\"}")
    }
    
    func testStubBehavior() {
        let request = Call<Empty>()
            .stub(behavior: .immediate)
        
        XCTAssertNotNil(request.stubBehavior)
        if case .immediate = request.stubBehavior {
            // Expected
        } else {
            XCTFail("Expected immediate stub behavior")
        }
    }
    
    func testStubBehaviorDelayed() {
        let request = Call<Empty>()
            .stub(behavior: .delayed(1.5))
        
        if case .delayed(let delay) = request.stubBehavior {
            XCTAssertEqual(delay, 1.5)
        } else {
            XCTFail("Expected delayed stub behavior")
        }
    }
    
    // MARK: - OnComplete Configuration Tests
    
    func testOnCompleteConfiguration() {
        let request = Call<Empty>()
            .onComplete { _ in }
        
        XCTAssertNotNil(request.onCompleteHandler)
    }
    
    func testOnCompletePreservesOtherConfiguration() {
        let request = Call<GitHubUser>()
            .path("/users/test")
            .method(.get)
            .timeout(60)
            .onComplete { _ in }
            .validateSuccessCodes()
        
        XCTAssertEqual(request.path, "/users/test")
        XCTAssertEqual(request.method, .get)
        XCTAssertEqual(request.timeout, 60)
        XCTAssertEqual(request.validationType, .successCodes)
        XCTAssertNotNil(request.onCompleteHandler)
    }
    
    // MARK: - Cancellation Tests
    
    func testCancellingTaskCancelsUnderlyingRequest() async {
        let didStartUnderlyingRequest = expectation(description: "Underlying request should start")
        let didCancelUnderlyingRequest = expectation(description: "Underlying request should be cancelled")
        StubURLProtocol.responseDelay = 5
        StubURLProtocol.onStartLoading = {
            didStartUnderlyingRequest.fulfill()
        }
        StubURLProtocol.onStopLoading = {
            didCancelUnderlyingRequest.fulfill()
        }
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }
        defer { StubURLProtocol.reset() }
        
        Iris.configure(IrisConfiguration().session(makeStubbedSession()))
        
        let task = _Concurrency.Task {
            try await Call<Empty>()
                .baseURL("https://example.com")
                .path("/slow")
                .send()
        }
        
        await fulfillment(of: [didStartUnderlyingRequest], timeout: 1)
        task.cancel()
        await fulfillment(of: [didCancelUnderlyingRequest], timeout: 1)
    }
    
    // MARK: - Chaining Tests
    
    func testCompleteChaining() {
        let request = Call<GitHubUser>()
            .baseURL("https://api.github.com")
            .path("/users/octocat")
            .method(.get)
            .header("Accept", "application/json")
            .timeout(30)
            .validateSuccessCodes()
        
        XCTAssertEqual(request.baseURL.absoluteString, "https://api.github.com")
        XCTAssertEqual(request.path, "/users/octocat")
        XCTAssertEqual(request.method, .get)
        XCTAssertEqual(request.headers?["Accept"], "application/json")
        XCTAssertEqual(request.timeout, 30)
        XCTAssertEqual(request.validationType, .successCodes)
    }
    
    func testPostRequestChaining() {
        struct CreateUser: Encodable {
            let name: String
            let email: String
        }
        
        let request = Call<GitHubUser>()
            .path("/users")
            .method(.post)
            .body(CreateUser(name: "Test", email: "test@example.com"))
            .header("Content-Type", "application/json")
            .validateSuccessCodes()
        
        XCTAssertEqual(request.path, "/users")
        XCTAssertEqual(request.method, .post)
        if case .requestJSONEncodable = request.task {
            // Expected
        } else {
            XCTFail("Expected callJSONEncodable task")
        }
    }
    
    // MARK: - Static Factory Tests
    
    func testEmptyResponseFactory() {
        let request = Call.empty()
        
        XCTAssertEqual(request.method, .get)
        if case .requestPlain = request.task {
            // Expected
        } else {
            XCTFail("Expected callPlain task")
        }
    }
    
    func testDataResponseFactory() {
        let request = Call.data()
        
        XCTAssertEqual(request.method, .get)
        if case .requestPlain = request.task {
            // Expected
        } else {
            XCTFail("Expected callPlain task")
        }
    }
    
    func testStringResponseFactory() {
        let request = Call.string()
        
        XCTAssertEqual(request.method, .get)
        if case .requestPlain = request.task {
            // Expected
        } else {
            XCTFail("Expected callPlain task")
        }
    }
    
    // MARK: - TargetType Conformance Tests
    
    func testTargetTypeConformance() {
        let request = Call<Empty>()
            .baseURL("https://api.example.com")
            .path("/test")
            .method(.post)
            .body(["key": "value"])
            .headers(["X-Custom": "value"])
            .validateSuccessCodes()
            .stub("test data")
        
        // Test TargetType protocol conformance
        XCTAssertEqual(request.baseURL.absoluteString, "https://api.example.com")
        XCTAssertEqual(request.path, "/test")
        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(request.headers?["X-Custom"], "value")
        XCTAssertEqual(request.validationType, .successCodes)
        XCTAssertEqual(String(data: request.sampleData, encoding: .utf8), "test data")
    }
}
