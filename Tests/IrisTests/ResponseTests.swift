//
//  ResponseTests.swift
//  IrisTests
//
//  Tests for Response mapping and filtering.
//

import XCTest
@testable import Iris

final class ResponseTests: XCTestCase {
    
    // MARK: - Status Code Filter Tests
    
    func testFilterSuccessfulStatusCodesSucceeds() throws {
        let response = RawResponse(statusCode: 200, data: Data())
        let filteredResponse = try response.filterSuccessfulStatusCodes()
        XCTAssertEqual(filteredResponse.statusCode, 200)
    }
    
    func testFilterSuccessfulStatusCodesFails() {
        let response = RawResponse(statusCode: 400, data: Data())
        XCTAssertThrowsError(try response.filterSuccessfulStatusCodes()) { error in
            guard case IrisError.statusCode = error else {
                XCTFail("Expected statusCode error")
                return
            }
        }
    }
    
    func testFilterSuccessfulStatusAndRedirectCodesSucceeds() throws {
        let response1 = RawResponse(statusCode: 200, data: Data())
        let filtered1 = try response1.filterSuccessfulStatusAndRedirectCodes()
        XCTAssertEqual(filtered1.statusCode, 200)
        
        let response2 = RawResponse(statusCode: 301, data: Data())
        let filtered2 = try response2.filterSuccessfulStatusAndRedirectCodes()
        XCTAssertEqual(filtered2.statusCode, 301)
    }
    
    func testFilterSuccessfulStatusAndRedirectCodesFails() {
        let response = RawResponse(statusCode: 400, data: Data())
        XCTAssertThrowsError(try response.filterSuccessfulStatusAndRedirectCodes()) { error in
            guard case IrisError.statusCode = error else {
                XCTFail("Expected statusCode error")
                return
            }
        }
    }
    
    func testFilterStatusCodesWithRange() throws {
        let response = RawResponse(statusCode: 201, data: Data())
        let filteredResponse = try response.filter(statusCodes: 200..<300)
        XCTAssertEqual(filteredResponse.statusCode, 201)
    }
    
    func testFilterSingleStatusCode() throws {
        let response = RawResponse(statusCode: 200, data: Data())
        let filteredResponse = try response.filter(statusCode: 200)
        XCTAssertEqual(filteredResponse.statusCode, 200)
    }
    
    func testFilterSingleStatusCodeFails() {
        let response = RawResponse(statusCode: 201, data: Data())
        XCTAssertThrowsError(try response.filter(statusCode: 200)) { error in
            guard case IrisError.statusCode = error else {
                XCTFail("Expected statusCode error")
                return
            }
        }
    }
    
    // MARK: - Convenience Property Tests
    
    func testIsSuccess() {
        let successResponse = RawResponse(statusCode: 200, data: Data())
        XCTAssertTrue(successResponse.isSuccess)
        
        let failureResponse = RawResponse(statusCode: 400, data: Data())
        XCTAssertFalse(failureResponse.isSuccess)
    }
    
    func testIsRedirect() {
        let redirectResponse = RawResponse(statusCode: 301, data: Data())
        XCTAssertTrue(redirectResponse.isRedirect)
        
        let nonRedirectResponse = RawResponse(statusCode: 200, data: Data())
        XCTAssertFalse(nonRedirectResponse.isRedirect)
    }
    
    func testIsClientError() {
        let clientErrorResponse = RawResponse(statusCode: 404, data: Data())
        XCTAssertTrue(clientErrorResponse.isClientError)
        
        let nonClientErrorResponse = RawResponse(statusCode: 200, data: Data())
        XCTAssertFalse(nonClientErrorResponse.isClientError)
    }
    
    func testIsServerError() {
        let serverErrorResponse = RawResponse(statusCode: 500, data: Data())
        XCTAssertTrue(serverErrorResponse.isServerError)
        
        let nonServerErrorResponse = RawResponse(statusCode: 200, data: Data())
        XCTAssertFalse(nonServerErrorResponse.isServerError)
    }
    
    // MARK: - JSON Mapping Tests
    
    func testMapJSONWithValidJSON() throws {
        let jsonData = "{\"name\": \"test\"}".data(using: .utf8)!
        let response = RawResponse(statusCode: 200, data: jsonData)
        
        let json = try response.mapJSON() as? [String: Any]
        XCTAssertEqual(json?["name"] as? String, "test")
    }
    
    func testMapJSONWithInvalidJSON() {
        let invalidData = "not json".data(using: .utf8)!
        let response = RawResponse(statusCode: 200, data: invalidData)
        
        XCTAssertThrowsError(try response.mapJSON()) { error in
            guard case IrisError.jsonMapping = error else {
                XCTFail("Expected jsonMapping error")
                return
            }
        }
    }
    
    func testMapJSONWithEmptyDataDefaultParameter() {
        let response = RawResponse(statusCode: 200, data: Data())
        
        XCTAssertThrowsError(try response.mapJSON()) { error in
            guard case IrisError.jsonMapping = error else {
                XCTFail("Expected jsonMapping error")
                return
            }
        }
    }
    
    func testMapJSONWithEmptyDataFailsOnEmptyDataFalse() throws {
        let response = RawResponse(statusCode: 200, data: Data())
        
        // Should not throw
        let result = try response.mapJSON(failsOnEmptyData: false)
        XCTAssertTrue(result is NSNull)
    }
    
    // MARK: - String Mapping Tests
    
    func testMapStringWithValidUTF8() throws {
        let stringData = "Hello, World!".data(using: .utf8)!
        let response = RawResponse(statusCode: 200, data: stringData)
        
        let string = try response.mapString()
        XCTAssertEqual(string, "Hello, World!")
    }
    
    func testMapStringWithKeyPath() throws {
        let jsonData = "{\"nested\": {\"value\": \"found\"}}".data(using: .utf8)!
        let response = RawResponse(statusCode: 200, data: jsonData)
        
        let string = try response.mapString(atKeyPath: "nested.value")
        XCTAssertEqual(string, "found")
    }
    
    func testMapStringWithInvalidKeyPath() {
        let jsonData = "{\"nested\": {\"value\": \"found\"}}".data(using: .utf8)!
        let response = RawResponse(statusCode: 200, data: jsonData)
        
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
        let response = RawResponse(statusCode: 200, data: jsonData)
        
        let user = try response.map(GitHubUser.self)
        XCTAssertEqual(user.login, "testuser")
        XCTAssertEqual(user.id, 123)
    }
    
    func testMapDecodableWithKeyPath() throws {
        let jsonData = "{\"user\": {\"login\": \"testuser\", \"id\": 123}}".data(using: .utf8)!
        let response = RawResponse(statusCode: 200, data: jsonData)
        
        let user = try response.map(GitHubUser.self, atKeyPath: "user")
        XCTAssertEqual(user.login, "testuser")
        XCTAssertEqual(user.id, 123)
    }
    
    func testMapDecodableWithInvalidJSON() {
        let invalidData = "not json".data(using: .utf8)!
        let response = RawResponse(statusCode: 200, data: invalidData)
        
        XCTAssertThrowsError(try response.map(GitHubUser.self)) { error in
            guard case IrisError.objectMapping = error else {
                XCTFail("Expected objectMapping error")
                return
            }
        }
    }
    
    func testMapDecodableWithEmptyDataFailsOnEmptyDataFalse() throws {
        let response = RawResponse(statusCode: 200, data: Data())
        
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
        let response = RawResponse(statusCode: 200, data: jsonData)
        
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
        let response = RawResponse(statusCode: 200, data: data)
        let probe = try response.map(Probe.self)
        
        XCTAssertEqual(probe.userName, "ada")
    }
    
    // MARK: - Image Mapping Tests
    
    func testMapImageWithValidImageData() throws {
        let response = RawResponse(statusCode: 200, data: testImageData)
        
        let image = try response.mapImage()
        XCTAssertNotNil(image)
    }
    
    func testMapImageWithInvalidData() {
        let invalidData = "not an image".data(using: .utf8)!
        let response = RawResponse(statusCode: 200, data: invalidData)
        
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
        let response = RawResponse(statusCode: 200, data: data)
        
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
        
        XCTAssertEqual(response.model?.login, "test")
        XCTAssertEqual(response.model?.id, 1)
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
    
    func testResponseUnwrapThrowsWhenModelIsNil() {
        let response = Response<GitHubUser>(
            model: nil,
            statusCode: 200,
            data: Data(),
            request: nil,
            response: nil
        )
        
        XCTAssertThrowsError(try response.unwrap()) { error in
            guard case IrisError.objectMapping = error else {
                XCTFail("Expected objectMapping error")
                return
            }
        }
    }
    
    func testAsRawConversion() {
        let user = GitHubUser(login: "test", id: 1)
        let data = "test".data(using: .utf8)!
        let response = Response<GitHubUser>(
            model: user,
            statusCode: 200,
            data: data,
            request: nil,
            response: nil
        )
        
        let rawResponse = response.asRaw()
        XCTAssertEqual(rawResponse.statusCode, 200)
        XCTAssertEqual(rawResponse.data, data)
        XCTAssertNil(rawResponse.model)
    }
    
    // MARK: - Array Mapping at KeyPath Tests
    
    func testMapArrayAtKeyPath() throws {
        let jsonData = "{\"users\": [{\"login\": \"user1\", \"id\": 1}, {\"login\": \"user2\", \"id\": 2}]}".data(using: .utf8)!
        let response = RawResponse(statusCode: 200, data: jsonData)
        
        let users = try response.map([GitHubUser].self, atKeyPath: "users")
        XCTAssertEqual(users.count, 2)
        XCTAssertEqual(users[0].login, "user1")
        XCTAssertEqual(users[1].login, "user2")
    }
    
    // MARK: - Scalar Value at KeyPath Tests
    
    func testMapScalarAtKeyPath() throws {
        let jsonData = "{\"count\": 42}".data(using: .utf8)!
        let response = RawResponse(statusCode: 200, data: jsonData)
        
        let count = try response.map(Int.self, atKeyPath: "count")
        XCTAssertEqual(count, 42)
    }
    
    // MARK: - Deep Nested KeyPath Tests
    
    func testMapDeepNestedKeyPath() throws {
        let jsonData = "{\"data\": {\"user\": {\"profile\": {\"login\": \"nested\", \"id\": 999}}}}".data(using: .utf8)!
        let response = RawResponse(statusCode: 200, data: jsonData)
        
        let user = try response.map(GitHubUser.self, atKeyPath: "data.user.profile")
        XCTAssertEqual(user.login, "nested")
        XCTAssertEqual(user.id, 999)
    }
}
