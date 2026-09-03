//
//  ResponseTests.swift
//  IrisTests
//
//  Tests for Response mapping and filtering.
//

import XCTest
@testable import Iris

final class ResponseTests: XCTestCase {
    
    func testHTTPResponseMapsDecodable() throws {
        let jsonData = "{\"login\": \"testuser\", \"id\": 123}".data(using: .utf8)!
        let response = HTTPResponse(statusCode: 200, data: jsonData)
        
        let user = try response.map(GitHubUser.self)
        
        XCTAssertEqual(user.login, "testuser")
        XCTAssertEqual(user.id, 123)
    }
    
    func testResponseModelIsNonOptional() {
        let user = GitHubUser(login: "test", id: 1)
        let httpResponse = HTTPResponse(statusCode: 200, data: Data())
        let response = Response(model: user, httpResponse: httpResponse)
        
        XCTAssertEqual(response.model.login, "test")
        XCTAssertEqual(response.model.id, 1)
    }
    
    func testMapDataReturnsRawBody() throws {
        let jsonData = #"{"ok":true}"#.data(using: .utf8)!
        let response = HTTPResponse(statusCode: 200, data: jsonData)
        
        XCTAssertEqual(try response.map(Data.self), jsonData)
    }
    
    func testMapDataReturnsEmptyBody() throws {
        let response = HTTPResponse(statusCode: 204, data: Data())
        XCTAssertEqual(try response.map(Data.self), Data())
    }
    
    func testMapStringReturnsUTF8Body() throws {
        let body = "not-json"
        let response = HTTPResponse(statusCode: 200, data: body.data(using: .utf8)!)
        
        XCTAssertEqual(try response.map(String.self), body)
    }
    
    func testMapStringAtKeyPathExtractsJSONString() throws {
        let jsonData = #"{"msg":"hello"}"#.data(using: .utf8)!
        let response = HTTPResponse(statusCode: 200, data: jsonData)
        
        XCTAssertEqual(try response.map(String.self, atKeyPath: "msg"), "hello")
    }
    
    func testMapDataAtKeyPathStillUsesJSON() throws {
        let jsonData = #"{"payload":{"n":1}}"#.data(using: .utf8)!
        let response = HTTPResponse(statusCode: 200, data: jsonData)
        
        let nested = try response.map(Data.self, atKeyPath: "payload")
        let object = try JSONSerialization.jsonObject(with: nested) as? [String: Any]
        XCTAssertEqual((object?["n"] as? NSNumber)?.intValue, 1)
    }
    
    func testMapStringThrowsOnInvalidUTF8() {
        let response = HTTPResponse(statusCode: 200, data: Data([0xFF, 0xFE]))
        XCTAssertThrowsError(try response.map(String.self)) { error in
            guard case IrisError.stringMapping = error else {
                XCTFail("Expected stringMapping error")
                return
            }
        }
    }
    
    // MARK: - Status Code Filter Tests
    
    func testFilterSuccessfulStatusCodesSucceeds() throws {
        let response = HTTPResponse(statusCode: 200, data: Data())
        let filteredResponse = try response.filterSuccessfulStatusCodes()
        XCTAssertEqual(filteredResponse.statusCode, 200)
    }
    
    func testFilterSuccessfulStatusCodesFails() {
        let response = HTTPResponse(statusCode: 400, data: Data())
        XCTAssertThrowsError(try response.filterSuccessfulStatusCodes()) { error in
            guard case IrisError.statusCode = error else {
                XCTFail("Expected statusCode error")
                return
            }
        }
    }
    
    func testFilterSuccessfulStatusAndRedirectCodesSucceeds() throws {
        let response1 = HTTPResponse(statusCode: 200, data: Data())
        let filtered1 = try response1.filterSuccessfulStatusAndRedirectCodes()
        XCTAssertEqual(filtered1.statusCode, 200)
        
        let response2 = HTTPResponse(statusCode: 301, data: Data())
        let filtered2 = try response2.filterSuccessfulStatusAndRedirectCodes()
        XCTAssertEqual(filtered2.statusCode, 301)
    }
    
    func testFilterSuccessfulStatusAndRedirectCodesFails() {
        let response = HTTPResponse(statusCode: 400, data: Data())
        XCTAssertThrowsError(try response.filterSuccessfulStatusAndRedirectCodes()) { error in
            guard case IrisError.statusCode = error else {
                XCTFail("Expected statusCode error")
                return
            }
        }
    }
    
    func testFilterStatusCodesWithRange() throws {
        let response = HTTPResponse(statusCode: 201, data: Data())
        let filteredResponse = try response.filter(statusCodes: 200..<300)
        XCTAssertEqual(filteredResponse.statusCode, 201)
    }
    
    func testFilterSingleStatusCode() throws {
        let response = HTTPResponse(statusCode: 200, data: Data())
        let filteredResponse = try response.filter(statusCode: 200)
        XCTAssertEqual(filteredResponse.statusCode, 200)
    }
    
    func testFilterSingleStatusCodeFails() {
        let response = HTTPResponse(statusCode: 201, data: Data())
        XCTAssertThrowsError(try response.filter(statusCode: 200)) { error in
            guard case IrisError.statusCode = error else {
                XCTFail("Expected statusCode error")
                return
            }
        }
    }
    
    // MARK: - Convenience Property Tests
    
    func testIsSuccess() {
        let successResponse = HTTPResponse(statusCode: 200, data: Data())
        XCTAssertTrue(successResponse.isSuccess)
        
        let failureResponse = HTTPResponse(statusCode: 400, data: Data())
        XCTAssertFalse(failureResponse.isSuccess)
    }
    
    func testIsRedirect() {
        let redirectResponse = HTTPResponse(statusCode: 301, data: Data())
        XCTAssertTrue(redirectResponse.isRedirect)
        
        let nonRedirectResponse = HTTPResponse(statusCode: 200, data: Data())
        XCTAssertFalse(nonRedirectResponse.isRedirect)
    }
    
    func testIsClientError() {
        let clientErrorResponse = HTTPResponse(statusCode: 404, data: Data())
        XCTAssertTrue(clientErrorResponse.isClientError)
        
        let nonClientErrorResponse = HTTPResponse(statusCode: 200, data: Data())
        XCTAssertFalse(nonClientErrorResponse.isClientError)
    }
    
    func testIsServerError() {
        let serverErrorResponse = HTTPResponse(statusCode: 500, data: Data())
        XCTAssertTrue(serverErrorResponse.isServerError)
        
        let nonServerErrorResponse = HTTPResponse(statusCode: 200, data: Data())
        XCTAssertFalse(nonServerErrorResponse.isServerError)
    }
    
    // MARK: - JSON Mapping Tests
    
    func testMapJSONWithValidJSON() throws {
        let jsonData = "{\"name\": \"test\"}".data(using: .utf8)!
        let response = HTTPResponse(statusCode: 200, data: jsonData)
        
        let json = try response.mapJSON() as? [String: Any]
        XCTAssertEqual(json?["name"] as? String, "test")
    }
    
    func testMapJSONWithInvalidJSON() {
        let invalidData = "not json".data(using: .utf8)!
        let response = HTTPResponse(statusCode: 200, data: invalidData)
        
        XCTAssertThrowsError(try response.mapJSON()) { error in
            guard case IrisError.jsonMapping = error else {
                XCTFail("Expected jsonMapping error")
                return
            }
        }
    }
    
    func testMapJSONWithEmptyDataDefaultParameter() {
        let response = HTTPResponse(statusCode: 200, data: Data())
        
        XCTAssertThrowsError(try response.mapJSON()) { error in
            guard case IrisError.jsonMapping = error else {
                XCTFail("Expected jsonMapping error")
                return
            }
        }
    }
    
    func testMapJSONWithEmptyDataFailsOnEmptyDataFalse() throws {
        let response = HTTPResponse(statusCode: 200, data: Data())
        
        // Should not throw
        let result = try response.mapJSON(failsOnEmptyData: false)
        XCTAssertTrue(result is NSNull)
    }
    
    // MARK: - String Mapping Tests
    
    func testMapStringWithValidUTF8() throws {
        let stringData = "Hello, World!".data(using: .utf8)!
        let response = HTTPResponse(statusCode: 200, data: stringData)
        
        let string = try response.mapString()
        XCTAssertEqual(string, "Hello, World!")
    }
    
    func testMapStringWithKeyPath() throws {
        let jsonData = "{\"nested\": {\"value\": \"found\"}}".data(using: .utf8)!
        let response = HTTPResponse(statusCode: 200, data: jsonData)
        
        let string = try response.mapString(atKeyPath: "nested.value")
        XCTAssertEqual(string, "found")
    }
    
    func testMapStringWithInvalidKeyPath() {
        let jsonData = "{\"nested\": {\"value\": \"found\"}}".data(using: .utf8)!
        let response = HTTPResponse(statusCode: 200, data: jsonData)
        
        XCTAssertThrowsError(try response.mapString(atKeyPath: "invalid.path")) { error in
            guard case IrisError.stringMapping = error else {
                XCTFail("Expected stringMapping error")
                return
            }
        }
    }
    
    // MARK: - Decodable Mapping Tests
    
    func testMapDecodable() throws {
        let jsonData = "{\"login\": \"testuser\", \"id\": 123}".data(using: .utf8)!
        let response = HTTPResponse(statusCode: 200, data: jsonData)
        
        let user = try response.map(GitHubUser.self)
        XCTAssertEqual(user.login, "testuser")
        XCTAssertEqual(user.id, 123)
    }
    
    func testMapDecodableWithKeyPath() throws {
        let jsonData = "{\"user\": {\"login\": \"testuser\", \"id\": 123}}".data(using: .utf8)!
        let response = HTTPResponse(statusCode: 200, data: jsonData)
        
        let user = try response.map(GitHubUser.self, atKeyPath: "user")
        XCTAssertEqual(user.login, "testuser")
        XCTAssertEqual(user.id, 123)
    }
    
    func testMapDecodableWithInvalidJSON() {
        let invalidData = "not json".data(using: .utf8)!
        let response = HTTPResponse(statusCode: 200, data: invalidData)
        
        XCTAssertThrowsError(try response.map(GitHubUser.self)) { error in
            guard case IrisError.objectMapping = error else {
                XCTFail("Expected objectMapping error")
                return
            }
        }
    }
    
    func testMapDecodableWithEmptyDataFailsOnEmptyDataFalse() throws {
        let response = HTTPResponse(statusCode: 200, data: Data())
        
        let optionalIssue = try response.map(OptionalIssue.self, failsOnEmptyData: false)
        XCTAssertNil(optionalIssue.title)
        XCTAssertNil(optionalIssue.createdAt)
    }
    
    func testMapDecodableWithCustomDecoder() throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .formatted(formatter)
        
        let jsonData = "{\"title\": \"Test\", \"createdAt\": \"2024-01-15\"}".data(using: .utf8)!
        let response = HTTPResponse(statusCode: 200, data: jsonData)
        
        let issue = try response.map(Issue.self, using: decoder)
        XCTAssertEqual(issue.title, "Test")
    }
    
    func testMapUsesConfigurationDecoder() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        Iris.configure(IrisConfiguration().decoder(decoder))
        defer { Iris.configuration = IrisConfiguration() }
        
        struct Probe: Decodable {
            let userName: String
        }
        
        let data = "{\"user_name\": \"ada\"}".data(using: .utf8)!
        let response = HTTPResponse(statusCode: 200, data: data)
        let probe = try response.map(Probe.self)
        
        XCTAssertEqual(probe.userName, "ada")
    }
    
    // MARK: - Image Mapping Tests
    
    func testMapImageWithValidImageData() throws {
        let response = HTTPResponse(statusCode: 200, data: testImageData)
        
        let image = try response.mapImage()
        XCTAssertNotNil(image)
    }
    
    func testMapImageWithInvalidData() {
        let invalidData = "not an image".data(using: .utf8)!
        let response = HTTPResponse(statusCode: 200, data: invalidData)
        
        XCTAssertThrowsError(try response.mapImage()) { error in
            guard case IrisError.imageMapping = error else {
                XCTFail("Expected imageMapping error")
                return
            }
        }
    }
    
    // MARK: - Response Description Tests
    
    func testResponseDescription() {
        let data = "test data".data(using: .utf8)!
        let response = HTTPResponse(statusCode: 200, data: data)
        
        XCTAssertTrue(response.description.contains("200"))
        XCTAssertTrue(response.description.contains("\(data.count)"))
    }
    
    // MARK: - Response<Model> Tests
    
    func testResponseWithModel() {
        let user = GitHubUser(login: "test", id: 1)
        let response = Response<GitHubUser>(
            model: user,
            statusCode: 200,
            data: Data(),
            request: nil,
            response: nil
        )
        
        XCTAssertEqual(response.model.login, "test")
        XCTAssertEqual(response.model.id, 1)
    }
    
    func testResponseUnwrap() throws {
        let user = GitHubUser(login: "test", id: 1)
        let response = Response<GitHubUser>(
            model: user,
            statusCode: 200,
            data: Data(),
            request: nil,
            response: nil
        )
        
        let unwrappedUser = try response.unwrap()
        XCTAssertEqual(unwrappedUser.login, "test")
    }
    
    func testResponseStoresHTTPResponse() {
        let user = GitHubUser(login: "test", id: 1)
        let data = "test".data(using: .utf8)!
        let response = Response<GitHubUser>(
            model: user,
            statusCode: 200,
            data: data,
            request: nil,
            response: nil
        )
        
        XCTAssertEqual(response.httpResponse.statusCode, 200)
        XCTAssertEqual(response.httpResponse.data, data)
    }
    
    // MARK: - Array Mapping at KeyPath Tests
    
    func testMapArrayAtKeyPath() throws {
        let jsonData = "{\"users\": [{\"login\": \"user1\", \"id\": 1}, {\"login\": \"user2\", \"id\": 2}]}".data(using: .utf8)!
        let response = HTTPResponse(statusCode: 200, data: jsonData)
        
        let users = try response.map([GitHubUser].self, atKeyPath: "users")
        XCTAssertEqual(users.count, 2)
        XCTAssertEqual(users[0].login, "user1")
        XCTAssertEqual(users[1].login, "user2")
    }
    
    // MARK: - Scalar Value at KeyPath Tests
    
    func testMapScalarAtKeyPath() throws {
        let jsonData = "{\"count\": 42}".data(using: .utf8)!
        let response = HTTPResponse(statusCode: 200, data: jsonData)
        
        let count = try response.map(Int.self, atKeyPath: "count")
        XCTAssertEqual(count, 42)
    }
    
    // MARK: - Deep Nested KeyPath Tests
    
    func testMapDeepNestedKeyPath() throws {
        let jsonData = "{\"data\": {\"user\": {\"profile\": {\"login\": \"nested\", \"id\": 999}}}}".data(using: .utf8)!
        let response = HTTPResponse(statusCode: 200, data: jsonData)
        
        let user = try response.map(GitHubUser.self, atKeyPath: "data.user.profile")
        XCTAssertEqual(user.login, "nested")
        XCTAssertEqual(user.id, 999)
    }
}
