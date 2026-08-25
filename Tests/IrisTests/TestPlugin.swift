//
//  TestPlugin.swift
//  IrisTests
//
//  Test plugins for verifying plugin system behavior.
//

import Foundation
@testable import Iris

// MARK: - TestingPlugin

/// A comprehensive testing plugin that tracks all plugin method calls.
///
/// Use this plugin in tests to verify that plugins are called correctly
/// at each stage of the request lifecycle.
final class TestingPlugin: PluginType {
    
    /// The last request and target passed to willSend.
    var request: (CallType, TargetType)?
    
    /// The last result passed to didReceive.
    var result: Result<RawResponse, IrisError>?
    
    /// Whether prepare was called before willSend.
    var didPrepare = false
    
    /// Number of times prepare was called.
    var prepareCalledCount = 0
    
    /// Number of times willSend was called.
    var willSendCalledCount = 0
    
    /// Number of times didReceive was called.
    var didReceiveCalledCount = 0
    
    /// Number of times process was called.
    var processCalledCount = 0
    
    func prepare(_ request: URLRequest, target: TargetType) -> URLRequest {
        prepareCalledCount += 1
        var request = request
        request.addValue("yes", forHTTPHeaderField: "prepared")
        return request
    }
    
    func willSend(_ request: CallType, target: TargetType) {
        willSendCalledCount += 1
        self.request = (request, target)
        
        // Check that prepare was called before willSend
        didPrepare = request.request?.allHTTPHeaderFields?["prepared"] == "yes"
    }
    
    func didReceive(_ result: Result<RawResponse, IrisError>, target: TargetType) {
        didReceiveCalledCount += 1
        self.result = result
    }
    
    func process(_ result: Result<RawResponse, IrisError>, target: TargetType) -> Result<RawResponse, IrisError> {
        processCalledCount += 1
        var result = result
        
        if case .success(let response) = result {
            let processedResponse = RawResponse(
                statusCode: -1,
                data: response.data,
                request: response.request,
                response: response.response
            )
            result = .success(processedResponse)
        }
        
        return result
    }
    
    /// Resets all tracked state.
    func reset() {
        request = nil
        result = nil
        didPrepare = false
        prepareCalledCount = 0
        willSendCalledCount = 0
        didReceiveCalledCount = 0
        processCalledCount = 0
    }
}

// MARK: - OrderTrackingPlugin

/// A plugin that tracks the order of method calls.
///
/// Use this to verify that plugin methods are called in the expected order.
final class OrderTrackingPlugin: PluginType {
    
    /// The order in which methods were called.
    var callOrder: [String] = []
    
    func prepare(_ request: URLRequest, target: TargetType) -> URLRequest {
        callOrder.append("prepare")
        return request
    }
    
    func willSend(_ request: CallType, target: TargetType) {
        callOrder.append("willSend")
    }
    
    func didReceive(_ result: Result<RawResponse, IrisError>, target: TargetType) {
        callOrder.append("didReceive")
    }
    
    func process(_ result: Result<RawResponse, IrisError>, target: TargetType) -> Result<RawResponse, IrisError> {
        callOrder.append("process")
        return result
    }
    
    /// Resets the call order tracking.
    func reset() {
        callOrder = []
    }
}

// MARK: - HeaderModifyingPlugin

/// A plugin that adds a custom header to requests.
final class HeaderModifyingPlugin: PluginType {
    
    /// The header key to add.
    let headerKey: String
    
    /// The header value to add.
    let headerValue: String
    
    /// Creates a new header modifying plugin.
    ///
    /// - Parameters:
    ///   - headerKey: The header field name.
    ///   - headerValue: The header field value.
    init(headerKey: String, headerValue: String) {
        self.headerKey = headerKey
        self.headerValue = headerValue
    }
    
    func prepare(_ request: URLRequest, target: TargetType) -> URLRequest {
        var request = request
        request.addValue(headerValue, forHTTPHeaderField: headerKey)
        return request
    }
}

// MARK: - ResponseModifyingPlugin

/// A plugin that modifies the response status code.
final class ResponseModifyingPlugin: PluginType {
    
    /// The new status code to set.
    let newStatusCode: Int
    
    /// Creates a new response modifying plugin.
    ///
    /// - Parameter newStatusCode: The status code to set on responses.
    init(newStatusCode: Int) {
        self.newStatusCode = newStatusCode
    }
    
    func process(_ result: Result<RawResponse, IrisError>, target: TargetType) -> Result<RawResponse, IrisError> {
        if case .success(let response) = result {
            let modifiedResponse = RawResponse(
                statusCode: newStatusCode,
                data: response.data,
                request: response.request,
                response: response.response
            )
            return .success(modifiedResponse)
        }
        return result
    }
}

// MARK: - ErrorInjectingPlugin

/// A plugin that injects an error into all responses.
final class ErrorInjectingPlugin: PluginType {
    
    /// The error to inject.
    let error: IrisError
    
    /// Creates a new error injecting plugin.
    ///
    /// - Parameter error: The error to return for all requests.
    init(error: IrisError) {
        self.error = error
    }
    
    func process(_ result: Result<RawResponse, IrisError>, target: TargetType) -> Result<RawResponse, IrisError> {
        return .failure(error)
    }
}

// MARK: - NetworkActivityPlugin

/// A plugin that tracks network activity changes.
///
/// Use this to test that network activity indicators are properly shown/hidden.
final class NetworkActivityPlugin: PluginType {
    
    /// The type of network activity change.
    enum NetworkActivityChangeType {
        case began
        case ended
    }
    
    /// Closure type for network activity changes.
    typealias NetworkActivityClosure = (_ change: NetworkActivityChangeType, _ target: TargetType) -> Void
    
    /// The closure called when network activity changes.
    let networkActivityClosure: NetworkActivityClosure
    
    /// Creates a new network activity plugin.
    ///
    /// - Parameter networkActivityClosure: Called when activity starts or ends.
    init(networkActivityClosure: @escaping NetworkActivityClosure) {
        self.networkActivityClosure = networkActivityClosure
    }
    
    func willSend(_ request: CallType, target: TargetType) {
        networkActivityClosure(.began, target)
    }
    
    func didReceive(_ result: Result<RawResponse, IrisError>, target: TargetType) {
        networkActivityClosure(.ended, target)
    }
}

// MARK: - EmptyPlugin

/// An empty plugin that uses all default implementations.
///
/// Use this to test that the default plugin implementations work correctly.
final class EmptyPlugin: PluginType {
    // Uses all default implementations
}
