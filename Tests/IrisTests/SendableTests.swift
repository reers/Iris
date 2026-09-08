//
//  SendableTests.swift
//  IrisTests
//
//  Compile-time coverage that public Iris types can cross isolation domains.
//

import XCTest
@testable import Iris

final class SendableTests: XCTestCase {

    func testPublicTypesAreSendable() {
        assertSendable(Call<Empty>())
        assertSendable(Call<Data>())
        assertSendable(Call<String>())
        assertSendable(IrisConfiguration())
        assertSendable(IrisService())
        assertSendable(IrisClient.shared)
        assertSendable(IrisClient())
        assertSendable(StubBehavior.immediate)
        assertSendable(RetryPolicy(count: 2, interval: 0.1, backoff: .none))
        assertSendable(RetryPolicy.Backoff.exponential)
        assertSendable(ValidationType.successCodes)
        assertSendable(HTTPResponse(statusCode: 200, data: Data()))
        assertSendable(Response(model: Empty(), httpResponse: HTTPResponse(statusCode: 200, data: Data())))
        assertSendable(Empty())
        assertSendable(CallTask.requestPlain)
        assertSendable(HeaderModifyingPlugin(headerKey: "X-Test", headerValue: "1"))
        assertSendable(EmptyPlugin())
        assertSendable(
            CompletionInfo(
                result: .success(Response(model: Empty(), httpResponse: HTTPResponse(statusCode: 200, data: Data()))),
                duration: 0
            )
        )
    }

    func testCallCanCrossIsolationDomain() async throws {
        let request = Call<Empty>()
            .baseURL("https://example.com")
            .path("/health")
            .stub(behavior: .immediate)
            .stub(Data())

        let delivered = SendableBox<Bool>(false)
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                _ = try await request.send()
                delivered.value = true
            }
            try await group.waitForAll()
        }
        XCTAssertTrue(delivered.value)
    }

    private func assertSendable<T: Sendable>(_ value: T) {
        _ = value
    }
}
