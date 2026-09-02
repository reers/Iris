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
- **Configurable**: Global, service-scoped, and per-request configuration options
- **Plugin System**: Intercept and modify requests/responses
- **Stubbing**: First-class support for testing with stubbed responses
- **Full-Featured**: Supports uploads, downloads, multipart form data, and more

## Installation

### Swift Package Manager

Add Iris to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/example/Iris.git", from: "1.0.0")
]
```

Or add it through Xcode:
1. File → Add Package Dependencies...
2. Enter the repository URL
3. Select the version

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
```

## Request Configuration

### Service-Scoped Defaults

Use `IrisService` when different business domains use different base URLs or
defaults. Calls created from a service inherit its configuration while still
allowing per-request overrides.

```swift
// Global defaults for the main API.
Iris.configure(
    IrisConfiguration()
        .baseURL("https://api.example.com")
        .header("Accept", "application/json")
        .timeout(30)
)

// Service defaults for a separate payment API.
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

// Uses the global base URL.
let user = try await Call<User>()
    .path("/users/me")
    .fetch()

// Uses the payment service base URL.
let order = try await PaymentAPI.order(id: "123").fetch()

// Per-request configuration still has the highest priority.
let stagingOrder = try await PaymentAPI.order(id: "123")
    .baseURL("https://pay-staging.example.com")
    .timeout(5)
    .fetch()
```

Configuration priority is:

```text
request > service > global > default
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

Call<Data>()
    .path("/files/document.pdf")
    .download(to: destination)
```

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
response.model           // Decoded model
response.httpResponse    // Underlying HTTPResponse
response.data            // Raw response data
response.request         // Original URLRequest
response.response        // HTTPURLResponse
```

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

## Global and Service Configuration

Configure Iris once at app startup:

```swift
Iris.configure(
    IrisConfiguration()
        .baseURL("https://api.example.com")
        .header("Accept", "application/json")
        .header("X-API-Version", "v1")
        .timeout(30)
        .decoder(customJSONDecoder)
        .encoder(customJSONEncoder)
        .plugin(LoggingPlugin())
        .plugin(AuthPlugin())
)
```

Individual requests can override global settings:

```swift
Call<User>()
    .baseURL("https://other-api.example.com")  // Override base URL
    .timeout(60)                                // Override timeout
    .decoder(customDecoder)                     // Override decoder
```

For larger apps, use `IrisService` to group endpoints that share a different
base URL, headers, or timeout without changing the global configuration.

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

- iOS 13.0+ / macOS 10.15+ / tvOS 13.0+ / watchOS 6.0+ / visionOS 1.0+
- Swift 5.9+
- Xcode 15.0+

## Dependencies

- [Alamofire](https://github.com/Alamofire/Alamofire) 5.8+

## License

Iris is available under the MIT license. See the [LICENSE](LICENSE) file for more info.

## Acknowledgments

Iris is inspired by [Moya](https://github.com/Moya/Moya), a fantastic networking abstraction layer for Swift. Many concepts and patterns are borrowed from Moya's excellent design.
