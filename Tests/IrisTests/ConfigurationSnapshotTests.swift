//
//  ConfigurationSnapshotTests.swift
//  IrisTests
//
//  A request snapshots the global configuration when it starts. Replacing
//  `Iris.configuration` mid-flight must not affect requests already running,
//  and individual reads/writes of the global value are atomic.
//

import XCTest
@testable import Iris

final class ConfigurationSnapshotTests: XCTestCase {
    
    override func tearDown() {
        Iris.configuration = IrisConfiguration()
        super.tearDown()
    }
    
    /// Decoding must use the configuration captured when the request started,
    /// not whatever the global value happens to be at decode time.
    func testInFlightRequestDecodesWithSnapshotConfiguration() async throws {
        let snapshotDecoder = JSONDecoder()
        snapshotDecoder.dateDecodingStrategy = .secondsSince1970
        
        var config = IrisConfiguration().baseURL("https://api.example.com")
        config.jsonDecoder = snapshotDecoder
        Iris.configuration = config
        
        let json = #"{"title":"snapshot","createdAt":1000,"rating":null}"#.data(using: .utf8)!
        let task = _Concurrency.Task {
            try await Call<Issue>()
                .path("/issues/1")
                .stub(json)
                .stub(behavior: .delayed(0.3))
                .send()
        }
        
        // Let the request take its snapshot, then swap the global for a decoder
        // that would produce a different date (seconds since 2001-01-01).
        try await _Concurrency.Task.sleep(nanoseconds: 50_000_000)
        var swapped = IrisConfiguration().baseURL("https://api.example.com")
        swapped.jsonDecoder = JSONDecoder()
        Iris.configuration = swapped
        
        let response = try await task.value
        XCTAssertEqual(response.model.createdAt, Date(timeIntervalSince1970: 1000))
    }
    
    /// Plugins (willSend/didReceive/process) must come from the configuration
    /// captured at request start.
    func testInFlightRequestUsesSnapshotPlugins() async throws {
        let first = SendableBox(0)
        let second = SendableBox(0)
        
        Iris.configuration = IrisConfiguration()
            .baseURL("https://api.example.com")
            .plugin(CountingPlugin(box: first))
        
        let task = _Concurrency.Task {
            try await Call<GitHubUser>()
                .path("/users/octocat")
                .stub(GitHubUser(login: "octocat", id: 1))
                .stub(behavior: .delayed(0.3))
                .send()
        }
        
        try await _Concurrency.Task.sleep(nanoseconds: 50_000_000)
        Iris.configuration = IrisConfiguration()
            .baseURL("https://api.example.com")
            .plugin(CountingPlugin(box: second))
        
        _ = try await task.value
        XCTAssertEqual(first.value, 1)
        XCTAssertEqual(second.value, 0)
    }
    
    /// Reads and writes of the global configuration are individually atomic.
    /// Smoke test: hammer the global from many tasks while requests snapshot it.
    /// Its real value is under Thread Sanitizer.
    func testConcurrentConfigureAndSend() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<20 {
                group.addTask {
                    Iris.configuration = IrisConfiguration()
                        .baseURL("https://api\(index).example.com")
                }
                group.addTask {
                    _ = try await Call<GitHubUser>()
                        .baseURL("https://api.example.com")
                        .path("/users/octocat")
                        .stub(GitHubUser(login: "octocat", id: 1))
                        .stub(behavior: .immediate)
                        .send()
                }
            }
            try await group.waitForAll()
        }
    }
}

private struct CountingPlugin: PluginType {
    let box: SendableBox<Int>
    
    func didReceive(_ result: Result<HTTPResponse, IrisError>, target: TargetType) {
        box.value += 1
    }
}
