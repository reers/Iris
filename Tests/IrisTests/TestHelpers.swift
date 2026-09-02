//
//  TestHelpers.swift
//  IrisTests
//
//  Test helper classes and mock data fixtures.
//

import Foundation
@testable import Iris

// MARK: - API Factories (Iris Style)

/// GitHub API call factory - demonstrates Iris chainable API usage.
enum GitHubAPI {
    static let baseURL = "https://api.github.com"
    
    /// Fetches the GitHub Zen message.
    static func zen() -> Call<String> {
        Call<String>()
            .baseURL(baseURL)
            .path("/zen")
            .method(.get)
            .stub("Half measures are as bad as nothing at all.")
    }
    
    /// Fetches a user's profile by username.
    static func userProfile(_ name: String) -> Call<GitHubUser> {
        Call<GitHubUser>()
            .baseURL(baseURL)
            .path("/users/\(name.urlEscaped)")
            .method(.get)
            .stub(GitHubUser(login: name, id: 100))
            .validateSuccessAndRedirectCodes()
    }
}

/// HTTPBin API request factory for testing various request types.
enum HTTPBinAPI {
    static let baseURL = "http://httpbin.org"
    
    /// Tests basic authentication.
    static func basicAuth() -> Call<AuthResponse> {
        Call<AuthResponse>()
            .baseURL(baseURL)
            .path("/basic-auth/user/passwd")
            .method(.get)
            .stub(AuthResponse(authenticated: true, user: "user"))
    }
    
    /// Tests POST requests.
    static func post() -> Call<HTTPBinResponse> {
        Call<HTTPBinResponse>()
            .baseURL(baseURL)
            .path("/post")
            .method(.post)
            .stub(HTTPBinResponse.empty)
    }
    
    /// Tests file upload.
    static func upload(file: URL) -> Call<HTTPBinResponse> {
        Call<HTTPBinResponse>()
            .baseURL(baseURL)
            .path("/post")
            .method(.post)
            .upload(file: file)
            .stub(HTTPBinResponse.empty)
    }
    
    /// Tests multipart form upload.
    static func uploadMultipart(
        parts: [MultipartFormBodyPart],
        urlParameters: [String: Any]? = nil
    ) -> Call<HTTPBinResponse> {
        var request = Call<HTTPBinResponse>()
            .baseURL(baseURL)
            .path("/post")
            .method(.post)
            .stub(HTTPBinResponse.empty)
        
        if let urlParameters = urlParameters {
            request = request.upload(multipart: MultipartFormData(parts: parts), query: urlParameters)
        } else {
            request = request.upload(multipart: MultipartFormData(parts: parts))
        }
        
        return request
    }
    
    /// Tests validated multipart upload.
    static func validatedUpload(
        parts: [MultipartFormBodyPart],
        urlParameters: [String: Any]? = nil,
        codes: [Int]
    ) -> Call<HTTPBinResponse> {
        var request = uploadMultipart(parts: parts, urlParameters: urlParameters)
        request = request.validate(.customCodes(codes))
        return request
    }
    
    /// Creates test multipart form data.
    static func createTestMultipartFormData() -> [MultipartFormBodyPart] {
        let string = "some data"
        guard let data = string.data(using: .utf8) else {
            fatalError("Failed creating Data from String \(string)")
        }
        return [
            MultipartFormBodyPart(provider: .data(data), name: "data")
        ]
    }
}

/// GitHubUserContent API request factory for download testing.
enum GitHubUserContentAPI {
    static let baseURL = "https://raw.githubusercontent.com"
    
    /// Downloads content from the Moya repository.
    static func downloadMoyaWebContent(_ contentPath: String) -> Call<Data> {
        Call<Data>()
            .baseURL(baseURL)
            .path("/Moya/Moya/master/web/\(contentPath)")
            .method(.get)
            .download(to: defaultDownloadDestination)
            .stub(Data(count: 4000))
    }
    
    /// Requests content from the Moya repository.
    static func requestMoyaWebContent(_ contentPath: String) -> Call<Data> {
        Call<Data>()
            .baseURL(baseURL)
            .path("/Moya/Moya/master/web/\(contentPath)")
            .method(.get)
            .stub(Data(count: 4000))
    }
}

/// Default download destination for file downloads.
private let defaultDownloadDestination: DownloadDestination = { temporaryURL, response in
    let directoryURLs = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
    
    if !directoryURLs.isEmpty {
        return (directoryURLs.first!.appendingPathComponent(response.suggestedFilename!), [])
    }
    
    return (temporaryURL, [])
}

// MARK: - Response Models

/// HTTPBin authentication response model.
struct AuthResponse: Codable, Equatable {
    let authenticated: Bool
    let user: String
}

/// HTTPBin response model.
struct HTTPBinResponse: Codable, Equatable {
    let args: [String: String]
    let data: String
    let files: [String: String]
    let form: [String: String]
    
    /// Empty response for stubbing.
    static let empty = HTTPBinResponse(args: [:], data: "", files: [:], form: [:])
}

// MARK: - String Helpers

extension String {
    /// Returns a URL-escaped version of the string.
    var urlEscaped: String {
        self.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)!
    }
}

// MARK: - URL Helpers

extension URL {
    /// Creates a random URL with the given file extension.
    static func random(withExtension ext: String) -> URL {
        let directory = FileManager.default.temporaryDirectory
        let name = UUID().uuidString + "." + ext
        return directory.appendingPathComponent(name, isDirectory: false)
    }
}

// MARK: - Test Fixtures

/// A fixture for testing Decodable mapping with dates.
struct Issue: Codable, Equatable {
    let title: String
    let createdAt: Date
    let rating: Float?
    
    enum CodingKeys: String, CodingKey {
        case title
        case createdAt
        case rating
    }
}

/// A fixture for testing optional Decodable mapping.
struct OptionalIssue: Codable {
    let title: String?
    let createdAt: Date?
}

/// A GitHub user model for testing.
struct GitHubUser: Codable, Equatable {
    let login: String
    let id: Int
}

// MARK: - Simple Endpoint Factory

/// Creates a simple test endpoint for Endpoint unit tests.
func makeSimpleEndpoint(
    url: String = "https://api.github.com/zen",
    method: HTTPMethod = .get,
    task: CallTask = .requestPlain,
    sampleData: Data = "Half measures are as bad as nothing at all.".data(using: .utf8)!,
    headers: [String: String]? = ["Title": "Dominar"]
) -> Endpoint {
    Endpoint(
        url: url,
        sampleResponseClosure: { .networkResponse(200, sampleData) },
        method: method,
        task: task,
        httpHeaderFields: headers
    )
}

/// Creates a failure endpoint for testing error cases.
func makeFailureEndpoint(url: String = "https://api.github.com/zen") -> Endpoint {
    let error = NSError(domain: "com.iris.iriserror", code: 0, userInfo: [NSLocalizedDescriptionKey: "Houston, we have a problem"])
    return Endpoint(
        url: url,
        sampleResponseClosure: { .networkError(error) },
        method: .get,
        task: .requestPlain,
        httpHeaderFields: nil
    )
}

// MARK: - Test Image Data

/// Minimal valid PNG image data for testing image mapping.
let testImageData: Data = {
    // Creates a simple 1x1 PNG image
    // PNG header + minimal IHDR + IDAT + IEND
    let pngData: [UInt8] = [
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
        0x00, 0x00, 0x00, 0x0D, // IHDR length
        0x49, 0x48, 0x44, 0x52, // IHDR
        0x00, 0x00, 0x00, 0x01, // width
        0x00, 0x00, 0x00, 0x01, // height
        0x08, 0x02, // bit depth, color type
        0x00, 0x00, 0x00, // compression, filter, interlace
        0x90, 0x77, 0x53, 0xDE, // CRC
        0x00, 0x00, 0x00, 0x0C, // IDAT length
        0x49, 0x44, 0x41, 0x54, // IDAT
        0x08, 0xD7, 0x63, 0xF8, 0xFF, 0xFF, 0xFF, 0x00,
        0x05, 0xFE, 0x02, 0xFE,
        0xA3, 0x6E, 0x93, 0x9C, // CRC
        0x00, 0x00, 0x00, 0x00, // IEND length
        0x49, 0x45, 0x4E, 0x44, // IEND
        0xAE, 0x42, 0x60, 0x82  // CRC
    ]
    return Data(pngData)
}()

// MARK: - DispatchQueue Test Helpers

extension DispatchQueue {
    /// Returns the label of the current dispatch queue.
    class var currentLabel: String? {
        String(validatingUTF8: __dispatch_queue_get_label(nil))
    }
}

// MARK: - Thread-Safe Test Box

/// A thread-safe container for capturing values in `@Sendable` closures during tests.
///
/// Use this to avoid Swift 6 concurrency warnings when capturing mutable state in test closures.
final class SendableBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T
    
    init(_ value: T) {
        self._value = value
    }
    
    var value: T {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _value
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _value = newValue
        }
    }
}

/// A thread-safe array container for capturing values in `@Sendable` closures during tests.
final class SendableArray<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [T] = []
    
    init() {}
    
    var values: [T] {
        lock.lock()
        defer { lock.unlock() }
        return _values
    }
    
    func append(_ value: T) {
        lock.lock()
        defer { lock.unlock() }
        _values.append(value)
    }
    
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return _values.count
    }
    
    subscript(index: Int) -> T {
        lock.lock()
        defer { lock.unlock() }
        return _values[index]
    }
}

// MARK: - URLProtocol Stub

/// Intercepts URLSession traffic so tests can simulate HTTP and transport failures.
final class StubURLProtocol: URLProtocol {
    
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    
    override class func canInit(with request: URLRequest) -> Bool { true }
    
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    
    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    
    override func stopLoading() {}
    
    static func reset() {
        handler = nil
    }
}

func makeStubbedSession() -> Session {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    return Session(configuration: configuration)
}
