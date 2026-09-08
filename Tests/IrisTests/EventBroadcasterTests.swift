//
//  EventBroadcasterTests.swift
//  IrisTests
//
//  Unit tests for the sidecar multicast semantics: live-only streams and
//  immutable progress snapshots.
//

import XCTest
@testable import Iris

final class EventBroadcasterTests: XCTestCase {
    
    private func makeProgress(_ completed: Int64, total: Int64 = 100) -> Progress {
        let progress = Progress(totalUnitCount: total)
        progress.completedUnitCount = completed
        return progress
    }
    
    // MARK: - Live-Only Semantics
    
    /// Values emitted before a stream is created must not be replayed to it.
    func testValuesYieldedBeforeSubscriptionAreNotReplayed() async {
        let broadcaster = EventBroadcaster(from: Call<Data>())
        
        broadcaster.yieldDownload(makeProgress(10), handlerOnQueue: true)
        broadcaster.yieldDownload(makeProgress(20), handlerOnQueue: true)
        
        let stream = broadcaster.downloadProgress
        
        broadcaster.yieldDownload(makeProgress(30), handlerOnQueue: true)
        broadcaster.finish()
        
        var received: [Int64] = []
        for await progress in stream {
            received.append(progress.completedUnitCount)
        }
        
        XCTAssertEqual(received, [30])
    }
    
    /// Chunks follow the same live-only rule as progress.
    func testChunksYieldedBeforeSubscriptionAreNotReplayed() async {
        let broadcaster = EventBroadcaster(from: Call<Data>().stream())
        
        broadcaster.yieldChunk(Data([0x01]), handlerOnQueue: true)
        
        let stream = broadcaster.chunks
        
        broadcaster.yieldChunk(Data([0x02]), handlerOnQueue: true)
        broadcaster.finish()
        
        var received: [Data] = []
        for await chunk in stream {
            received.append(chunk)
        }
        
        XCTAssertEqual(received, [Data([0x02])])
    }
    
    /// A stream created after `finish()` must close immediately and deliver nothing.
    func testStreamCreatedAfterFinishIsEmptyAndFinished() async {
        let broadcaster = EventBroadcaster(from: Call<Data>())
        
        broadcaster.yieldDownload(makeProgress(10), handlerOnQueue: true)
        broadcaster.finish()
        
        var iterator = broadcaster.downloadProgress.makeAsyncIterator()
        let value = await iterator.next()
        
        XCTAssertNil(value)
    }
    
    // MARK: - Delivery Guarantees
    
    /// An active subscriber receives every value in order, then the stream finishes.
    func testActiveSubscriberReceivesAllValuesInOrderThenFinishes() async {
        let broadcaster = EventBroadcaster(from: Call<Data>())
        let stream = broadcaster.uploadProgress
        
        broadcaster.yieldUpload(makeProgress(10), handlerOnQueue: true)
        broadcaster.yieldUpload(makeProgress(50), handlerOnQueue: true)
        broadcaster.yieldUpload(makeProgress(100), handlerOnQueue: true)
        broadcaster.finish()
        
        var received: [Int64] = []
        for await progress in stream {
            received.append(progress.completedUnitCount)
        }
        
        XCTAssertEqual(received, [10, 50, 100])
    }
    
    /// Each access creates an independent stream that only sees values from that
    /// point on; the first stream is unaffected.
    func testSecondAccessCreatesIndependentStreamWithoutHistory() async {
        let broadcaster = EventBroadcaster(from: Call<Data>())
        let first = broadcaster.downloadProgress
        
        broadcaster.yieldDownload(makeProgress(10), handlerOnQueue: true)
        
        let second = broadcaster.downloadProgress
        
        broadcaster.yieldDownload(makeProgress(20), handlerOnQueue: true)
        broadcaster.finish()
        
        var firstValues: [Int64] = []
        for await progress in first {
            firstValues.append(progress.completedUnitCount)
        }
        
        var secondValues: [Int64] = []
        for await progress in second {
            secondValues.append(progress.completedUnitCount)
        }
        
        XCTAssertEqual(firstValues, [10, 20])
        XCTAssertEqual(secondValues, [20])
    }
    
    /// Values yielded after `finish()` reach neither streams nor new subscribers.
    func testValuesYieldedAfterFinishAreDropped() async {
        let broadcaster = EventBroadcaster(from: Call<Data>())
        let stream = broadcaster.downloadProgress
        
        broadcaster.yieldDownload(makeProgress(10), handlerOnQueue: true)
        broadcaster.finish()
        broadcaster.yieldDownload(makeProgress(20), handlerOnQueue: true)
        
        var received: [Int64] = []
        for await progress in stream {
            received.append(progress.completedUnitCount)
        }
        
        XCTAssertEqual(received, [10])
    }
    
    // MARK: - Snapshot Truthfulness
    
    /// Alamofire mutates one shared `Progress` instance; a delivered value must
    /// reflect the state at yield time, not later mutations.
    func testProgressIsSnapshottedAtYieldTime() async {
        let broadcaster = EventBroadcaster(from: Call<Data>())
        let stream = broadcaster.downloadProgress
        
        let shared = makeProgress(10)
        broadcaster.yieldDownload(shared, handlerOnQueue: true)
        shared.completedUnitCount = 90 // later mutation must not leak into the delivered value
        broadcaster.yieldDownload(shared, handlerOnQueue: true)
        
        broadcaster.finish()
        
        var received: [Int64] = []
        for await progress in stream {
            received.append(progress.completedUnitCount)
        }
        
        XCTAssertEqual(received, [10, 90])
    }
    
    // MARK: - Recipe Handlers
    
    /// Recipe handlers fire even when no stream subscriber exists.
    func testRecipeHandlerReceivesValuesWithoutStreamSubscribers() {
        let received = SendableArray<Int64>()
        let handlerCalled = expectation(description: "Recipe handler should be called")
        let call = Call<Data>().onDownloadProgress(on: .global()) { progress in
            received.append(progress.completedUnitCount)
            handlerCalled.fulfill()
        }
        let broadcaster = EventBroadcaster(from: call)

        broadcaster.yieldDownload(makeProgress(42), handlerOnQueue: false)
        broadcaster.finish()

        wait(for: [handlerCalled], timeout: 1)
        XCTAssertEqual(received.values, [42])
    }

    /// Dispatching sidecar handlers must not synchronously block cooperative
    /// Swift concurrency threads while a target queue is busy.
    func testRecipeHandlerDeliveryDoesNotBlockCallerWhenQueueIsBusy() {
        let queue = DispatchQueue(label: "iris.tests.busy-sidecar-queue")
        let busyStarted = expectation(description: "Queue should become busy")
        let handlerCalled = expectation(description: "Recipe handler should eventually be called")
        let received = SendableArray<Int64>()

        queue.async {
            busyStarted.fulfill()
            Thread.sleep(forTimeInterval: 0.2)
        }
        wait(for: [busyStarted], timeout: 1)

        let call = Call<Data>().onDownloadProgress(on: queue) { progress in
            received.append(progress.completedUnitCount)
            handlerCalled.fulfill()
        }
        let broadcaster = EventBroadcaster(from: call)

        let start = Date()
        broadcaster.yieldDownload(makeProgress(42), handlerOnQueue: false)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 0.1)
        wait(for: [handlerCalled], timeout: 1)
        XCTAssertEqual(received.values, [42])
    }
    
    /// Recipe handlers receive snapshots too, not the mutable shared instance.
    func testRecipeHandlerReceivesSnapshot() {
        let received = SendableArray<Progress>()
        let handlerCalled = expectation(description: "Recipe handler should be called")
        let call = Call<Data>().onDownloadProgress(on: .global()) { progress in
            received.append(progress)
            handlerCalled.fulfill()
        }
        let broadcaster = EventBroadcaster(from: call)

        let shared = makeProgress(10)
        broadcaster.yieldDownload(shared, handlerOnQueue: false)
        shared.completedUnitCount = 90

        wait(for: [handlerCalled], timeout: 1)
        XCTAssertEqual(received.values.first?.completedUnitCount, 10)
    }
}
