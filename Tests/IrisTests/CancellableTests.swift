//
//  CancellableTests.swift
//  IrisTests
//
//  Tests for the Cancellable protocol and implementations.
//

import XCTest
@testable import Iris

final class CancellableTests: XCTestCase {
    
    // MARK: - SimpleCancellable Tests
    
    func testSimpleCancellableInitialState() {
        let cancellable = SimpleCancellable()
        XCTAssertFalse(cancellable.isCancelled)
    }
    
    func testSimpleCancellableCancel() {
        let cancellable = SimpleCancellable()
        cancellable.cancel()
        XCTAssertTrue(cancellable.isCancelled)
    }
    
    func testSimpleCancellableMultipleCancels() {
        let cancellable = SimpleCancellable()
        cancellable.cancel()
        cancellable.cancel()
        cancellable.cancel()
        XCTAssertTrue(cancellable.isCancelled)
    }
    
    // MARK: - CancellableWrapper Tests
    
    func testCancellableWrapperInitialState() {
        let wrapper = CancellableWrapper()
        XCTAssertFalse(wrapper.isCancelled)
    }
    
    func testCancellableWrapperCancel() {
        let wrapper = CancellableWrapper()
        wrapper.cancel()
        XCTAssertTrue(wrapper.isCancelled)
    }
    
    func testCancellableWrapperWithInnerCancellable() {
        let wrapper = CancellableWrapper()
        let inner = SimpleCancellable()
        wrapper.innerCancellable = inner
        
        XCTAssertFalse(wrapper.isCancelled)
        XCTAssertFalse(inner.isCancelled)
        
        wrapper.cancel()
        
        XCTAssertTrue(wrapper.isCancelled)
        XCTAssertTrue(inner.isCancelled)
    }
    
    func testCancellableWrapperReplacingInner() {
        let wrapper = CancellableWrapper()
        let inner1 = SimpleCancellable()
        let inner2 = SimpleCancellable()
        
        wrapper.innerCancellable = inner1
        wrapper.innerCancellable = inner2
        
        wrapper.cancel()
        
        // Only inner2 should be cancelled
        XCTAssertFalse(inner1.isCancelled)
        XCTAssertTrue(inner2.isCancelled)
    }
    
    // MARK: - CancellableToken Tests
    
    func testCancellableTokenWithAction() {
        let actionCalled = SendableBox(false)
        let token = CancellableToken {
            actionCalled.value = true
        }
        
        XCTAssertFalse(token.isCancelled)
        XCTAssertFalse(actionCalled.value)
        
        token.cancel()
        
        XCTAssertTrue(token.isCancelled)
        XCTAssertTrue(actionCalled.value)
    }
    
    func testCancellableTokenMultipleCancels() {
        let cancelCount = SendableBox(0)
        let token = CancellableToken {
            cancelCount.value += 1
        }
        
        token.cancel()
        token.cancel()
        token.cancel()
        
        // Action should only be called once
        XCTAssertEqual(cancelCount.value, 1)
        XCTAssertTrue(token.isCancelled)
    }
    
    func testCancellableTokenDebugDescription() {
        let token = CancellableToken { }
        // Without a request, should return "Empty Request"
        XCTAssertEqual(token.debugDescription, "Empty Request")
    }
    
    // MARK: - Cancellable Protocol Tests
    
    func testCancellableProtocolConformance() {
        let simpleCancellable: Cancellable = SimpleCancellable()
        let wrapper: Cancellable = CancellableWrapper()
        let token: Cancellable = CancellableToken { }
        
        // All should start not cancelled
        XCTAssertFalse(simpleCancellable.isCancelled)
        XCTAssertFalse(wrapper.isCancelled)
        XCTAssertFalse(token.isCancelled)
        
        // All should be cancellable
        simpleCancellable.cancel()
        wrapper.cancel()
        token.cancel()
        
        XCTAssertTrue(simpleCancellable.isCancelled)
        XCTAssertTrue(wrapper.isCancelled)
        XCTAssertTrue(token.isCancelled)
    }
    
    // MARK: - Thread Safety Tests
    
    func testCancellableTokenThreadSafety() {
        let cancelCount = SendableBox(0)
        let token = CancellableToken {
            cancelCount.value += 1
        }
        
        let expectation = XCTestExpectation(description: "Thread safety test")
        expectation.expectedFulfillmentCount = 10
        
        // Cancel from multiple threads simultaneously
        for _ in 0..<10 {
            DispatchQueue.global().async {
                token.cancel()
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
        
        // Action should only be called once due to thread safety
        XCTAssertEqual(cancelCount.value, 1)
        XCTAssertTrue(token.isCancelled)
    }
}
