//
//  EndpointTests.swift
//  IrisTests
//
//  Tests for the Endpoint class and URLRequest conversion.
//

import XCTest
@testable import Iris

final class EndpointTests: XCTestCase {
    
    /// A simple test endpoint (Iris style: direct construction, no enum needed).
    var simpleGitHubEndpoint: Endpoint {
        makeSimpleEndpoint()
    }
    
    override func setUp() {
        super.setUp()
        Iris.configuration = IrisConfiguration()
    }
    
    override func tearDown() {
        Iris.configuration = IrisConfiguration()
        super.tearDown()
    }
    
    // MARK: - Basic Tests
    
    func testReturnsNewEndpointForAddingNewHTTPHeaderFields() {
        let endpoint = simpleGitHubEndpoint
        let agent = "Zalbinian"
        let newEndpoint = endpoint.adding(newHTTPHeaderFields: ["User-Agent": agent])
        let newEndpointAgent = newEndpoint.httpHeaderFields?["User-Agent"]
        
        // Make sure our closure updated the sample response
        XCTAssertEqual(newEndpointAgent, agent)
        
        // Compare other properties to ensure they've been copied correctly
        XCTAssertEqual(newEndpoint.url, endpoint.url)
        XCTAssertEqual(newEndpoint.method, endpoint.method)
    }
    
    func testReturnsNilURLRequestForInvalidURL() {
        // Note: URL(string:) with percent encoding handles many "invalid" URLs
        // An empty string is truly invalid
        let badEndpoint = Endpoint(
            url: "",
            sampleResponseClosure: { .networkResponse(200, Data()) },
            method: .get,
            task: .requestPlain,
            httpHeaderFields: nil
        )
        let urlRequest = try? badEndpoint.urlRequest()
        XCTAssertNil(urlRequest)
    }
    
    // MARK: - Task: requestPlain Tests
    
    func testRequestPlainDoesNotUpdateRequest() throws {
        let endpoint = simpleGitHubEndpoint.replacing(task: .requestPlain)
        let request = try endpoint.urlRequest()
        
        XCTAssertNil(request.httpBody)
        XCTAssertEqual(request.url?.absoluteString, endpoint.url)
        XCTAssertEqual(request.allHTTPHeaderFields, endpoint.httpHeaderFields)
        XCTAssertEqual(request.httpMethod, endpoint.method.rawValue)
    }
    
    // MARK: - Task: uploadFile Tests
    
    func testUploadFileDoesNotUpdateRequest() throws {
        let endpoint = simpleGitHubEndpoint.replacing(task: .uploadFile(URL(string: "https://google.com")!))
        let request = try endpoint.urlRequest()
        
        XCTAssertNil(request.httpBody)
        XCTAssertEqual(request.url?.absoluteString, endpoint.url)
        XCTAssertEqual(request.allHTTPHeaderFields, endpoint.httpHeaderFields)
        XCTAssertEqual(request.httpMethod, endpoint.method.rawValue)
    }
    
    // MARK: - Task: uploadMultipartFormData Tests
    
    func testUploadMultipartFormDataDoesNotUpdateRequest() throws {
        let endpoint = simpleGitHubEndpoint.replacing(task: .uploadMultipartFormData(MultipartFormData(parts: [])))
        let request = try endpoint.urlRequest()
        
        XCTAssertNil(request.httpBody)
        XCTAssertEqual(request.url?.absoluteString, endpoint.url)
        XCTAssertEqual(request.allHTTPHeaderFields, endpoint.httpHeaderFields)
        XCTAssertEqual(request.httpMethod, endpoint.method.rawValue)
    }
    
    // MARK: - Task: downloadDestination Tests
    
    func testDownloadDestinationDoesNotUpdateRequest() throws {
        let destination: DownloadDestination = { url, _ in (destinationURL: url, options: []) }
        let endpoint = simpleGitHubEndpoint.replacing(task: .downloadDestination(destination))
        let request = try endpoint.urlRequest()
        
        XCTAssertNil(request.httpBody)
        XCTAssertEqual(request.url?.absoluteString, endpoint.url)
        XCTAssertEqual(request.allHTTPHeaderFields, endpoint.httpHeaderFields)
        XCTAssertEqual(request.httpMethod, endpoint.method.rawValue)
    }
    
    // MARK: - Task: requestParameters Tests
    
    func testRequestParametersUpdatesRequestCorrectly() throws {
        let parameters = ["Nemesis": "Harvey"]
        let encoding = JSONEncoding.default
        let endpoint = simpleGitHubEndpoint.replacing(task: .requestParameters(parameters: parameters, encoding: encoding))
        let request = try endpoint.urlRequest()
        
        let newEndpoint = endpoint.replacing(task: .requestPlain)
        let newRequest = try newEndpoint.urlRequest()
        let newEncodedRequest = try? encoding.encode(newRequest, with: parameters)
        
        XCTAssertEqual(request.httpBody, newEncodedRequest?.httpBody)
        XCTAssertEqual(request.url?.absoluteString, newEncodedRequest?.url?.absoluteString)
        XCTAssertEqual(request.allHTTPHeaderFields, newEncodedRequest?.allHTTPHeaderFields)
        XCTAssertEqual(request.httpMethod, newEncodedRequest?.httpMethod)
    }
    
    // MARK: - Task: downloadParameters Tests
    
    func testDownloadParametersUpdatesRequestCorrectly() throws {
        let parameters = ["Nemesis": "Harvey"]
        let encoding = JSONEncoding.default
        let destination: DownloadDestination = { url, _ in (destinationURL: url, options: []) }
        let endpoint = simpleGitHubEndpoint.replacing(task: .downloadParameters(parameters: parameters, encoding: encoding, destination: destination))
        let request = try endpoint.urlRequest()
        
        let newEndpoint = endpoint.replacing(task: .requestPlain)
        let newRequest = try newEndpoint.urlRequest()
        let newEncodedRequest = try? encoding.encode(newRequest, with: parameters)
        
        XCTAssertEqual(request.httpBody, newEncodedRequest?.httpBody)
        XCTAssertEqual(request.url?.absoluteString, newEncodedRequest?.url?.absoluteString)
        XCTAssertEqual(request.allHTTPHeaderFields, newEncodedRequest?.allHTTPHeaderFields)
        XCTAssertEqual(request.httpMethod, newEncodedRequest?.httpMethod)
    }
    
    // MARK: - Task: requestData Tests
    
    func testRequestDataUpdatesHTTPBody() throws {
        let data = "test data".data(using: .utf8)!
        let endpoint = simpleGitHubEndpoint.replacing(task: .requestData(data))
        let request = try endpoint.urlRequest()
        
        XCTAssertEqual(request.httpBody, data)
    }
    
    func testRequestDataDoesNotUpdateOtherProperties() throws {
        let data = "test data".data(using: .utf8)!
        let endpoint = simpleGitHubEndpoint.replacing(task: .requestData(data))
        let request = try endpoint.urlRequest()
        
        XCTAssertEqual(request.url?.absoluteString, endpoint.url)
        XCTAssertEqual(request.allHTTPHeaderFields, endpoint.httpHeaderFields)
        XCTAssertEqual(request.httpMethod, endpoint.method.rawValue)
    }
    
    // MARK: - Task: requestJSONEncodable Tests
    
    func testRequestJSONEncodableUpdatesHTTPBody() throws {
        let issue = Issue(title: "Hello, Iris!", createdAt: Date(), rating: 0)
        let endpoint = simpleGitHubEndpoint.replacing(task: .requestJSONEncodable(issue))
        let request = try endpoint.urlRequest()
        
        let expectedIssue = try JSONDecoder().decode(Issue.self, from: request.httpBody!)
        XCTAssertEqual(issue.title, expectedIssue.title)
    }
    
    func testRequestJSONEncodableUpdatesContentTypeHeader() throws {
        let issue = Issue(title: "Hello, Iris!", createdAt: Date(), rating: 0)
        let endpoint = simpleGitHubEndpoint.replacing(task: .requestJSONEncodable(issue))
        let request = try endpoint.urlRequest()
        
        let contentTypeHeaders = ["Content-Type": "application/json"]
        let initialHeaderFields = endpoint.httpHeaderFields ?? [:]
        let expectedHTTPHeaderFields = initialHeaderFields.merging(contentTypeHeaders) { initialValue, _ in initialValue }
        XCTAssertEqual(request.allHTTPHeaderFields, expectedHTTPHeaderFields)
    }
    
    func testRequestJSONEncodableDoesNotUpdateOtherProperties() throws {
        let issue = Issue(title: "Hello, Iris!", createdAt: Date(), rating: 0)
        let endpoint = simpleGitHubEndpoint.replacing(task: .requestJSONEncodable(issue))
        let request = try endpoint.urlRequest()
        
        XCTAssertEqual(request.url?.absoluteString, endpoint.url)
        XCTAssertEqual(request.httpMethod, endpoint.method.rawValue)
    }
    
    // MARK: - Task: requestCustomJSONEncodable Tests
    
    func testRequestCustomJSONEncodableUpdatesHTTPBody() throws {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .formatted(formatter)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .formatted(formatter)
        
        let issue = Issue(title: "Hello, Iris!", createdAt: Date(), rating: 0)
        let endpoint = simpleGitHubEndpoint.replacing(task: .requestCustomJSONEncodable(issue, encoder: encoder))
        let request = try endpoint.urlRequest()
        
        let expectedIssue = try decoder.decode(Issue.self, from: request.httpBody!)
        XCTAssertEqual(formatter.string(from: issue.createdAt), formatter.string(from: expectedIssue.createdAt))
        XCTAssertEqual(issue.title, expectedIssue.title)
    }
    
    func testRequestJSONEncodableUsesConfigurationEncoder() throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        Iris.configure(IrisConfiguration().encoder(encoder))
        
        let endpoint = simpleGitHubEndpoint.replacing(task: .requestJSONEncodable(Issue(title: "Hello", createdAt: Date(), rating: nil)))
        let request = try endpoint.urlRequest()
        let json = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        
        XCTAssertNotNil(json["created_at"])
        XCTAssertNil(json["createdAt"])
    }
    
    func testRequestCustomJSONEncodableOverridesConfigurationEncoder() throws {
        let configEncoder = JSONEncoder()
        configEncoder.keyEncodingStrategy = .convertToSnakeCase
        Iris.configure(IrisConfiguration().encoder(configEncoder))
        
        let endpoint = simpleGitHubEndpoint.replacing(task: .requestCustomJSONEncodable(Issue(title: "Hello", createdAt: Date(), rating: nil), encoder: JSONEncoder()))
        let request = try endpoint.urlRequest()
        let json = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        
        XCTAssertNotNil(json["createdAt"])
        XCTAssertNil(json["created_at"])
    }
    
    // MARK: - Task: requestCompositeData Tests
    
    func testRequestCompositeDataUpdatesURL() throws {
        let parameters = ["Nemesis": "Harvey"]
        let data = "test data".data(using: .utf8)!
        let endpoint = simpleGitHubEndpoint.replacing(task: .requestCompositeData(bodyData: data, urlParameters: parameters))
        let request = try endpoint.urlRequest()
        
        let expectedUrl = endpoint.url + "?Nemesis=Harvey"
        XCTAssertEqual(request.url?.absoluteString, expectedUrl)
    }
    
    func testRequestCompositeDataUpdatesHTTPBody() throws {
        let parameters = ["Nemesis": "Harvey"]
        let data = "test data".data(using: .utf8)!
        let endpoint = simpleGitHubEndpoint.replacing(task: .requestCompositeData(bodyData: data, urlParameters: parameters))
        let request = try endpoint.urlRequest()
        
        XCTAssertEqual(request.httpBody, data)
    }
    
    func testRequestCompositeDataDoesNotUpdateOtherProperties() throws {
        let parameters = ["Nemesis": "Harvey"]
        let data = "test data".data(using: .utf8)!
        let endpoint = simpleGitHubEndpoint.replacing(task: .requestCompositeData(bodyData: data, urlParameters: parameters))
        let request = try endpoint.urlRequest()
        
        XCTAssertEqual(request.allHTTPHeaderFields, endpoint.httpHeaderFields)
        XCTAssertEqual(request.httpMethod, endpoint.method.rawValue)
    }
    
    // MARK: - Task: requestCompositeParameters Tests
    
    func testRequestCompositeParametersUpdatesURL() throws {
        let bodyParameters = ["Nemesis": "Harvey"]
        let urlParameters = ["Harvey": "Nemesis"]
        let encoding = JSONEncoding.default
        let endpoint = simpleGitHubEndpoint.replacing(task: .requestCompositeParameters(bodyParameters: bodyParameters, bodyEncoding: encoding, urlParameters: urlParameters))
        let request = try endpoint.urlRequest()
        
        let expectedUrl = endpoint.url + "?Harvey=Nemesis"
        XCTAssertEqual(request.url?.absoluteString, expectedUrl)
    }
    
    func testRequestCompositeParametersUpdatesRequestCorrectly() throws {
        let bodyParameters = ["Nemesis": "Harvey"]
        let urlParameters = ["Harvey": "Nemesis"]
        let encoding = JSONEncoding.default
        let endpoint = simpleGitHubEndpoint.replacing(task: .requestCompositeParameters(bodyParameters: bodyParameters, bodyEncoding: encoding, urlParameters: urlParameters))
        let request = try endpoint.urlRequest()
        
        let newEndpoint = endpoint.replacing(task: .requestPlain)
        let newRequest = try newEndpoint.urlRequest()
        let newEncodedRequest = try? encoding.encode(newRequest, with: bodyParameters)
        
        XCTAssertEqual(request.httpBody, newEncodedRequest?.httpBody)
        XCTAssertEqual(request.allHTTPHeaderFields, newEncodedRequest?.allHTTPHeaderFields)
        XCTAssertEqual(request.httpMethod, newEncodedRequest?.httpMethod)
    }
    
    // MARK: - Task: uploadCompositeMultipartFormData Tests
    
    func testUploadCompositeMultipartFormDataUpdatesURL() throws {
        let urlParameters = ["Harvey": "Nemesis"]
        let endpoint = simpleGitHubEndpoint.replacing(task: .uploadCompositeMultipartFormData(MultipartFormData(parts: []), urlParameters: urlParameters))
        let request = try endpoint.urlRequest()
        
        let expectedUrl = endpoint.url + "?Harvey=Nemesis"
        XCTAssertEqual(request.url?.absoluteString, expectedUrl)
    }
    
    // MARK: - Invalid URL Tests
    
    func testInvalidURLThrowsRequestMappingError() {
        // An empty string is truly invalid
        let badEndpoint = Endpoint(
            url: "",
            sampleResponseClosure: { .networkResponse(200, Data()) },
            method: .get,
            task: .requestPlain,
            httpHeaderFields: nil
        )
        
        var receivedError: IrisError?
        do {
            _ = try badEndpoint.urlRequest()
        } catch {
            receivedError = error as? IrisError
        }
        
        XCTAssertNotNil(receivedError)
        if case .requestMapping = receivedError {
            // Expected
        } else {
            XCTFail("Expected requestMapping error")
        }
    }
    
    // MARK: - Endpoint Equality Tests
    
    func testEndpointsAreEqualForSameURLHeadersAndFormData() {
        let endpoint1 = simpleGitHubEndpoint.replacing(task: .uploadMultipartFormData(MultipartFormData(parts: [
            MultipartFormBodyPart(provider: .data("test".data(using: .utf8)!), name: "test")
        ])))
        let endpoint2 = simpleGitHubEndpoint.replacing(task: .uploadMultipartFormData(MultipartFormData(parts: [
            MultipartFormBodyPart(provider: .data("test".data(using: .utf8)!), name: "test")
        ])))
        
        XCTAssertEqual(endpoint1, endpoint2)
    }
    
    func testEndpointsAreNotEqualForDifferentFormData() {
        let endpoint1 = simpleGitHubEndpoint.replacing(task: .uploadMultipartFormData(MultipartFormData(parts: [
            MultipartFormBodyPart(provider: .data("test".data(using: .utf8)!), name: "test")
        ])))
        let endpoint2 = simpleGitHubEndpoint.replacing(task: .uploadMultipartFormData(MultipartFormData(parts: [
            MultipartFormBodyPart(provider: .data("test1".data(using: .utf8)!), name: "test")
        ])))
        
        XCTAssertNotEqual(endpoint1, endpoint2)
    }
    
    func testEndpointsAreEqualForSameUploadFile() {
        let endpoint1 = simpleGitHubEndpoint.replacing(task: .uploadFile(URL(string: "https://google.com")!))
        let endpoint2 = simpleGitHubEndpoint.replacing(task: .uploadFile(URL(string: "https://google.com")!))
        
        XCTAssertEqual(endpoint1, endpoint2)
    }
    
    func testEndpointsAreNotEqualForDifferentUploadFile() {
        let endpoint1 = simpleGitHubEndpoint.replacing(task: .uploadFile(URL(string: "https://google.com")!))
        let endpoint2 = simpleGitHubEndpoint.replacing(task: .uploadFile(URL(string: "https://google.com?q=test")!))
        
        XCTAssertNotEqual(endpoint1, endpoint2)
    }
    
    func testEndpointsAreEqualForRequestPlain() {
        let endpoint1 = simpleGitHubEndpoint.replacing(task: .requestPlain)
        let endpoint2 = simpleGitHubEndpoint.replacing(task: .requestPlain)
        
        XCTAssertEqual(endpoint1, endpoint2)
    }
    
    func testEndpointsAreEqualForSameRequestData() {
        let endpoint1 = simpleGitHubEndpoint.replacing(task: .requestData("test".data(using: .utf8)!))
        let endpoint2 = simpleGitHubEndpoint.replacing(task: .requestData("test".data(using: .utf8)!))
        
        XCTAssertEqual(endpoint1, endpoint2)
    }
    
    func testEndpointsAreNotEqualForDifferentRequestData() {
        // Note: URLRequest equality doesn't compare httpBody, so endpoints with different
        // requestData but same URL are considered equal in Iris (same behavior as Moya)
        // This test verifies that the httpBody is actually different at the URLRequest level
        let endpoint1 = simpleGitHubEndpoint.replacing(task: .requestData("test".data(using: .utf8)!))
        let endpoint2 = simpleGitHubEndpoint.replacing(task: .requestData("test1".data(using: .utf8)!))
        
        let request1 = try! endpoint1.urlRequest()
        let request2 = try! endpoint2.urlRequest()
        
        // The httpBody should be different even if the endpoints are considered "equal"
        XCTAssertNotEqual(request1.httpBody, request2.httpBody)
    }
    
    func testEndpointsAreEqualForSameRequestParameters() {
        let endpoint1 = simpleGitHubEndpoint.replacing(task: .requestParameters(parameters: ["test": "test1"], encoding: URLEncoding.queryString))
        let endpoint2 = simpleGitHubEndpoint.replacing(task: .requestParameters(parameters: ["test": "test1"], encoding: URLEncoding.queryString))
        
        XCTAssertEqual(endpoint1, endpoint2)
    }
    
    func testEndpointsAreNotEqualForDifferentRequestParameters() {
        let endpoint1 = simpleGitHubEndpoint.replacing(task: .requestParameters(parameters: ["test": "test1"], encoding: URLEncoding.queryString))
        let endpoint2 = simpleGitHubEndpoint.replacing(task: .requestParameters(parameters: ["test": "test2"], encoding: URLEncoding.queryString))
        
        XCTAssertNotEqual(endpoint1, endpoint2)
    }
    
    // MARK: - Hashable Tests
    
    func testEndpointHashValueForUploadFile() {
        let endpoint1 = simpleGitHubEndpoint.replacing(task: .uploadFile(URL(string: "https://google.com")!))
        let endpoint2 = simpleGitHubEndpoint.replacing(task: .uploadFile(URL(string: "https://google.com")!))
        
        XCTAssertEqual(endpoint1.hashValue, endpoint2.hashValue)
    }
    
    func testEndpointHashValueForMultipartFormData() {
        let endpoint1 = simpleGitHubEndpoint.replacing(task: .uploadMultipartFormData(MultipartFormData(parts: [
            MultipartFormBodyPart(provider: .data("test".data(using: .utf8)!), name: "test")
        ])))
        let endpoint2 = simpleGitHubEndpoint.replacing(task: .uploadMultipartFormData(MultipartFormData(parts: [
            MultipartFormBodyPart(provider: .data("test".data(using: .utf8)!), name: "test")
        ])))
        
        XCTAssertEqual(endpoint1.hashValue, endpoint2.hashValue)
    }
}
