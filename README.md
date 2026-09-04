# Iris

[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%20|%20macOS%20|%20tvOS%20|%20watchOS%20|%20visionOS-blue.svg)](https://developer.apple.com)
[![Swift Package Manager](https://img.shields.io/badge/Swift%20Package%20Manager-compatible-brightgreen.svg)](https://swift.org/package-manager/)
[![License](https://img.shields.io/badge/License-MIT-lightgrey.svg)](LICENSE)

A modern, type-safe networking library for Swift featuring async/await and a chainable API.

## Overview

Iris is a networking library built on top of [Alamofire](https://github.com/Alamofire/Alamofire) and inspired by [Moya](https://github.com/Moya/Moya). It provides a clean, chainable API for building and executing network requests with full async/await support.

### Key Features

- **Chainable API**: Build requests using a fluent, chainable syntax
- **Type-Safe**: Generic response types ensure compile-time safety
- **Async/Await**: Modern Swift concurrency support out of the box
- **Callbacks**: Thin `send` / `fetch` completion wrappers for existing callback call sites
- **Progress**: Upload and download `Progress` as recipe handlers or `send { session in }` streams
- **HTTP Streaming**: `stream()` with `onChunk` or `session.chunks`
- **Configurable**: Global, service-scoped, and per-request configuration options
- **Plugin System**: Intercept and modify requests/responses
- **Stubbing**: First-class support for testing with stubbed responses
- **Full-Featured**: Supports uploads, downloads, multipart form data, and more

## Installation

### Swift Package Manager

Add Iris to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/reers/Iris.git", from: "1.0.0")
]
```

Or add it through Xcode:
1. File → Add Package Dependencies...
2. Enter the repository URL
3. Select the version

Iris requires **Swift 5.9+** and:

| Platform | Minimum |
|---|---|
| iOS / iPadOS / Mac Catalyst | 13.0 |
| macOS | 10.15 |
| tvOS | 13.0 |
| watchOS | 6.0 |
| visionOS | 1.0 |

`AsyncStream` (used by `send { session in }`) shipped in **Swift 5.5** and Apple makes it available on the same OS versions as the table above. It does not raise Iris’s deployment target.

## Quick Start

### Basic Usage

```swift
import Iris

// Configure Iris at app startup
Iris.configure(
    IrisConfiguration()
        .baseURL("https://api.example.com")
        .header("Accept", "application/json")
)

// Define your model
struct User: Codable {
    let id: Int
    let name: String
}

// Make a request
let user = try await Call<User>()
    .path("/users/1")
    .method(.get)
    .fetch()

print(user.name)
```

### Defining API Endpoints

Iris encourages defining your API endpoints as static factory methods on `Call`:

```swift
extension Call {
    /// Fetches a user by ID.
    static func getUser(id: Int) -> Call<User> {
        Call<User>()
            .path("/users/\(id)")
            .method(.get)
            .validateSuccessCodes()
    }
    
    /// Creates a new user.
    static func createUser(name: String, email: String) -> Call<User> {
        Call<User>()
            .path("/users")
            .method(.post)
            .body(["name": name, "email": email])
            .validateSuccessCodes()
    }
    
    /// Uploads a user's avatar.
    static func uploadAvatar(userId: Int, imageData: Data) -> Call<User> {
        Call<User>()
            .path("/users/\(userId)/avatar")
            .method(.post)
            .upload(multipart: [
                MultipartFormBodyPart(
                    provider: .data(imageData),
                    name: "avatar",
                    fileName: "avatar.jpg",
                    mimeType: "image/jpeg"
                )
            ])
            .timeout(60)
    }
}
```

### Using the API

```swift
// Method 1: fetch() - Returns the decoded model directly
let user = try await Call<User>.getUser(id: 123).fetch()

// Method 2: send() - Returns Response<Model> with metadata
let response = try await Call<User>.getUser(id: 123).send()
print("Status: \(response.statusCode)")
print("User: \(response.model.name)")

// Access convenience properties
if response.isSuccess {
    let user = try response.unwrap()
}

// Raw body, no JSON decoding — equivalent to Far's GET/POST<…, Data>
let bytes = try await Call.data()
    .path("/v1/shield")
    .method(.post)
    .body(["userId": 1])
    .fetch()

// UTF-8 body, no JSON decoding — equivalent to Far's Returns == String
let text = try await Call.string()
    .path("/zen")
    .fetch()

// Callback-style send — thin wrapper over send()/fetch()
Call<User>()
    .path("/users/1")
    .send { result in
        switch result {
        case .success(let response): print(response.model.name)
        case .failure(let error): print(error)
        }
    }

Call<Media>()
    .path("/v1/media")
    .upload(multipart: parts)
    .onUploadProgress { progress in
        print(progress.fractionCompleted)
    }
    .send { result in
        _ = try? result.get()
    }

Call.data()
    .path("/v1/ai/complete")
    .method(.post)
    .body(["prompt": "hi"])
    .stream()
    .onChunk { data in
        print(String(data: data, encoding: .utf8) ?? "")
    }
    .send { _ in }

// Concurrency sidecars — live session does not escape the closure
let media = try await Call<Media>()
    .path("/v1/media")
    .upload(multipart: parts)
    .send { session in
        for await progress in session.uploadProgress {
            print(progress.fractionCompleted)
        }
    }
```

## Request Configuration

Defaults can be set at three levels. A later level wins on the same key:

```text
per-request  >  IrisService (business module)  >  Iris.configure (global)  >  built-in default
```

Headers are merged in that order (request keys overwrite service keys, which overwrite global keys). Timeout and base URL are replaced, not merged.

### Global defaults

Call `Iris.configure` once at app launch. Every `Call` that does not set its own value uses this:

```swift
Iris.configure(
    IrisConfiguration()
        .baseURL("https://api.example.com")
        .header("Accept", "application/json")
        .header("X-API-Version", "v1")
        .timeout(30)
        .decoder(JSONDecoder())
        .encoder(JSONEncoder())
        .plugin(LoggingPlugin())
        // .session(customAlamofireSession)  // pinning, interceptors, …
)
```

Bare `Call<User>().path("/users/me")` then hits `https://api.example.com/users/me`.

An absolute `path` (scheme + host) does not use any base URL:

```swift
try await Call<User>()
    .path("https://cdn.example.com/profile.json")
    .fetch()
```

### Service-scoped defaults (business modules)

Use `IrisService` when a domain has its own host, headers, or timeout — payment, IM, a BFF — sitting between global config and a single request.

```swift
enum PaymentAPI {
    static let service = IrisService(
        baseURL: "https://pay.example.com",
        headers: ["X-Business": "payment"],
        timeout: 15
    )
    
    static func order(id: String) -> Call<Order> {
        service.call(Order.self)
            .path("/orders/\(id)")
            .method(.get)
    }
}

enum MediaAPI {
    static let service = IrisService(
        baseURL: "https://media.example.com",
        timeout: 60
    )
    
    static func upload(_ parts: [MultipartFormBodyPart]) -> Call<Media> {
        service.call(Media.self)
            .path("/v1/media")
            .method(.post)
            .upload(multipart: parts)
    }
}

// Global base URL + headers.
let user = try await Call<User>()
    .path("/users/me")
    .fetch()

// Payment host + X-Business; timeout 15s.
let order = try await PaymentAPI.order(id: "123").fetch()
```

`service.call(Model.self)` copies the service onto the `Call`. Other chain methods (`.path`, `.body`, `.validateSuccessCodes()`, …) are unchanged.

### Per-request overrides

Anything set on the `Call` beats service and global:

```swift
let stagingOrder = try await PaymentAPI.order(id: "123")
    .baseURL("https://pay-staging.example.com")
    .header("X-Debug", "1")
    .timeout(5)
    .fetch()
```

```swift
Call<User>()
    .baseURL("https://api-staging.example.com")  // this request only
    .timeout(60)
    .decoder(customDecoder)
```

### HTTP Methods

```swift
Call<User>()
    .method(.get)      // GET (default)
    .method(.post)     // POST
    .method(.put)      // PUT
    .method(.delete)   // DELETE
    .method(.patch)    // PATCH
```

### Headers

```swift
Call<User>()
    .headers(["Content-Type": "application/json"])
    .header("X-Custom", "value")
    .authorization("Basic abc123")
    .bearerToken("your-jwt-token")
```

### Request Body

```swift
// JSON dictionary
Call<User>()
    .body(["name": "John", "email": "john@example.com"])

// Encodable object
struct CreateUser: Encodable {
    let name: String
    let email: String
}
Call<User>()
    .body(CreateUser(name: "John", email: "john@example.com"))

// Raw data
Call<Empty>()
    .body(someData)

// Form URL-encoded
Call<User>()
    .formBody(["username": "john", "password": "secret"])

// URL query parameters
Call<[User]>()
    .query(["page": 1, "limit": 10])

// Combined URL parameters and body
Call<User>()
    .composite(query: ["version": "v2"], body: ["name": "John"])
```

### File Upload

```swift
// Single file upload
Call<Response>()
    .upload(file: fileURL)

// Multipart form data
Call<Response>()
    .upload(multipart: [
        MultipartFormBodyPart(
            provider: .data(imageData),
            name: "image",
            fileName: "photo.jpg",
            mimeType: "image/jpeg"
        ),
        MultipartFormBodyPart(
            provider: .data("Description".data(using: .utf8)!),
            name: "description"
        )
    ])
```

### File Download

```swift
let destination: DownloadDestination = { temporaryURL, response in
    let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let fileURL = documentsURL.appendingPathComponent(response.suggestedFilename!)
    return (fileURL, [.removePreviousFile, .createIntermediateDirectories])
}

Call.data()
    .path("/files/document.pdf")
    .download(to: destination)
```

### Progress and HTTP streaming

Progress and body chunks are **sidecars**: they do not change `send()`’s return type (`Response`). There are two ways to observe them. Use **one style per sidecar** at a given call site (do not both `onUploadProgress` and `for await session.uploadProgress` for the same HUD).

Both styles share one probe. `onComplete` and plugins still run once at the end.

#### Handler (GCD)

For call sites that cannot be `async` (UIKit actions, existing completion-style managers). Closures default to the main queue.

```swift
Call<Media>()
    .path("/v1/media")
    .upload(multipart: parts)
    .onUploadProgress { progress in
        print(progress.fractionCompleted)
    }
    .send { result in
        _ = try? result.get()
    }

Call.data()
    .path("/files/document.pdf")
    .download(to: destination)
    .onDownloadProgress { progress in
        print(progress.fractionCompleted)
    }
    .send { _ in }

Call.data()
    .path("/v1/ai/complete")
    .method(.post)
    .body(["prompt": "hi"])
    .stream()
    .onChunk { data in
        print(String(data: data, encoding: .utf8) ?? "")
    }
    .send { result in
        _ = try? result.get().model   // concatenated body as Data
    }
```

Progress uses Foundation `Progress`. When `Content-Length` is missing, `fractionCompleted` may stay `0`.

`stream()` applies to data tasks only — not file upload or file download. Mark the recipe with `stream()` so chunks are delivered; `Empty` discards the concatenated body, `Data` / `String` keep it as the raw model, other `Decodable` types JSON-decode the concatenation.

#### AsyncStream (Swift concurrency)

For `async` call sites. `send { session in }` starts the request, lets `body` consume streams, then always returns `Response`. The live `CallSession` must not be stored outside the closure.

`for await` needs an `async` context. `AsyncStream` is a **Swift 5.5** API (`SE-0314`). On Apple platforms it is available from **iOS 13 / macOS 10.15 / tvOS 13 / watchOS 6 / visionOS 1** — the same versions Iris already requires, so enabling streams does not bump the OS minimum.

```swift
let response = try await Call<Media>()
    .path("/v1/media")
    .upload(multipart: parts)
    .send { session in
        for await progress in session.uploadProgress {
            print(progress.fractionCompleted)
        }
    }

let downloaded = try await Call.data()
    .path("/files/document.pdf")
    .download(to: destination)
    .send { session in
        for await progress in session.downloadProgress {
            print(progress.fractionCompleted)
        }
    }

let streamed = try await Call.data()
    .path("/v1/ai/complete")
    .method(.post)
    .body(["prompt": "hi"])
    .stream()
    .send { session in
        for await chunk in session.chunks {
            print(String(data: chunk, encoding: .utf8) ?? "")
        }
    }
```

`try await send()` with no closure is the same engine with an empty body: you get `Response` and skip the streams.

### Validation

```swift
Call<User>()
    .validateSuccessCodes()              // Accept only 2xx
    .validateSuccessAndRedirectCodes()   // Accept 2xx and 3xx
    .validate(statusCodes: [200, 201])   // Accept specific codes
    .validate(.none)                     // Accept all (default)
```

### Timeout

```swift
Call<User>()
    .timeout(60)  // 60 seconds
```

## Response Handling

### Response Properties

```swift
let response = try await request.send()

// Status information
response.statusCode      // HTTP status code
response.isSuccess       // true if 2xx
response.isRedirect      // true if 3xx
response.isClientError   // true if 4xx
response.isServerError   // true if 5xx

// Data access
response.model           // Decoded model (`Data`/`String` are the raw body)
response.httpResponse    // Underlying HTTPResponse
response.data            // Raw response data
response.request         // Original URLRequest
response.response        // HTTPURLResponse
```

### Raw `Data` and `String`

`Call<Data>` and `Call<String>` skip JSON decoding. The model is the HTTP body
as received — the same as Far's `GET/POST<…, Data>` / `Returns == String`.

```swift
// Binary or opaque JSON you will parse yourself
let data = try await Call.data()
    .path("/v1/history-messages")
    .query(["uid": 1])
    .fetch()

// Plain text (not a JSON string value)
let zen = try await Call.string()
    .path("/zen")
    .fetch()
```

Use `Call.empty()` when the body should be discarded. Use a `Decodable` model
when the body is JSON you want Iris to decode.

### Response Mapping

```swift
let response = try await request.send()

// Get the model
let user = try response.unwrap()

// Map to different types
let json = try response.mapJSON()
let string = try response.mapString()
let image = try response.mapImage()

// Map with key path
let user = try response.map(User.self, atKeyPath: "data.user")

// Filter by status code
let filtered = try response.filterSuccessfulStatusCodes()
```

See [Request Configuration](#request-configuration) for global `Iris.configure`, per-module `IrisService`, and per-request overrides.

## Plugins

Plugins allow you to intercept requests at various lifecycle points:

```swift
class LoggingPlugin: PluginType {
    func prepare(_ request: URLRequest, target: TargetType) -> URLRequest {
        // Modify request before sending
        print("Preparing: \(request.url?.absoluteString ?? "")")
        return request
    }
    
    func willSend(_ request: CallType, target: TargetType) {
        // Called just before request is sent
        print("Sending request to: \(target.path)")
    }
    
    func didReceive(_ result: Result<HTTPResponse, IrisError>, target: TargetType) {
        // Called after response is received
        switch result {
        case .success(let response):
            print("Received: \(response.statusCode)")
        case .failure(let error):
            print("Error: \(error)")
        }
    }
    
    func process(_ result: Result<HTTPResponse, IrisError>, target: TargetType) -> Result<HTTPResponse, IrisError> {
        // Transform the result before returning
        return result
    }
}
```

### Common Plugin Use Cases

- **Authentication**: Inject auth tokens into requests
- **Logging**: Log requests and responses
- **Activity Indicator**: Show/hide network activity
- **Error Handling**: Transform or handle specific errors
- **Caching**: Implement custom caching logic
- **Retry Logic**: Implement automatic retries

## Testing with Stubs

Iris provides first-class support for stubbing responses:

```swift
// Enable stubbing globally
Iris.configure(
    IrisConfiguration()
        .baseURL("https://api.example.com")
        .stub(.immediate)  // or .delayed(0.5)
)

// Provide stub data per request
let user = try await Call<User>()
    .path("/users/1")
    .stub(User(id: 1, name: "Test User"))  // From Encodable
    .stub(behavior: .immediate)
    .fetch()

// Or use raw data/string
Call<User>()
    .stub("{\"id\": 1, \"name\": \"Test\"}".data(using: .utf8)!)
    .stub("{\"id\": 1, \"name\": \"Test\"}")  // From string
```

### Stub in Tests

```swift
class UserServiceTests: XCTestCase {
    override func setUp() {
        Iris.configure(IrisConfiguration().stub(.immediate))
    }
    
    func testGetUser() async throws {
        let user = try await Call<User>()
            .path("/users/1")
            .stub(User(id: 1, name: "Test"))
            .fetch()
        
        XCTAssertEqual(user.name, "Test")
    }
}
```

## Error Handling

```swift
do {
    let user = try await request.fetch()
} catch let error as IrisError {
    switch error {
    case .statusCode(let response):
        print("HTTP Error: \(response.statusCode)")
        // Access response body for error details
        if let errorMessage = try? response.mapString() {
            print("Error message: \(errorMessage)")
        }
        
    case .objectMapping(let decodingError, let response):
        print("Decoding failed: \(decodingError)")
        
    case .underlying(let networkError, _):
        print("Network error: \(networkError)")
        
    case .requestMapping(let url):
        print("Invalid URL: \(url)")
        
    default:
        print("Other error: \(error)")
    }
}
```

## Type Aliases

```swift
// Undecoded HTTP response used by plugins and IrisError.
let httpResponse: HTTPResponse

// Create a request without response parsing
let request = Call.empty()
```

## Requirements

- Swift 5.9+ / Xcode 15.0+
- iOS 13.0+ / macOS 10.15+ / tvOS 13.0+ / watchOS 6.0+ / visionOS 1.0+

`AsyncStream` (`for await session.uploadProgress` / `session.chunks`) is a Swift 5.5 standard-library type. Apple’s availability is iOS 13 / macOS 10.15 / tvOS 13 / watchOS 6 / visionOS 1, so it does not raise Iris’s minimum OS. Handler APIs (`onUploadProgress`, `onChunk`) have no extra concurrency requirement.

## Dependencies

- [Alamofire](https://github.com/Alamofire/Alamofire) 5.8+

## License

Iris is available under the MIT license. See the [LICENSE](LICENSE) file for more info.

## Acknowledgments

Iris is inspired by [Moya](https://github.com/Moya/Moya), a fantastic networking abstraction layer for Swift. Many concepts and patterns are borrowed from Moya's excellent design.
