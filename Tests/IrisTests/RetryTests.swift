//
//  RetryTests.swift
//  IrisTests
//
//  Call / configuration retry policy and Alamofire retrier behavior.
//

import XCTest
@testable import Iris

final class RetryTests: XCTestCase {

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

    // MARK: - Policy

    func testRetryPolicyStoresCountIntervalAndBackoff() {
        let policy = RetryPolicy(count: 3, interval: 0.25, backoff: .linear, idempotentOnly: false)

        XCTAssertEqual(policy.count, 3)
        XCTAssertEqual(policy.interval, 0.25)
        XCTAssertEqual(policy.backoff, .linear)
        XCTAssertFalse(policy.idempotentOnly)
    }

    func testRetryDelayNoneUsesInterval() {
        let policy = RetryPolicy(count: 3, interval: 0.4, backoff: .none)

        XCTAssertEqual(policy.delay(beforeRetry: 1), 0.4)
        XCTAssertEqual(policy.delay(beforeRetry: 3), 0.4)
    }

    func testRetryDelayLinearScalesWithAttempt() {
        let policy = RetryPolicy(count: 3, interval: 0.5, backoff: .linear)

        XCTAssertEqual(policy.delay(beforeRetry: 1), 0.5)
        XCTAssertEqual(policy.delay(beforeRetry: 2), 1.0)
        XCTAssertEqual(policy.delay(beforeRetry: 3), 1.5)
    }

    func testRetryDelayExponentialScalesWithAttempt() {
        let policy = RetryPolicy(count: 3, interval: 0.5, backoff: .exponential)

        XCTAssertEqual(policy.delay(beforeRetry: 1), 0.5)
        XCTAssertEqual(policy.delay(beforeRetry: 2), 1.0)
        XCTAssertEqual(policy.delay(beforeRetry: 3), 2.0)
    }

    func testRetryDelayIsClampedToFiniteValue() {
        let policy = RetryPolicy(count: 100, interval: .infinity, backoff: .exponential)

        XCTAssertTrue(policy.delay(beforeRetry: 100).isFinite)
        XCTAssertLessThanOrEqual(policy.delay(beforeRetry: 100), RetryPolicy.maximumDelay)
    }

    func testRetryDelayTreatsInvalidBackoffAsImmediateRetry() {
        let policy = RetryPolicy(count: 3, interval: 0.5, backoff: .exponential(base: .nan, scale: 1))

        XCTAssertEqual(policy.delay(beforeRetry: 2), 0)
    }

    func testCallRetrySetsPolicy() {
        let request = Call<Empty>()
            .retry(count: 2, interval: 0.1, backoff: .none)

        XCTAssertEqual(request.retryPolicy?.count, 2)
        XCTAssertEqual(request.retryPolicy?.interval, 0.1)
        XCTAssertEqual(request.retryPolicy?.backoff, RetryPolicy.Backoff.none)
    }

    func testCallRetryPolicyOverridesConfiguration() {
        let configuration = IrisConfiguration()
            .retry(count: 5, interval: 1, backoff: .linear)
        let request = Call<Empty>()
            .retry(count: 1, interval: 0, backoff: .none)

        XCTAssertEqual(request.retryPolicy(over: configuration)?.count, 1)
    }

    func testCallRetryCountZeroDisablesConfigurationRetry() {
        let configuration = IrisConfiguration()
            .retry(count: 3, interval: 0, backoff: .none)
        let request = Call<Empty>()
            .retry(count: 0)

        XCTAssertNil(request.retryPolicy(over: configuration))
    }

    func testConfigurationRetryIsUsedWhenCallOmitsRetry() {
        let configuration = IrisConfiguration()
            .retry(count: 4, interval: 0.2, backoff: .none)

        XCTAssertEqual(Call<Empty>().retryPolicy(over: configuration)?.count, 4)
    }

    // MARK: - Live retries

    func testConnectionErrorRetriesUntilSuccess() async throws {
        let attempts = SendableBox(0)
        stubSequential { attempt in
            attempts.value = attempt
            if attempt < 3 {
                throw URLError(.networkConnectionLost)
            }
            return (httpResponse(200), Data("{}".utf8))
        }

        let response = try await Call.empty()
            .path("/retry-connection")
            .retry(count: 2, interval: 0, backoff: .none)
            .send()

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(attempts.value, 3)
    }

    func testPostDoesNotRetryByDefault() async throws {
        let attempts = SendableBox(0)
        stubSequential { attempt in
            attempts.value = attempt
            return (httpResponse(503), Data())
        }

        let response = try await Call.empty()
            .path("/retry-post")
            .method(.post)
            .retry(count: 2, interval: 0, backoff: .none)
            .send()

        XCTAssertEqual(response.statusCode, 503)
        XCTAssertEqual(attempts.value, 1)
    }

    func testPostRetriesWhenIdempotentOnlyIsDisabled() async throws {
        let attempts = SendableBox(0)
        stubSequential { attempt in
            attempts.value = attempt
            if attempt < 3 {
                return (httpResponse(503), Data())
            }
            return (httpResponse(200), Data("{}".utf8))
        }

        let response = try await Call.empty()
            .path("/retry-post-forced")
            .method(.post)
            .retry(count: 2, interval: 0, backoff: .none, idempotentOnly: false)
            .send()

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(attempts.value, 3)
    }

    func testClientErrorDoesNotRetry() async throws {
        let attempts = SendableBox(0)
        stubSequential { attempt in
            attempts.value = attempt
            return (httpResponse(400), Data("bad".utf8))
        }

        let response = try await Call.data()
            .path("/retry-400")
            .retry(count: 2, interval: 0, backoff: .none)
            .send()

        XCTAssertEqual(response.statusCode, 400)
        XCTAssertEqual(response.model, Data("bad".utf8))
        XCTAssertEqual(attempts.value, 1)
    }

    func testServerErrorRetriesThenSucceeds() async throws {
        let attempts = SendableBox(0)
        stubSequential { attempt in
            attempts.value = attempt
            if attempt < 3 {
                return (httpResponse(503), Data())
            }
            return (httpResponse(200), Data("{}".utf8))
        }

        let response = try await Call.empty()
            .path("/retry-503")
            .retry(count: 2, interval: 0, backoff: .none)
            .send()

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(attempts.value, 3)
    }

    func testExhaustedServerErrorRemainsSuccessWithoutValidation() async throws {
        let attempts = SendableBox(0)
        stubSequential { attempt in
            attempts.value = attempt
            return (httpResponse(503), Data("down".utf8))
        }

        let response = try await Call.data()
            .path("/retry-503-success")
            .retry(count: 2, interval: 0, backoff: .none)
            .send()

        XCTAssertEqual(response.statusCode, 503)
        XCTAssertEqual(response.model, Data("down".utf8))
        XCTAssertEqual(attempts.value, 3)
    }

    func testExhaustedServerErrorStaysFailureWithSuccessValidation() async {
        let attempts = SendableBox(0)
        stubSequential { attempt in
            attempts.value = attempt
            return (httpResponse(503), Data())
        }

        do {
            _ = try await Call.data()
                .path("/retry-503-validate")
                .validateSuccessCodes()
                .retry(count: 2, interval: 0, backoff: .none)
                .send()
            XCTFail("Expected statusCode error")
        } catch let IrisError.statusCode(response) {
            XCTAssertEqual(response.statusCode, 503)
        } catch {
            XCTFail("Expected statusCode, got \(error)")
        }

        XCTAssertEqual(attempts.value, 3)
    }

    func testConfigurationRetryAppliesWhenCallOmitsRetry() async throws {
        Iris.configure(
            IrisConfiguration()
                .baseURL("https://api.example.com")
                .session(makeStubbedSession())
                .retry(count: 2, interval: 0, backoff: .none)
        )

        let attempts = SendableBox(0)
        stubSequential { attempt in
            attempts.value = attempt
            if attempt < 3 {
                throw URLError(.timedOut)
            }
            return (httpResponse(200), Data("{}".utf8))
        }

        let response = try await Call.empty()
            .path("/retry-config")
            .send()

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(attempts.value, 3)
    }

    func testStubPathDoesNotRetry() async throws {
        let plugin = TestingPlugin()
        Iris.configure(
            IrisConfiguration()
                .baseURL("https://api.example.com")
                .plugin(plugin)
                .stub(.immediate)
        )

        _ = try await Call.empty()
            .path("/retry-stub")
            .stub(Data())
            .retry(count: 3, interval: 0, backoff: .none)
            .send()

        XCTAssertEqual(plugin.willSendCalledCount, 1)
        XCTAssertEqual(plugin.didReceiveCalledCount, 1)
        XCTAssertEqual(plugin.processCalledCount, 1)
    }

    func testPrepareAndWillSendRunPerAttemptDidReceiveOnce() async throws {
        let plugin = TestingPlugin()
        Iris.configure(
            IrisConfiguration()
                .baseURL("https://api.example.com")
                .session(makeStubbedSession())
                .plugin(plugin)
        )

        stubSequential { attempt in
            if attempt < 3 {
                throw URLError(.cannotConnectToHost)
            }
            return (httpResponse(200), Data("{}".utf8))
        }

        _ = try await Call.empty()
            .path("/retry-plugins")
            .retry(count: 2, interval: 0, backoff: .none)
            .send()

        XCTAssertEqual(plugin.prepareCalledCount, 3)
        XCTAssertEqual(plugin.willSendCalledCount, 3)
        XCTAssertEqual(plugin.didReceiveCalledCount, 1)
        XCTAssertEqual(plugin.processCalledCount, 1)
    }

    func testCancelledRequestDoesNotRetry() async {
        let starts = SendableBox(0)
        let didStart = expectation(description: "first attempt should start")
        StubURLProtocol.responseDelay = 5
        StubURLProtocol.onStartLoading = {
            starts.value += 1
            if starts.value == 1 {
                didStart.fulfill()
            }
        }
        stubSequential { _ in
            throw URLError(.networkConnectionLost)
        }

        let task = _Concurrency.Task {
            try await Call.empty()
                .path("/retry-cancel")
                .retry(count: 5, interval: 2, backoff: .none)
                .send()
        }

        await fulfillment(of: [didStart], timeout: 1)
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            // Alamofire may surface the cancelled transport error.
        }

        XCTAssertEqual(starts.value, 1)
    }

    func testStreamRetriesTransportErrorBeforeFirstChunk() async throws {
        let attempts = SendableBox(0)
        stubSequential { attempt in
            attempts.value = attempt
            if attempt < 3 {
                throw URLError(.networkConnectionLost)
            }
            return (httpResponse(200), Data("hello".utf8))
        }

        let response = try await Call.data()
            .path("/retry-stream")
            .stream()
            .retry(count: 2, interval: 0, backoff: .none)
            .send()

        XCTAssertEqual(response.model, Data("hello".utf8))
        XCTAssertEqual(attempts.value, 3)
    }

    func testStreamDoesNotRetryAfterChunksArrive() async throws {
        let attempts = SendableBox(0)
        stubSequential { attempt in
            attempts.value = attempt
            return (httpResponse(503), Data("partial".utf8))
        }

        let response = try await Call.data()
            .path("/retry-stream-chunks")
            .stream()
            .retry(count: 2, interval: 0, backoff: .none)
            .send()

        XCTAssertEqual(response.statusCode, 503)
        XCTAssertEqual(response.model, Data("partial".utf8))
        XCTAssertEqual(attempts.value, 1)
    }

    func testTerminalStreamDoesNotRetryAfterChunksArrive() async throws {
        let attempts = SendableBox(0)
        StubURLProtocol.bodyChunkSize = 3
        stubSequential { attempt in
            attempts.value = attempt
            return (httpResponse(503), Data("partial".utf8))
        }

        var chunks: [Data] = []
        for try await chunk in Call<Empty>()
            .path("/retry-terminal-stream-chunks")
            .retry(count: 2, interval: 0, backoff: .none)
            .streamBytes() {
            chunks.append(chunk)
        }

        XCTAssertEqual(chunks.reduce(into: Data()) { $0.append($1) }, Data("partial".utf8))
        XCTAssertEqual(attempts.value, 1)
    }

    // MARK: - Helpers

    private func stubSequential(
        _ handler: @escaping @Sendable (Int) throws -> (HTTPURLResponse, Data)
    ) {
        let attempts = SendableBox(0)
        StubURLProtocol.handler = { _ in
            attempts.value += 1
            return try handler(attempts.value)
        }
    }
}

private func httpResponse(_ statusCode: Int) -> HTTPURLResponse {
    HTTPURLResponse(
        url: URL(string: "https://api.example.com/retry")!,
        statusCode: statusCode,
        httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": "application/json"]
    )!
}
