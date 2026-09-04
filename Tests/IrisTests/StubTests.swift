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
            .send()
        
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(response.model.login, "testuser")
        XCTAssertEqual(response.model.id, 123)
    }
    
    func testStubCanReturnCustomStatusCode() async throws {
        let sampleData = "{\"login\": \"created\", \"id\": 201}".data(using: .utf8)!
        
        let response = try await Call<GitHubUser>()
            .path("/users/created")
            .stub(statusCode: 201, data: sampleData)
            .send()
        
        XCTAssertEqual(response.statusCode, 201)
        XCTAssertEqual(response.model.login, "created")
    }
    
    func testStubValidationFailsForCustomStatusCode() async {
        let sampleData = "{\"message\": \"missing\"}".data(using: .utf8)!
        
        do {
            _ = try await Call<Empty>()
                .path("/users/missing")
                .validateSuccessCodes()
                .stub(statusCode: 404, data: sampleData)
                .send()
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
                .send()
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
            .send()
        
        XCTAssertEqual(response.model.login, "stubuser")
        XCTAssertEqual(response.model.id, 456)
    }
    
    func testStubFromString() async throws {
        let response = try await Call<GitHubUser>()
            .path("/users/stringuser")
            .stub("{\"login\": \"stringuser\", \"id\": 789}")
            .send()
        
        XCTAssertEqual(response.model.login, "stringuser")
        XCTAssertEqual(response.model.id, 789)
    }
    
    // MARK: - Delayed Stub Tests
    
    func testDelayedStub() async throws {
        let delay: TimeInterval = 0.5
        let startTime = Date()
        
        let response = try await Call<GitHubUser>()
            .path("/users/delayed")
            .stub(GitHubUser(login: "delayed", id: 1))
            .stub(behavior: .delayed(delay))
            .send()
        
        let elapsedTime = Date().timeIntervalSince(startTime)
        
        XCTAssertEqual(response.model.login, "delayed")
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
            .send()
        
        let elapsedTime = Date().timeIntervalSince(startTime)
        
        XCTAssertEqual(response.model.login, "globaldelayed")
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
            .send()
        
        let elapsedTime = Date().timeIntervalSince(startTime)
        
        XCTAssertEqual(response.model.login, "override")
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
            .send()
        
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
            .empty()
            .path("/ping")
            .stub(Data())
            .send()
        
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertTrue(response.isSuccess)
    }
    
    func testRawDataResponseReturnsBodyWithoutJSONDecoding() async throws {
        let sampleData = Data([0x00, 0xFF, 0x10, 0x20])
        
        let response = try await Call.data()
            .path("/v1/shield")
            .stub(sampleData)
            .send()
        
        XCTAssertEqual(response.model, sampleData)
        XCTAssertEqual(response.data, sampleData)
        XCTAssertEqual(try response.unwrap(), sampleData)
    }
    
    func testRawDataFetchReturnsJSONObjectBytes() async throws {
        let json = #"{"ok":true}"#.data(using: .utf8)!
        
        let data = try await Call<Data>()
            .path("/v1/configs")
            .stub(json)
            .fetch()
        
        XCTAssertEqual(data, json)
    }
    
    func testRawDataFetchAllowsEmptyBody() async throws {
        let data = try await Call.data()
            .path("/v1/like")
            .stub(Data())
            .fetch()
        
        XCTAssertEqual(data, Data())
    }
    
    func testRawStringResponseReturnsUTF8Body() async throws {
        let body = "Half measures are as bad as nothing at all."
        
        let text = try await Call.string()
            .path("/zen")
            .stub(body)
            .fetch()
        
        XCTAssertEqual(text, body)
    }
    
    func testRawStringDoesNotJSONDecode() async throws {
        let jsonObject = #"{"ok":true}"#
        
        let text = try await Call<String>()
            .path("/v1/void")
            .stub(jsonObject)
            .fetch()
        
        XCTAssertEqual(text, jsonObject)
    }
    
    func testSendCompletionDeliversSuccess() {
        let expectation = XCTestExpectation(description: "send completion success")
        let sampleData = "{\"login\": \"testuser\", \"id\": 123}".data(using: .utf8)!
        
        Call<GitHubUser>()
            .path("/users/testuser")
            .stub(sampleData)
            .send { result in
                switch result {
                case .success(let response):
                    XCTAssertEqual(response.model.login, "testuser")
                    XCTAssertEqual(response.model.id, 123)
                case .failure(let error):
                    XCTFail("Unexpected failure: \(error)")
                }
                expectation.fulfill()
            }
        
        wait(for: [expectation], timeout: 1)
    }
    
    func testFetchCompletionDeliversModel() {
        let expectation = XCTestExpectation(description: "fetch completion success")
        let sampleData = "{\"login\": \"testuser\", \"id\": 123}".data(using: .utf8)!
        
        Call<GitHubUser>()
            .path("/users/testuser")
            .stub(sampleData)
            .fetch { result in
                switch result {
                case .success(let user):
                    XCTAssertEqual(user.login, "testuser")
                case .failure(let error):
                    XCTFail("Unexpected failure: \(error)")
                }
                expectation.fulfill()
            }
        
        wait(for: [expectation], timeout: 1)
    }
    
    func testSendCompletionDeliversFailure() {
        let expectation = XCTestExpectation(description: "send completion failure")
        
        Call<GitHubUser>()
            .path("/users/testuser")
            .validateSuccessCodes()
            .stub(statusCode: 500, data: Data())
            .send { result in
                if case .failure(.statusCode(let response)) = result {
                    XCTAssertEqual(response.statusCode, 500)
                } else {
                    XCTFail("Expected statusCode failure")
                }
                expectation.fulfill()
            }
        
        wait(for: [expectation], timeout: 1)
    }
    
    func testStubUploadProgressFiresBeforeCompletion() {
        let progressExpectation = XCTestExpectation(description: "upload progress")
        let completionExpectation = XCTestExpectation(description: "send completion")
        
        Call.data()
            .path("/v1/media")
            .stub(Data([0x01]))
            .onUploadProgress { progress in
                XCTAssertEqual(progress.fractionCompleted, 1)
                progressExpectation.fulfill()
            }
            .send { result in
                XCTAssertNotNil(try? result.get())
                completionExpectation.fulfill()
            }
        
        wait(for: [progressExpectation, completionExpectation], timeout: 1)
    }
    
    func testStubStreamDeliversChunkThenCompletion() {
        let chunkExpectation = XCTestExpectation(description: "chunk")
        let completionExpectation = XCTestExpectation(description: "completion")
        let payload = #"{"token":"hi"}"#.data(using: .utf8)!
        
        Call.data()
            .path("/v1/ai")
            .stub(payload)
            .stream()
            .onChunk { data in
                XCTAssertEqual(data, payload)
                chunkExpectation.fulfill()
            }
            .send { result in
                XCTAssertEqual(try? result.get().model, payload)
                completionExpectation.fulfill()
            }
        
        wait(for: [chunkExpectation, completionExpectation], timeout: 1)
    }
    
    func testSendScopeReturnsValue() async throws {
        let sampleData = "{\"login\": \"testuser\", \"id\": 123}".data(using: .utf8)!
        
        let response = try await Call<GitHubUser>()
            .path("/users/testuser")
            .stub(sampleData)
            .send { _ in }
        
        XCTAssertEqual(response.model.login, "testuser")
        XCTAssertEqual(response.model.id, 123)
    }
    
    func testSendScopeProgressThenValue() async throws {
        var fractions: [Double] = []
        
        let response = try await Call.data()
            .path("/v1/media")
            .stub(Data([0x01]))
            .send { session in
                for await progress in session.uploadProgress {
                    fractions.append(progress.fractionCompleted)
                }
            }
        
        XCTAssertEqual(fractions, [1])
        XCTAssertEqual(response.model, Data([0x01]))
    }
    
    func testSendScopeProgressAlongsideValue() async throws {
        var fractions: [Double] = []
        
        let response = try await Call.data()
            .path("/v1/media")
            .stub(Data([0x01]))
            .send { session in
                async let _ = session.value
                for await progress in session.uploadProgress {
                    fractions.append(progress.fractionCompleted)
                }
            }
        
        XCTAssertEqual(fractions, [1])
        XCTAssertEqual(response.model, Data([0x01]))
    }
    
    func testSendScopeChunksThenValue() async throws {
        let payload = #"{"token":"hi"}"#.data(using: .utf8)!
        var chunks: [Data] = []
        
        let response = try await Call.data()
            .path("/v1/ai")
            .stub(payload)
            .stream()
            .send { session in
                for await chunk in session.chunks {
                    chunks.append(chunk)
                }
            }
        
        XCTAssertEqual(chunks, [payload])
        XCTAssertEqual(response.model, payload)
    }
    
    func testSendScopeAndHandlerBothReceiveProgress() async throws {
        let handlerCount = SendableBox(0)
        var streamCount = 0
        
        _ = try await Call.data()
            .path("/v1/media")
            .stub(Data([0x01]))
            .onUploadProgress { _ in
                handlerCount.value += 1
            }
            .send { session in
                for await _ in session.uploadProgress {
                    streamCount += 1
                }
            }
        
        XCTAssertEqual(handlerCount.value, 1)
        XCTAssertEqual(streamCount, 1)
    }
    
    func testSendScopeEmptyBodyStillReturnsResponse() async throws {
        let completeCount = SendableBox(0)
        
        let response = try await Call<GitHubUser>()
            .path("/users/testuser")
            .stub(GitHubUser(login: "testuser", id: 1))
            .onComplete { _ in
                completeCount.value += 1
            }
            .send { _ in }
        
        XCTAssertEqual(response.model.login, "testuser")
        XCTAssertEqual(completeCount.value, 1)
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
            .send()
        
        XCTAssertEqual(response.model.count, 3)
        XCTAssertEqual(response.model[0].login, "user1")
        XCTAssertEqual(response.model[1].login, "user2")
        XCTAssertEqual(response.model[2].login, "user3")
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
            .send()
        
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
            .send()
        
        // Plugin modifies status code to 201
        XCTAssertEqual(response.statusCode, 201)
    }
    
    // MARK: - Response Mapping Tests
    
    func testStubResponseCanBeFiltered() async throws {
        let response = try await Call<GitHubUser>()
            .path("/users/filter")
            .stub(GitHubUser(login: "filter", id: 1))
            .send()
        
        // Should not throw since status code is 200
        let filtered = try response.filterSuccessfulStatusCodes()
        XCTAssertEqual(filtered.statusCode, 200)
    }
    
    func testStubResponseCanBeMappedToJSON() async throws {
        let response = try await Call<GitHubUser>()
            .path("/users/json")
            .stub(GitHubUser(login: "json", id: 1))
            .send()
        
        let json = try response.mapJSON() as? [String: Any]
        XCTAssertEqual(json?["login"] as? String, "json")
        XCTAssertEqual(json?["id"] as? Int, 1)
    }
    
    func testStubResponseCanBeMappedToString() async throws {
        let response = try await Call<GitHubUser>()
            .path("/users/string")
            .stub("{\"login\": \"string\", \"id\": 1}")
            .send()
        
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
            .send()
        
        XCTAssertEqual(response.model.login, "newuser")
    }
    
    func testStubWorksWithPutMethod() async throws {
        let response = try await Call<GitHubUser>()
            .path("/users/1")
            .method(.put)
            .body(["name": "updateduser"])
            .stub(GitHubUser(login: "updateduser", id: 1))
            .send()
        
        XCTAssertEqual(response.model.login, "updateduser")
    }
    
    func testStubWorksWithDeleteMethod() async throws {
        let response = try await Call<Empty>()
            .path("/users/1")
            .method(.delete)
            .stub(Data())
            .send()
        
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
            .send()
        
        XCTAssertEqual(response.model.login, "customdecoder")
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
            .send()
        
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
                .send()
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
            .send()
        
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
            .send()
        
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
            .send()
        
        await fulfillment(of: [expectation], timeout: 1.0)
        
        XCTAssertNotNil(completedAt.value)
        let elapsed = completedAt.value!.timeIntervalSince(startTime)
        XCTAssertGreaterThanOrEqual(elapsed, delay * 0.9)
    }
}
