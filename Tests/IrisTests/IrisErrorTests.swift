//
//  IrisErrorTests.swift
//  IrisTests
//
//  Tests for IrisError types and properties.
//

import XCTest
@testable import Iris

final class IrisErrorTests: XCTestCase {
    
    var response: RawResponse!
    var underlyingError: NSError!
    
    override func setUp() {
        super.setUp()
        response = RawResponse(statusCode: 200, data: Data(), request: nil, response: nil)
        underlyingError = NSError(domain: "UnderlyingDomain", code: 200, userInfo: ["data": "some data"])
    }
    
    // MARK: - Response Computed Variable Tests
    
    func testImageMappingErrorReturnsResponse() {
        let error = IrisError.imageMapping(response)
        XCTAssertEqual(error.response?.statusCode, response.statusCode)
    }
    
    func testJSONMappingErrorReturnsResponse() {
        let error = IrisError.jsonMapping(response)
        XCTAssertEqual(error.response?.statusCode, response.statusCode)
    }
    
    func testStringMappingErrorReturnsResponse() {
        let error = IrisError.stringMapping(response)
        XCTAssertEqual(error.response?.statusCode, response.statusCode)
    }
    
    func testObjectMappingErrorReturnsResponse() {
        let error = IrisError.objectMapping(underlyingError, response)
        XCTAssertEqual(error.response?.statusCode, response.statusCode)
    }
    
    func testEncodableMappingErrorReturnsNilResponse() {
        let error = IrisError.encodableMapping(underlyingError)
        XCTAssertNil(error.response)
    }
    
    func testStatusCodeErrorReturnsResponse() {
        let error = IrisError.statusCode(response)
        XCTAssertEqual(error.response?.statusCode, response.statusCode)
    }
    
    func testUnderlyingErrorReturnsResponse() {
        let error = IrisError.underlying(underlyingError, response)
        XCTAssertEqual(error.response?.statusCode, response.statusCode)
    }
    
    func testRequestMappingErrorReturnsNilResponse() {
        let error = IrisError.requestMapping("http://www.example.com")
        XCTAssertNil(error.response)
    }
    
    func testParameterEncodingErrorReturnsNilResponse() {
        let error = IrisError.parameterEncoding(underlyingError)
        XCTAssertNil(error.response)
    }
    
    // MARK: - UnderlyingError Computed Variable Tests
    
    func testImageMappingErrorReturnsNilUnderlyingError() {
        let error = IrisError.imageMapping(response)
        XCTAssertNil(error.underlyingError)
    }
    
    func testJSONMappingErrorReturnsNilUnderlyingError() {
        let error = IrisError.jsonMapping(response)
        XCTAssertNil(error.underlyingError)
    }
    
    func testStringMappingErrorReturnsNilUnderlyingError() {
        let error = IrisError.stringMapping(response)
        XCTAssertNil(error.underlyingError)
    }
    
    func testObjectMappingErrorReturnsUnderlyingError() {
        let error = IrisError.objectMapping(underlyingError, response)
        XCTAssertEqual(error.underlyingError as NSError?, underlyingError)
    }
    
    func testEncodableMappingErrorReturnsUnderlyingError() {
        let error = IrisError.encodableMapping(underlyingError)
        XCTAssertEqual(error.underlyingError as NSError?, underlyingError)
    }
    
    func testStatusCodeErrorReturnsNilUnderlyingError() {
        let error = IrisError.statusCode(response)
        XCTAssertNil(error.underlyingError)
    }
    
    func testUnderlyingErrorReturnsTheUnderlyingError() {
        let error = IrisError.underlying(underlyingError, response)
        XCTAssertEqual(error.underlyingError as NSError?, underlyingError)
    }
    
    func testRequestMappingErrorReturnsNilUnderlyingError() {
        let error = IrisError.requestMapping("http://www.example.com")
        XCTAssertNil(error.underlyingError)
    }
    
    func testParameterEncodingErrorReturnsUnderlyingError() {
        let error = IrisError.parameterEncoding(underlyingError)
        XCTAssertEqual(error.underlyingError as NSError?, underlyingError)
    }
    
    // MARK: - Bridged UserInfo Dictionary Tests
    
    func testImageMappingErrorHasLocalizedDescriptionAndNoUnderlyingError() {
        let error = IrisError.imageMapping(response)
        let userInfo = (error as NSError).userInfo
        
        XCTAssertEqual(userInfo[NSLocalizedDescriptionKey] as? String, error.errorDescription)
        XCTAssertNil(userInfo[NSUnderlyingErrorKey] as? NSError)
    }
    
    func testJSONMappingErrorHasLocalizedDescriptionAndNoUnderlyingError() {
        let error = IrisError.jsonMapping(response)
        let userInfo = (error as NSError).userInfo
        
        XCTAssertEqual(userInfo[NSLocalizedDescriptionKey] as? String, error.errorDescription)
        XCTAssertNil(userInfo[NSUnderlyingErrorKey] as? NSError)
    }
    
    func testStringMappingErrorHasLocalizedDescriptionAndNoUnderlyingError() {
        let error = IrisError.stringMapping(response)
        let userInfo = (error as NSError).userInfo
        
        XCTAssertEqual(userInfo[NSLocalizedDescriptionKey] as? String, error.errorDescription)
        XCTAssertNil(userInfo[NSUnderlyingErrorKey] as? NSError)
    }
    
    func testObjectMappingErrorHasLocalizedDescriptionAndUnderlyingError() {
        let error = IrisError.objectMapping(underlyingError, response)
        let userInfo = (error as NSError).userInfo
        
        XCTAssertEqual(userInfo[NSLocalizedDescriptionKey] as? String, error.errorDescription)
        XCTAssertEqual(userInfo[NSUnderlyingErrorKey] as? NSError, underlyingError)
    }
    
    func testEncodableMappingErrorHasLocalizedDescriptionAndUnderlyingError() {
        let error = IrisError.encodableMapping(underlyingError)
        let userInfo = (error as NSError).userInfo
        
        XCTAssertEqual(userInfo[NSLocalizedDescriptionKey] as? String, error.errorDescription)
        XCTAssertEqual(userInfo[NSUnderlyingErrorKey] as? NSError, underlyingError)
    }
    
    func testStatusCodeErrorHasLocalizedDescriptionAndNoUnderlyingError() {
        let error = IrisError.statusCode(response)
        let userInfo = (error as NSError).userInfo
        
        XCTAssertEqual(userInfo[NSLocalizedDescriptionKey] as? String, error.errorDescription)
        XCTAssertNil(userInfo[NSUnderlyingErrorKey] as? NSError)
    }
    
    func testUnderlyingErrorHasLocalizedDescriptionAndUnderlyingError() {
        let error = IrisError.underlying(underlyingError, nil)
        let userInfo = (error as NSError).userInfo
        
        XCTAssertEqual(userInfo[NSLocalizedDescriptionKey] as? String, error.errorDescription)
        XCTAssertEqual(userInfo[NSUnderlyingErrorKey] as? NSError, underlyingError)
    }
    
    func testRequestMappingErrorHasLocalizedDescriptionAndNoUnderlyingError() {
        let error = IrisError.requestMapping("http://www.example.com")
        let userInfo = (error as NSError).userInfo
        
        XCTAssertEqual(userInfo[NSLocalizedDescriptionKey] as? String, error.errorDescription)
        XCTAssertNil(userInfo[NSUnderlyingErrorKey] as? NSError)
    }
    
    func testParameterEncodingErrorHasLocalizedDescriptionAndUnderlyingError() {
        let error = IrisError.parameterEncoding(underlyingError)
        let userInfo = (error as NSError).userInfo
        
        XCTAssertEqual(userInfo[NSLocalizedDescriptionKey] as? String, error.errorDescription)
        XCTAssertEqual(userInfo[NSUnderlyingErrorKey] as? NSError, underlyingError)
    }
    
    // MARK: - Error Description Tests
    
    func testImageMappingErrorDescription() {
        let error = IrisError.imageMapping(response)
        XCTAssertEqual(error.errorDescription, "Failed to map data to an Image.")
    }
    
    func testJSONMappingErrorDescription() {
        let error = IrisError.jsonMapping(response)
        XCTAssertEqual(error.errorDescription, "Failed to map data to JSON.")
    }
    
    func testStringMappingErrorDescription() {
        let error = IrisError.stringMapping(response)
        XCTAssertEqual(error.errorDescription, "Failed to map data to a String.")
    }
    
    func testObjectMappingErrorDescription() {
        let error = IrisError.objectMapping(underlyingError, response)
        XCTAssertEqual(error.errorDescription, "Failed to map data to a Decodable object.")
    }
    
    func testEncodableMappingErrorDescription() {
        let error = IrisError.encodableMapping(underlyingError)
        XCTAssertEqual(error.errorDescription, "Failed to encode Encodable object into data.")
    }
    
    func testStatusCodeErrorDescription() {
        let error = IrisError.statusCode(response)
        XCTAssertEqual(error.errorDescription, "Status code didn't fall within the given range.")
    }
    
    func testRequestMappingErrorDescription() {
        let error = IrisError.requestMapping("http://www.example.com")
        XCTAssertEqual(error.errorDescription, "Failed to map Endpoint to a URLRequest.")
    }
    
    // MARK: - Network Result Mapping Tests
    
    func testHTTPErrorMapsToStatusCode() {
        let url = URL(string: "https://example.com")!
        let http = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)
        let result = Iris.mapNetworkResult(
            data: Data(),
            request: nil,
            response: http,
            error: URLError(.badServerResponse)
        )
        
        if case .failure(.statusCode(let mapped)) = result {
            XCTAssertEqual(mapped.statusCode, 404)
        } else {
            XCTFail("Expected statusCode error, got \(result)")
        }
    }
    
    func testTransportErrorMapsToUnderlying() {
        let result = Iris.mapNetworkResult(
            data: Data(),
            request: nil,
            response: nil,
            error: URLError(.notConnectedToInternet)
        )
        
        if case .failure(.underlying) = result {
            // Expected
        } else {
            XCTFail("Expected underlying error, got \(result)")
        }
    }
    
    func testSuccessfulHTTPResponseMapsToSuccess() {
        let url = URL(string: "https://example.com")!
        let http = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        let result = Iris.mapNetworkResult(
            data: Data(),
            request: nil,
            response: http,
            error: nil
        )
        
        if case .success(let mapped) = result {
            XCTAssertEqual(mapped.statusCode, 200)
        } else {
            XCTFail("Expected success, got \(result)")
        }
    }
}
