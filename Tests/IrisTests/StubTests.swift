//
//  StubTests.swift
//  IrisTests
//
//  Integration tests for stub mode.
//

import XCTest
@testable import Iris

final class StubTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        Iris.configuration = IrisConfiguration()
            .baseURL("https://api.example.com")
            .stub(.immediate)
    }
    
    override func tearDown() {
        Iris.configuration = IrisConfiguration()
        super.tearDown()
    }
    
    // MARK: - Basic Stub Tests
    
    func testImmediateStubReturnsData() async throws {
        let sampleData = "{\"login\": \"testuser\", \"id\": 123}".data(using: .utf8)!
        
        let response = try await Call<GitHubUser>()
            .path("/users/testuser")
            .stub(sampleData)
            .fire()
        
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(response.model?.login, "testuser")
        XCTAssertEqual(response.model?.id, 123)
    }
    
    func testStubCanReturnCustomStatusCode() async throws {
        let sampleData = "{\"login\": \"created\", \"id\": 201}".data(using: .utf8)!
        
        let response = try await Call<GitHubUser>()
            .path("/users/created")
            .stub(statusCode: 201, data: sampleData)
            .fire()
        
        XCTAssertEqual(response.statusCode, 201)
        XCTAssertEqual(response.model?.login, "created")
    }
    
    func testStubValidationFailsForCustomStatusCode() async {
        let sampleData = "{\"message\": \"missing\"}".data(using: .utf8)!
        
        do {
            _ = try await Call<Empty>()
                .path("/users/missing")
                .validateSuccessCodes()
                .stub(statusCode: 404, data: sampleData)
                .fire()
            XCTFail("Expected statusCode error")
        } catch {
            guard let irisError = error as? IrisError, case .statusCode(let response) = irisError else {
                XCTFail("Expected statusCode error, got \(error)")
                return
            }
            XCTAssertEqual(response.statusCode, 404)
            XCTAssertEqual(response.data, sampleData)
        }
    }
    
    func testStubCanReturnNetworkError() async {
        let networkError = NSError(domain: "Stub", code: -1009)
        
        do {
            _ = try await Call<Empty>()
                .path("/users/offline")
                .stub(error: networkError)
                .fire()
            XCTFail("Expected underlying error")
        } catch {
            guard let irisError = error as? IrisError, case .underlying(let underlying, nil) = irisError else {
                XCTFail("Expected underlying error without response, got \(error)")
                return
            }
            XCTAssertEqual((underlying as NSError).domain, "Stub")
        }
    }
    
    func testStubFromEncodable() async throws {
        let user = GitHubUser(login: "stubuser", id: 456)
        
        let response = try await Call<GitHubUser>()
            .path("/users/stubuser")
            .stub(user)
            .fire()
        
        XCTAssertEqual(response.model?.login, "stubuser")
        XCTAssertEqual(response.model?.id, 456)
    }
    
    func testStubFromString() async throws {
        let response = try await Call<GitHubUser>()
            .path("/users/stringuser")
            .stub("{\"login\": \"stringuser\", \"id\": 789}")
            .fire()
        
        XCTAssertEqual(response.model?.login, "stringuser")
        XCTAssertEqual(response.model?.id, 789)
    }
    
    // MARK: - Delayed Stub Tests
    
    func testDelayedStub() async throws {
        let delay: TimeInterval = 0.5
        let startTime = Date()
        
        let response = try await Call<GitHubUser>()
            .path("/users/delayed")
            .stub(GitHubUser(login: "delayed", id: 1))
            .stub(behavior: .delayed(delay))
            .fire()
        
        let elapsedTime = Date().timeIntervalSince(startTime)
        
        XCTAssertEqual(response.model?.login, "delayed")
        XCTAssertGreaterThanOrEqual(elapsedTime, delay * 0.9) // Allow some tolerance
    }
    
    func testDelayedStubWithGlobalConfiguration() async throws {
        let delay: TimeInterval = 0.3
        Iris.configure(
            IrisConfiguration()
                .baseURL("https://api.example.com")
                .stub(.delayed(delay))
        )
        
        let startTime = Date()
        
        let response = try await Call<GitHubUser>()
            .path("/users/globaldelayed")
            .stub(GitHubUser(login: "globaldelayed", id: 2))
            .fire()
        
        let elapsedTime = Date().timeIntervalSince(startTime)
        
        XCTAssertEqual(response.model?.login, "globaldelayed")
        XCTAssertGreaterThanOrEqual(elapsedTime, delay * 0.9)
    }
    
    // MARK: - Local Stub Override Tests
    
    func testLocalStubBehaviorOverridesGlobal() async throws {
        // Global: delayed
        Iris.configure(
            IrisConfiguration()
                .baseURL("https://api.example.com")
                .stub(.delayed(1.0))
        )
        
        // Local: immediate
        let startTime = Date()
        
        let response = try await Call<GitHubUser>()
            .path("/users/override")
            .stub(GitHubUser(login: "override", id: 3))
            .stub(behavior: .immediate)
            .fire()
        
        let elapsedTime = Date().timeIntervalSince(startTime)
        
        XCTAssertEqual(response.model?.login, "override")
        XCTAssertLessThan(elapsedTime, 0.5) // Should be much faster than 1.0s
    }
    
    // MARK: - Fetch Convenience Tests
    
    func testFetchReturnsModel() async throws {
        let user = try await Call<GitHubUser>()
            .path("/users/fetchuser")
            .stub(GitHubUser(login: "fetchuser", id: 100))
            .fetch()
        
        XCTAssertEqual(user.login, "fetchuser")
        XCTAssertEqual(user.id, 100)
    }
    
    // MARK: - Response Properties Tests
    
    func testStubResponseHasCorrectProperties() async throws {
        let sampleData = "{\"login\": \"propuser\", \"id\": 200}".data(using: .utf8)!
        
        let response = try await Call<GitHubUser>()
            .path("/users/propuser")
            .stub(sampleData)
            .fire()
        
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertTrue(response.isSuccess)
        XCTAssertFalse(response.isRedirect)
        XCTAssertFalse(response.isClientError)
        XCTAssertFalse(response.isServerError)
        XCTAssertEqual(response.data, sampleData)
    }
    
    // MARK: - Empty Response Tests
    
    func testEmptyResponseStub() async throws {
        let response = try await Call<Empty>
            .plain()
            .path("/ping")
            .stub(Data())
            .fire()
        
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertTrue(response.isSuccess)
    }
    
    // MARK: - Array Response Tests
    
    func testArrayResponseStub() async throws {
        let users = [
            GitHubUser(login: "user1", id: 1),
            GitHubUser(login: "user2", id: 2),
            GitHubUser(login: "user3", id: 3)
        ]
        
        let encoder = JSONEncoder()
        let sampleData = try encoder.encode(users)
        
        let response = try await Call<[GitHubUser]>()
            .path("/users")
            .stub(sampleData)
            .fire()
        
        XCTAssertEqual(response.model?.count, 3)
        XCTAssertEqual(response.model?[0].login, "user1")
        XCTAssertEqual(response.model?[1].login, "user2")
        XCTAssertEqual(response.model?[2].login, "user3")
    }
    
    // MARK: - Plugin Integration Tests
    
    func testPluginsAreCalledDuringStub() async throws {
        let plugin = TestingPlugin()
        
        Iris.configure(
            IrisConfiguration()
                .baseURL("https://api.example.com")
                .stub(.immediate)
                .plugin(plugin)
        )
        
        _ = try await Call<GitHubUser>()
            .path("/users/plugintest")
            .stub(GitHubUser(login: "plugintest", id: 1))
            .fire()
        
        XCTAssertEqual(plugin.willSendCalledCount, 1)
        XCTAssertEqual(plugin.didReceiveCalledCount, 1)
        XCTAssertEqual(plugin.processCalledCount, 1)
    }
    
    func testPluginCanModifyStubResponse() async throws {
        let plugin = ResponseModifyingPlugin(newStatusCode: 201)
        
        Iris.configure(
            IrisConfiguration()
                .baseURL("https://api.example.com")
                .stub(.immediate)
                .plugin(plugin)
        )
        
        let response = try await Call<GitHubUser>()
            .path("/users/modified")
            .stub(GitHubUser(login: "modified", id: 1))
            .fire()
        
        // Plugin modifies status code to 201
        XCTAssertEqual(response.statusCode, 201)
    }
    
    // MARK: - Response Mapping Tests
    
    func testStubResponseCanBeFiltered() async throws {
        let response = try await Call<GitHubUser>()
            .path("/users/filter")
            .stub(GitHubUser(login: "filter", id: 1))
            .fire()
        
        // Should not throw since status code is 200
        let filtered = try response.filterSuccessfulStatusCodes()
        XCTAssertEqual(filtered.statusCode, 200)
    }
    
    func testStubResponseCanBeMappedToJSON() async throws {
        let response = try await Call<GitHubUser>()
            .path("/users/json")
            .stub(GitHubUser(login: "json", id: 1))
            .fire()
        
        let json = try response.mapJSON() as? [String: Any]
        XCTAssertEqual(json?["login"] as? String, "json")
        XCTAssertEqual(json?["id"] as? Int, 1)
    }
    
    func testStubResponseCanBeMappedToString() async throws {
        let response = try await Call<GitHubUser>()
            .path("/users/string")
            .stub("{\"login\": \"string\", \"id\": 1}")
            .fire()
        
        let string = try response.mapString()
        XCTAssertTrue(string.contains("string"))
    }
    
    // MARK: - Different Request Methods Tests
    
    func testStubWorksWithPostMethod() async throws {
        let response = try await Call<GitHubUser>()
            .path("/users")
            .method(.post)
            .body(["name": "newuser"])
            .stub(GitHubUser(login: "newuser", id: 999))
            .fire()
        
        XCTAssertEqual(response.model?.login, "newuser")
    }
    
    func testStubWorksWithPutMethod() async throws {
        let response = try await Call<GitHubUser>()
            .path("/users/1")
            .method(.put)
            .body(["name": "updateduser"])
            .stub(GitHubUser(login: "updateduser", id: 1))
            .fire()
        
        XCTAssertEqual(response.model?.login, "updateduser")
    }
    
    func testStubWorksWithDeleteMethod() async throws {
        let response = try await Call<Empty>()
            .path("/users/1")
            .method(.delete)
            .stub(Data())
            .fire()
        
        XCTAssertTrue(response.isSuccess)
    }
    
    // MARK: - Custom Decoder Tests
    
    func testStubWithCustomDecoder() async throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        let jsonData = "{\"login\": \"customdecoder\", \"id\": 1}".data(using: .utf8)!
        
        let response = try await Call<GitHubUser>()
            .path("/users/customdecoder")
            .stub(jsonData)
            .decoder(decoder)
            .fire()
        
        XCTAssertEqual(response.model?.login, "customdecoder")
    }
    
    // MARK: - OnComplete Handler Tests
    
    func testOnCompleteIsCalledWithDecodedModel() async throws {
        let expectation = XCTestExpectation(description: "onComplete called")
        let receivedModel = SendableBox<GitHubUser?>(nil)
        
        _ = try await Call<GitHubUser>()
            .path("/users/oncomplete")
            .stub(GitHubUser(login: "oncomplete", id: 123))
            .onComplete { response in
                if case .success(let model) = response.result {
                    receivedModel.value = model
                }
                expectation.fulfill()
            }
            .fire()
        
        await fulfillment(of: [expectation], timeout: 1.0)
        
        XCTAssertNotNil(receivedModel.value)
        XCTAssertEqual(receivedModel.value?.login, "oncomplete")
        XCTAssertEqual(receivedModel.value?.id, 123)
    }
    
    func testOnCompleteIsCalledOnSuccess() async throws {
        let expectation = XCTestExpectation(description: "onComplete called on success")
        let wasSuccess = SendableBox(false)
        
        _ = try await Call<GitHubUser>()
            .path("/users/success")
            .stub(GitHubUser(login: "success", id: 1))
            .onComplete { response in
                if case .success = response.result {
                    wasSuccess.value = true
                }
                expectation.fulfill()
            }
            .fetch()
        
        await fulfillment(of: [expectation], timeout: 1.0)
        
        XCTAssertTrue(wasSuccess.value)
    }
    
    func testOnCompleteIsCalledOnDecodingFailure() async throws {
        let expectation = XCTestExpectation(description: "onComplete called on failure")
        let wasFailure = SendableBox(false)
        
        // Invalid JSON that won't decode to GitHubUser
        let invalidData = "not valid json".data(using: .utf8)!
        
        do {
            _ = try await Call<GitHubUser>()
                .path("/users/invalid")
                .stub(invalidData)
                .onComplete { response in
                    if case .failure = response.result {
                        wasFailure.value = true
                    }
                    expectation.fulfill()
                }
                .fire()
            XCTFail("Expected decoding to fail")
        } catch {
            // Expected
        }
        
        await fulfillment(of: [expectation], timeout: 1.0)
        
        XCTAssertTrue(wasFailure.value)
    }
    
    func testOnCompleteCanSaveToDatabase() async throws {
        // Simulates a real-world use case: saving to database on completion
        let savedUsers = SendableArray<GitHubUser>()
        
        let user1 = try await Call<GitHubUser>()
            .path("/users/user1")
            .stub(GitHubUser(login: "user1", id: 1))
            .onComplete { response in
                if case .success(let model) = response.result {
                    savedUsers.append(model)
                }
            }
            .fetch()
        
        let user2 = try await Call<GitHubUser>()
            .path("/users/user2")
            .stub(GitHubUser(login: "user2", id: 2))
            .onComplete { response in
                if case .success(let model) = response.result {
                    savedUsers.append(model)
                }
            }
            .fetch()
        
        XCTAssertEqual(user1.login, "user1")
        XCTAssertEqual(user2.login, "user2")
        XCTAssertEqual(savedUsers.count, 2)
        XCTAssertEqual(savedUsers[0].login, "user1")
        XCTAssertEqual(savedUsers[1].login, "user2")
    }
    
    func testOnCompleteReceivesResponseMetadata() async throws {
        let expectation = XCTestExpectation(description: "onComplete receives metadata")
        let receivedData = SendableBox<Data?>(nil)
        
        let stubData = "{\"login\": \"metadata\", \"id\": 999}".data(using: .utf8)!
        
        _ = try await Call<GitHubUser>()
            .path("/users/metadata")
            .stub(stubData)
            .onComplete { response in
                receivedData.value = response.data
                expectation.fulfill()
            }
            .fire()
        
        await fulfillment(of: [expectation], timeout: 1.0)
        
        XCTAssertEqual(receivedData.value, stubData)
    }
    
    func testOnCompleteWithArrayResponse() async throws {
        let expectation = XCTestExpectation(description: "onComplete with array")
        let receivedUsers = SendableBox<[GitHubUser]>([])
        
        let users = [
            GitHubUser(login: "array1", id: 1),
            GitHubUser(login: "array2", id: 2)
        ]
        let encoder = JSONEncoder()
        let stubData = try encoder.encode(users)
        
        _ = try await Call<[GitHubUser]>()
            .path("/users")
            .stub(stubData)
            .onComplete { response in
                if case .success(let models) = response.result {
                    receivedUsers.value = models
                }
                expectation.fulfill()
            }
            .fire()
        
        await fulfillment(of: [expectation], timeout: 1.0)
        
        XCTAssertEqual(receivedUsers.value.count, 2)
        XCTAssertEqual(receivedUsers.value[0].login, "array1")
        XCTAssertEqual(receivedUsers.value[1].login, "array2")
    }
    
    func testOnCompleteWithDelayedStub() async throws {
        let expectation = XCTestExpectation(description: "onComplete with delayed stub")
        let completedAt = SendableBox<Date?>(nil)
        let startTime = Date()
        let delay: TimeInterval = 0.3
        
        _ = try await Call<GitHubUser>()
            .path("/users/delayed")
            .stub(GitHubUser(login: "delayed", id: 1))
            .stub(behavior: .delayed(delay))
            .onComplete { _ in
                completedAt.value = Date()
                expectation.fulfill()
            }
            .fire()
        
        await fulfillment(of: [expectation], timeout: 1.0)
        
        XCTAssertNotNil(completedAt.value)
        let elapsed = completedAt.value!.timeIntervalSince(startTime)
        XCTAssertGreaterThanOrEqual(elapsed, delay * 0.9)
    }
}
