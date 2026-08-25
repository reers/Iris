//
//  IrisTests.swift
//  IrisTests
//
//  Core integration tests and API usage examples.
//

import XCTest
@testable import Iris

// MARK: - Test Models

/// A simple user model for testing.
struct User: Codable, Equatable {
    let id: Int
    let name: String
}

/// A post model for testing.
struct Post: Codable {
    let id: Int
    let title: String
    let content: String
}

// MARK: - API Definition Examples (Iris Style - All configuration in one place!)

extension Call {
    
    /// Fetches a single user by ID.
    static func getUser(id: Int) -> Call<User> {
        .init()
            .path("/users/\(id)")
            .method(.get)
            .validateSuccessCodes()
    }
    
    /// Fetches a paginated list of users.
    static func getUsers(page: Int, limit: Int) -> Call<[User]> {
        .init()
            .path("/users")
            .query(["page": page, "limit": limit])
    }
    
    /// Creates a new user.
    static func createUser(name: String) -> Call<User> {
        .init()
            .path("/users")
            .method(.post)
            .body(["name": name])
            .validateSuccessCodes()
    }
    
    /// Uploads a user avatar image.
    static func uploadAvatar(userId: Int, imageData: Data) -> Call<User> {
        .init()
            .path("/users/\(userId)/avatar")
            .method(.post)
            .upload(multipart: [
                MultipartFormBodyPart(
                    provider: .data(imageData),
                    name: "avatar",
                    fileName: "avatar.jpg",
                    mimeType: "image/jpeg"
                )
            ])
            .timeout(60)
    }
    
    /// Creates a stubbed request for testing.
    static func getUserWithStub(id: Int) -> Call<User> {
        .init()
            .path("/users/\(id)")
            .stub(User(id: id, name: "Stubbed User"))
            .stub(behavior: .immediate)
    }
}

// MARK: - Tests

final class IrisTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Configure global settings
        Iris.configure(
            IrisConfiguration()
                .baseURL("https://api.example.com")
                .header("Accept", "application/json")
                .timeout(30)
                .stub(.immediate) // Use stub mode for testing
        )
    }
    
    override func tearDown() {
        Iris.configuration = IrisConfiguration()
        super.tearDown()
    }
    
    // MARK: - Response Tests
    
    func testResponse() async throws {
        // fire() returns Response<User>
        let response = try await Call<User>.getUserWithStub(id: 123).fire()
        
        // model is optional but guaranteed to have a value on successful fire()
        XCTAssertNotNil(response.model)
        XCTAssertEqual(response.model?.id, 123)
        XCTAssertEqual(response.model?.name, "Stubbed User")
        
        // Use unwrap() to get non-optional value
        let user = try response.unwrap()
        XCTAssertEqual(user.id, 123)
        
        // Other properties
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertTrue(response.isSuccess)
    }
    
    func testFetchConvenience() async throws {
        // fetch() returns Model directly (non-optional)
        let user = try await Call<User>.getUserWithStub(id: 456).fetch()
        
        XCTAssertEqual(user.id, 456)
        XCTAssertEqual(user.name, "Stubbed User")
    }
    
    // MARK: - Request Chaining Tests
    
    func testRequestChaining() {
        let request = Call<User>()
            .path("/test")
            .method(.post)
            .header("X-Custom", "value")
            .body(["key": "value"])
            .timeout(60)
            .validateSuccessCodes()
        
        XCTAssertEqual(request.path, "/test")
        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(request.headers?["X-Custom"], "value")
        XCTAssertEqual(request.timeout, 60)
        XCTAssertEqual(request.validationType, .successCodes)
    }
    
    // MARK: - Empty Response Tests
    
    func testEmpty() async throws {
        let request = Call
            .plain()
            .path("/ping")
            .stub(behavior: .immediate)
        
        let response = try await request.fire()
        XCTAssertTrue(response.isSuccess)
    }
    
    // MARK: - Response Mapping Tests
    
    func testResponseMapping() async throws {
        let response = try await Call<User>.getUserWithStub(id: 1).fire()
        
        // Map to string
        let string = try response.mapString()
        XCTAssertNotNil(string)
        
        // Map to JSON
        let json = try response.mapJSON()
        XCTAssertNotNil(json)
        
        // Map to another type
        let user = try response.map(User.self)
        XCTAssertEqual(user.name, "Stubbed User")
    }
    
    func testResponseConvenienceProperties() async throws {
        let response = try await Call<User>.getUserWithStub(id: 1).fire()
        
        // Test convenience properties
        XCTAssertTrue(response.isSuccess)
        XCTAssertFalse(response.isRedirect)
        XCTAssertFalse(response.isClientError)
        XCTAssertFalse(response.isServerError)
        
        // Filter status codes
        let filtered = try response.filterSuccessfulStatusCodes()
        XCTAssertEqual(filtered.statusCode, 200)
    }
    
    // MARK: - RawResponse Tests
    
    func testRawResponse() async throws {
        let response = try await Call<User>.getUserWithStub(id: 1).fire()
        
        // Convert to RawResponse (Response<Never>)
        let raw: RawResponse = response.asRaw()
        XCTAssertEqual(raw.statusCode, 200)
        XCTAssertTrue(raw.isSuccess)
        XCTAssertNil(raw.model)  // RawResponse's model is always nil
        
        // RawResponse has the same mapping methods
        let user = try raw.map(User.self)
        XCTAssertEqual(user.name, "Stubbed User")
    }
    
    // MARK: - GitHub API Tests (Iris Style - No enum needed!)
    
    func testGitHubZenStub() async throws {
        // Iris style: Build request directly without declaring a TargetType enum
        let response = try await Call<Empty>()
            .baseURL("https://api.github.com")
            .path("/zen")
            .method(.get)
            .stub("Half measures are as bad as nothing at all.".data(using: .utf8)!)
            .stub(behavior: .immediate)
            .fire()
        
        let message = try response.mapString()
        XCTAssertEqual(message, "Half measures are as bad as nothing at all.")
    }
    
    func testGitHubUserProfileStub() async throws {
        // Using GitHubAPI factory methods (demonstrates Iris's recommended API encapsulation)
        Iris.configure(IrisConfiguration().stub(.immediate))
        
        let response = try await GitHubAPI.userProfile("ashfurrow").fire()
        
        XCTAssertEqual(response.model?.login, "ashfurrow")
        XCTAssertEqual(response.model?.id, 100)
    }
    
    // MARK: - Validation Tests
    
    func testValidationWithSuccessStatusCode() async throws {
        let response = try await Call<User>()
            .path("/users/1")
            .validateSuccessCodes()
            .stub(User(id: 1, name: "Test"))
            .fire()
        
        // Should succeed with 200
        XCTAssertEqual(response.statusCode, 200)
    }
    
    // MARK: - Multiple Plugins Tests
    
    func testMultiplePlugins() async throws {
        let plugin1 = TestingPlugin()
        let plugin2 = OrderTrackingPlugin()
        
        Iris.configure(
            IrisConfiguration()
                .baseURL("https://api.example.com")
                .stub(.immediate)
                .plugin(plugin1)
                .plugin(plugin2)
        )
        
        _ = try await Call<User>()
            .path("/users/1")
            .stub(User(id: 1, name: "Test"))
            .fire()
        
        // Both plugins should be called
        // Note: In stub mode, `prepare` is not called (no real URLRequest to prepare)
        // So only willSend, didReceive, and process are called
        XCTAssertEqual(plugin1.willSendCalledCount, 1)
        XCTAssertEqual(plugin1.didReceiveCalledCount, 1)
        XCTAssertEqual(plugin2.callOrder.count, 3) // willSend, didReceive, process (no prepare in stub mode)
        XCTAssertEqual(plugin2.callOrder, ["willSend", "didReceive", "process"])
    }
}

// MARK: - Usage Examples

/*
 
 ╔════════════════════════════════════════════════════════════════╗
 ║                    Iris Usage Patterns                         ║
 ╚════════════════════════════════════════════════════════════════╝
 
 ## API Definition (All configuration in one place!)
 
 extension Call {
     static func getUser(id: Int) -> Call<User> {
         .init()
             .path("/users/\(id)")
             .method(.get)
             .validateSuccessCodes()
     }
 }
 
 ## Sending Requests
 
 // Method 1: fire() - Returns Response<Model>
 let response = try await Call<User>.getUser(id: 123).fire()
 let user = response.model!          // model is optional
 let user = try response.unwrap()    // or use unwrap()
 
 // Method 2: fetch() - Returns Model directly (recommended)
 let user = try await Call<User>.getUser(id: 123).fetch()
 
 ## Type Structure
 
 - Response<Model>: Generic response type
   - model: Model? (optional, has value on successful fire())
   - statusCode, data, isSuccess, etc.
 - RawResponse = Response<Never>: Response without model (used in plugins)
 
 */
