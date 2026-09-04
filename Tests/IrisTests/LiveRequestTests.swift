//
//  LiveRequestTests.swift
//  IrisTests
//
//  Alamofire / URLSession path. Uses StubURLProtocol so traffic still stays in-process.
//

import XCTest
@testable import Iris

final class LiveRequestTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        Iris.configure(
            IrisConfiguration()
                .baseURL("https://api.example.com")
                .session(makeStubbedSession())
        )
    }
    
    override func tearDown() {
        StubURLProtocol.reset()
        Iris.configuration = IrisConfiguration()
        super.tearDown()
    }
    
    func testSendDecodesJSONOverURLSession() async throws {
        let payload = #"{"login":"octocat","id":1}"#.data(using: .utf8)!
        stubBody(payload)
        
        let response = try await Call<GitHubUser>()
            .path("/users/octocat")
            .send()
        
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(response.model.login, "octocat")
        XCTAssertEqual(response.model.id, 1)
    }
    
    func testDownloadProgressHandlerFiresOverURLSession() async throws {
        let payload = Data(repeating: 0x61, count: 8)
        stubBody(payload, chunkSize: 2, chunkInterval: 0.01)
        
        let fractions = SendableArray<Double>()
        let response = try await Call.data()
            .path("/v1/media")
            .onDownloadProgress { progress in
                fractions.append(progress.fractionCompleted)
            }
            .send()
        
        XCTAssertEqual(response.model, payload)
        XCTAssertFalse(fractions.values.isEmpty)
        XCTAssertEqual(fractions.values.last, 1)
    }
    
    func testSendScopeDownloadProgressThenValue() async throws {
        let payload = Data(repeating: 0x62, count: 8)
        stubBody(payload, chunkSize: 2, chunkInterval: 0.01)
        
        var fractions: [Double] = []
        let response = try await Call.data()
            .path("/v1/media")
            .send { session in
                for await progress in session.downloadProgress {
                    fractions.append(progress.fractionCompleted)
                }
            }
        
        XCTAssertEqual(response.model, payload)
        XCTAssertFalse(fractions.isEmpty)
        XCTAssertEqual(fractions.last, 1)
    }
    
    func testStreamDeliversMultipleChunksThenDecodedValue() async throws {
        let payload = #"{"login":"octocat","id":1}"#.data(using: .utf8)!
        stubBody(payload, chunkSize: 8, chunkInterval: 0.01)
        
        var chunks: [Data] = []
        let response = try await Call<GitHubUser>()
            .path("/users/octocat")
            .stream()
            .send { session in
                for await chunk in session.chunks {
                    chunks.append(chunk)
                }
            }
        
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertEqual(chunks.reduce(into: Data()) { $0.append($1) }, payload)
        XCTAssertEqual(response.model.login, "octocat")
        XCTAssertEqual(response.model.id, 1)
    }
    
    func testHandlerAndSessionBothReceiveStreamChunks() async throws {
        let payload = Data(repeating: 0x63, count: 12)
        stubBody(payload, chunkSize: 4, chunkInterval: 0.01)
        
        let handlerChunks = SendableArray<Data>()
        var sessionChunks: [Data] = []
        
        let response = try await Call.data()
            .path("/v1/ai")
            .stream()
            .onChunk { data in
                handlerChunks.append(data)
            }
            .send { session in
                for await chunk in session.chunks {
                    sessionChunks.append(chunk)
                }
            }
        
        XCTAssertEqual(handlerChunks.values, sessionChunks)
        XCTAssertGreaterThan(sessionChunks.count, 1)
        XCTAssertEqual(sessionChunks.reduce(into: Data()) { $0.append($1) }, payload)
        XCTAssertEqual(response.model, payload)
    }
    
    func testCancellingSendScopeCancelsUnderlyingRequest() async {
        let didStartUnderlyingRequest = expectation(description: "Underlying request should start")
        let didCancelUnderlyingRequest = expectation(description: "Underlying request should be cancelled")
        StubURLProtocol.responseDelay = 5
        StubURLProtocol.onStartLoading = {
            didStartUnderlyingRequest.fulfill()
        }
        StubURLProtocol.onStopLoading = {
            didCancelUnderlyingRequest.fulfill()
        }
        stubBody(Data("{}".utf8))
        
        let task = _Concurrency.Task {
            try await Call<Empty>()
                .path("/slow")
                .send { session in
                    for await _ in session.downloadProgress {}
                }
        }
        
        await fulfillment(of: [didStartUnderlyingRequest], timeout: 1)
        task.cancel()
        await fulfillment(of: [didCancelUnderlyingRequest], timeout: 1)
    }
    
    private func stubBody(
        _ data: Data,
        statusCode: Int = 200,
        chunkSize: Int = 0,
        chunkInterval: TimeInterval = 0
    ) {
        StubURLProtocol.bodyChunkSize = chunkSize
        StubURLProtocol.bodyChunkInterval = chunkInterval
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": "application/json",
                    "Content-Length": "\(data.count)"
                ]
            )!
            return (response, data)
        }
    }
}
