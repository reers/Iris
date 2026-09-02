//
//  CallTask.swift
//  Iris
//
//  Defines the different types of HTTP tasks that can be performed.
//  Based on Moya's Task enum.
//

import Foundation

/// Represents an HTTP task to be performed.
///
/// A `CallTask` describes how the body and parameters of an HTTP request should be
/// configured. Different task types support different use cases like plain requests,
/// parameter encoding, file uploads, and downloads.
///
/// Example:
/// ```swift
/// // Plain request with no body
/// .requestPlain
///
/// // Request with JSON body
/// .requestParameters(parameters: ["name": "John"], encoding: JSONEncoding.default)
///
/// // File upload
/// .uploadFile(URL(fileURLWithPath: "/path/to/file"))
///
/// // Multipart form data
/// .uploadMultipartFormData(formData)
/// ```
public enum CallTask {

    /// A request with no additional data.
    ///
    /// Use this for simple GET requests or requests that don't need a body.
    case requestPlain

    /// A request with the body set with raw data.
    ///
    /// - Parameter data: The raw data to send as the request body.
    case requestData(Data)

    /// A request with the body set with an `Encodable` type using the global JSON encoder.
    ///
    /// The encodable object will be serialized to JSON using `IrisConfiguration.jsonEncoder`.
    ///
    /// - Parameter encodable: The object to encode as the request body.
    case requestJSONEncodable(Encodable)

    /// A request with the body set with an `Encodable` type using a custom encoder.
    ///
    /// - Parameters:
    ///   - encodable: The object to encode as the request body.
    ///   - encoder: The custom `JSONEncoder` to use.
    case requestCustomJSONEncodable(Encodable, encoder: JSONEncoder)

    /// A request with the body set with encoded parameters.
    ///
    /// The parameters will be encoded according to the specified encoding strategy.
    ///
    /// - Parameters:
    ///   - parameters: The parameters dictionary.
    ///   - encoding: The parameter encoding strategy (e.g., `URLEncoding`, `JSONEncoding`).
    case requestParameters(parameters: [String: Any], encoding: ParameterEncoding)

    /// A request with raw data body combined with URL query parameters.
    ///
    /// - Parameters:
    ///   - bodyData: The raw data to send as the request body.
    ///   - urlParameters: Parameters to append to the URL as query string.
    case requestCompositeData(bodyData: Data, urlParameters: [String: Any])

    /// A request with encoded body parameters combined with URL query parameters.
    ///
    /// - Parameters:
    ///   - bodyParameters: Parameters for the request body.
    ///   - bodyEncoding: Encoding strategy for body parameters.
    ///   - urlParameters: Parameters to append to the URL as query string.
    case requestCompositeParameters(bodyParameters: [String: Any], bodyEncoding: ParameterEncoding, urlParameters: [String: Any])

    /// A file upload task.
    ///
    /// The file at the specified URL will be uploaded.
    ///
    /// - Parameter fileURL: The local file URL to upload.
    case uploadFile(URL)

    /// A "multipart/form-data" upload task.
    ///
    /// Use this for uploading files along with form fields.
    ///
    /// - Parameter formData: The multipart form data to upload.
    case uploadMultipartFormData(MultipartFormData)

    /// A "multipart/form-data" upload task combined with URL query parameters.
    ///
    /// - Parameters:
    ///   - formData: The multipart form data to upload.
    ///   - urlParameters: Parameters to append to the URL as query string.
    case uploadCompositeMultipartFormData(MultipartFormData, urlParameters: [String: Any])

    /// A file download task to a destination.
    ///
    /// The downloaded file will be saved to the location specified by the destination closure.
    ///
    /// - Parameter destination: A closure that determines where to save the downloaded file.
    case downloadDestination(DownloadDestination)

    /// A file download task to a destination with extra parameters.
    ///
    /// - Parameters:
    ///   - parameters: Parameters to include in the download request.
    ///   - encoding: The parameter encoding strategy.
    ///   - destination: A closure that determines where to save the downloaded file.
    case downloadParameters(parameters: [String: Any], encoding: ParameterEncoding, destination: DownloadDestination)
}
