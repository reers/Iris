//
//  Configuration.swift
//  Iris
//
//  Global configuration for the Iris networking library.
//

import Foundation
import Alamofire

/// Global configuration for Iris networking.
///
/// `IrisConfiguration` provides centralized settings that apply to all requests
/// made through Iris. These include default headers, timeout, JSON coders,
/// plugins, and stubbing behavior.
///
/// Example:
/// ```swift
/// // Configure Iris at app startup
/// Iris.configure(
///     IrisConfiguration()
///         .baseURL("https://api.example.com")
///         .header("Accept", "application/json")
///         .header("X-API-Version", "v1")
///         .timeout(30)
///         .plugin(LoggingPlugin())
///         .plugin(AuthPlugin())
/// )
/// ```
public struct IrisConfiguration {
    
    /// The base URL for all requests.
    ///
    /// Individual requests can override this with their own base URL.
    public var baseURL: URL?
    
    /// Default headers to include in all requests.
    ///
    /// Request-specific headers will be merged with these, with request headers
    /// taking precedence in case of conflicts.
    public var defaultHeaders: [String: String]
    
    /// Default timeout interval for requests in seconds.
    ///
    /// Used when a request does not set its own timeout. Defaults to 30.
    public var defaultTimeout: TimeInterval
    
    /// The JSON decoder used for response parsing.
    ///
    /// Configure this to customize date decoding strategies, key decoding, etc.
    public var jsonDecoder: JSONDecoder
    
    /// The JSON encoder used for Encodable request bodies and Encodable stubs.
    ///
    /// Used when a request does not pass its own encoder. Configure this to
    /// customize date encoding strategies, key encoding, etc.
    public var jsonEncoder: JSONEncoder
    
    /// The list of plugins to apply to all requests.
    ///
    /// Plugins are called in order for request preparation and in reverse order
    /// for response processing.
    public var plugins: [PluginType]
    
    /// The Alamofire session used for network requests.
    ///
    /// Configure this to customize SSL pinning, caching, cookie handling, etc.
    public var session: Session
    
    /// The stub behavior for all requests.
    ///
    /// Set to a non-nil value to enable stubbing globally. Individual requests
    /// can override this setting.
    public var stubBehavior: StubBehavior?
    
    /// Creates a new configuration with default values.
    ///
    /// - Parameters:
    ///   - baseURL: The base URL for requests. Default is nil.
    ///   - defaultHeaders: Default headers for all requests. Default is empty.
    ///   - defaultTimeout: Request timeout in seconds. Default is 30.
    ///   - jsonDecoder: The JSON decoder. Default is a new `JSONDecoder`.
    ///   - jsonEncoder: The JSON encoder. Default is a new `JSONEncoder`.
    ///   - plugins: The plugin list. Default is empty.
    ///   - session: The Alamofire session. Default is `Session.default`.
    ///   - stubBehavior: The stub behavior. Default is nil (no stubbing).
    public init(
        baseURL: URL? = nil,
        defaultHeaders: [String: String] = [:],
        defaultTimeout: TimeInterval = 30,
        jsonDecoder: JSONDecoder = JSONDecoder(),
        jsonEncoder: JSONEncoder = JSONEncoder(),
        plugins: [PluginType] = [],
        session: Session = Session.default,
        stubBehavior: StubBehavior? = nil
    ) {
        self.baseURL = baseURL
        self.defaultHeaders = defaultHeaders
        self.defaultTimeout = defaultTimeout
        self.jsonDecoder = jsonDecoder
        self.jsonEncoder = jsonEncoder
        self.plugins = plugins
        self.session = session
        self.stubBehavior = stubBehavior
    }
}

// MARK: - Global Configuration

public extension Iris {
    
    /// The global configuration instance.
    ///
    /// This configuration applies to all requests made through Iris.
    static var configuration = IrisConfiguration()
    
    /// Replaces the global configuration.
    ///
    /// - Parameter configuration: The new configuration to use.
    static func configure(_ configuration: IrisConfiguration) {
        self.configuration = configuration
    }
}

// MARK: - Configuration Builder

public extension IrisConfiguration {
    
    /// Sets the base URL from a URL object.
    ///
    /// - Parameter url: The base URL.
    /// - Returns: A new configuration with the updated base URL.
    func baseURL(_ url: URL?) -> IrisConfiguration {
        var config = self
        config.baseURL = url
        return config
    }
    
    /// Sets the base URL from a string.
    ///
    /// - Parameter urlString: The base URL string.
    /// - Returns: A new configuration with the updated base URL.
    func baseURL(_ urlString: String) -> IrisConfiguration {
        var config = self
        config.baseURL = URL(string: urlString)
        return config
    }
    
    /// Adds a default header.
    ///
    /// - Parameters:
    ///   - key: The header field name.
    ///   - value: The header field value.
    /// - Returns: A new configuration with the added header.
    func header(_ key: String, _ value: String) -> IrisConfiguration {
        var config = self
        config.defaultHeaders[key] = value
        return config
    }
    
    /// Merges additional default headers.
    ///
    /// - Parameter headers: The headers to merge. Existing headers with the same
    ///   keys will be overwritten.
    /// - Returns: A new configuration with the merged headers.
    func headers(_ headers: [String: String]) -> IrisConfiguration {
        var config = self
        config.defaultHeaders.merge(headers) { _, new in new }
        return config
    }
    
    /// Sets the default timeout.
    ///
    /// - Parameter timeout: The timeout in seconds.
    /// - Returns: A new configuration with the updated timeout.
    func timeout(_ timeout: TimeInterval) -> IrisConfiguration {
        var config = self
        config.defaultTimeout = timeout
        return config
    }
    
    /// Adds a plugin to the plugin list.
    ///
    /// - Parameter plugin: The plugin to add.
    /// - Returns: A new configuration with the added plugin.
    func plugin(_ plugin: PluginType) -> IrisConfiguration {
        var config = self
        config.plugins.append(plugin)
        return config
    }
    
    /// Adds multiple plugins to the plugin list.
    ///
    /// - Parameter plugins: The plugins to add.
    /// - Returns: A new configuration with the added plugins.
    func plugins(_ plugins: [PluginType]) -> IrisConfiguration {
        var config = self
        config.plugins.append(contentsOf: plugins)
        return config
    }
    
    /// Sets the Alamofire session.
    ///
    /// - Parameter session: The session to use.
    /// - Returns: A new configuration with the updated session.
    func session(_ session: Session) -> IrisConfiguration {
        var config = self
        config.session = session
        return config
    }
    
    /// Sets the stub behavior.
    ///
    /// - Parameter behavior: The stub behavior to use.
    /// - Returns: A new configuration with the updated stub behavior.
    func stub(_ behavior: StubBehavior) -> IrisConfiguration {
        var config = self
        config.stubBehavior = behavior
        return config
    }
    
    /// Sets the JSON decoder.
    ///
    /// - Parameter decoder: The decoder to use.
    /// - Returns: A new configuration with the updated decoder.
    func decoder(_ decoder: JSONDecoder) -> IrisConfiguration {
        var config = self
        config.jsonDecoder = decoder
        return config
    }
    
    /// Sets the JSON encoder used for Encodable request bodies and stubs.
    ///
    /// - Parameter encoder: The encoder to use.
    /// - Returns: A new configuration with the updated encoder.
    func encoder(_ encoder: JSONEncoder) -> IrisConfiguration {
        var config = self
        config.jsonEncoder = encoder
        return config
    }
}

// MARK: - Stub Behavior

/// Controls how stub responses are returned.
///
/// Stub behavior determines when stubbed responses are returned during testing.
/// Use this to simulate different network conditions.
public enum StubBehavior {
    
    /// Return a response immediately without any delay.
    case immediate
    
    /// Return a response after the specified delay.
    ///
    /// - Parameter seconds: The delay in seconds before returning the response.
    case delayed(TimeInterval)
}
