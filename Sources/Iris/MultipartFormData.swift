//
//  MultipartFormData.swift
//  Iris
//
//  Represents multipart/form-data for file uploads.
//  Based on Moya's MultipartFormData.
//

import Foundation
import Alamofire

/// Represents "multipart/form-data" for an upload.
///
/// `MultipartFormData` encapsulates the data needed to build a multipart form
/// request. It consists of multiple body parts, each representing a form field
/// or file to upload.
///
/// Example:
/// ```swift
/// // Upload an image with form fields
/// let formData = MultipartFormData(parts: [
///     MultipartFormBodyPart(
///         provider: .data(imageData),
///         name: "avatar",
///         fileName: "avatar.jpg",
///         mimeType: "image/jpeg"
///     ),
///     MultipartFormBodyPart(
///         provider: .data("John".data(using: .utf8)!),
///         name: "name"
///     )
/// ])
///
/// let response = try await Call<User>()
///     .path("/users/1/avatar")
///     .method(.post)
///     .upload(multipart: formData)
///     .fire()
/// ```
public struct MultipartFormData: Hashable {

    /// Method to provide the form data.
    ///
    /// This enum represents the different ways data can be provided for a
    /// multipart form body part.
    public enum FormDataProvider: Hashable {
        
        /// Data from memory.
        ///
        /// - Parameter data: The data to upload.
        case data(Foundation.Data)
        
        /// Data from a file URL.
        ///
        /// - Parameter url: The local file URL.
        case file(URL)
        
        /// Data from an input stream with a known length.
        ///
        /// - Parameters:
        ///   - stream: The input stream.
        ///   - length: The total length of the stream in bytes.
        case stream(InputStream, UInt64)
    }

    /// The `FileManager` to use for file operations.
    ///
    /// Defaults to `FileManager.default`.
    public let fileManager: FileManager

    /// The boundary string that separates parts in the encoded form data.
    ///
    /// If nil, a random boundary will be generated.
    public let boundary: String?

    /// The body parts that make up this form data.
    public let parts: [MultipartFormBodyPart]

    /// Creates a new multipart form data.
    ///
    /// - Parameters:
    ///   - fileManager: The file manager for file operations. Default is `.default`.
    ///   - boundary: The boundary string. Default is nil (auto-generated).
    ///   - parts: The body parts to include.
    public init(fileManager: FileManager = .default, boundary: String? = nil, parts: [MultipartFormBodyPart]) {
        self.fileManager = fileManager
        self.boundary = boundary
        self.parts = parts
    }
}

// MARK: - ExpressibleByArrayLiteral

extension MultipartFormData: ExpressibleByArrayLiteral {
    
    /// Creates multipart form data from an array literal of body parts.
    ///
    /// - Parameter elements: The body parts.
    public init(arrayLiteral elements: MultipartFormBodyPart...) {
        self.init(parts: elements)
    }
}

// MARK: - MultipartFormBodyPart

/// Represents a single part of "multipart/form-data" for an upload.
///
/// Each body part represents either a form field or a file to upload.
/// The `provider` determines how the data is supplied (from memory, file, or stream).
public struct MultipartFormBodyPart: Hashable {

    /// Creates a new body part.
    ///
    /// - Parameters:
    ///   - provider: How the data is provided.
    ///   - name: The form field name.
    ///   - fileName: The file name for file uploads. Optional.
    ///   - mimeType: The MIME type of the data. Optional.
    public init(provider: MultipartFormData.FormDataProvider, name: String, fileName: String? = nil, mimeType: String? = nil) {
        self.provider = provider
        self.name = name
        self.fileName = fileName
        self.mimeType = mimeType
    }

    /// The method being used for providing form data.
    public let provider: MultipartFormData.FormDataProvider

    /// The form field name.
    public let name: String

    /// The file name for file uploads.
    ///
    /// This is used in the Content-Disposition header.
    public let fileName: String?

    /// The MIME type of the data.
    ///
    /// For example: "image/jpeg", "application/pdf", "text/plain".
    public let mimeType: String?

}

// MARK: - RequestMultipartFormData Appending

internal extension RequestMultipartFormData {
    
    /// Appends data to the multipart form.
    ///
    /// - Parameters:
    ///   - data: The data to append.
    ///   - bodyPart: The body part configuration.
    func append(data: Data, bodyPart: MultipartFormBodyPart) {
        append(data, withName: bodyPart.name, fileName: bodyPart.fileName, mimeType: bodyPart.mimeType)
    }

    /// Appends a file URL to the multipart form.
    ///
    /// - Parameters:
    ///   - url: The file URL.
    ///   - bodyPart: The body part configuration.
    func append(fileURL url: URL, bodyPart: MultipartFormBodyPart) {
        if let fileName = bodyPart.fileName, let mimeType = bodyPart.mimeType {
            append(url, withName: bodyPart.name, fileName: fileName, mimeType: mimeType)
        } else {
            append(url, withName: bodyPart.name)
        }
    }

    /// Appends a stream to the multipart form.
    ///
    /// - Parameters:
    ///   - stream: The input stream.
    ///   - length: The stream length.
    ///   - bodyPart: The body part configuration.
    func append(stream: InputStream, length: UInt64, bodyPart: MultipartFormBodyPart) {
        append(stream, withLength: length, name: bodyPart.name, fileName: bodyPart.fileName ?? "", mimeType: bodyPart.mimeType ?? "")
    }

    /// Applies Iris multipart form data to this Alamofire multipart form.
    ///
    /// - Parameter multipartFormData: The Iris multipart form data to apply.
    func applyMoyaMultipartFormData(_ multipartFormData: MultipartFormData) {
        for bodyPart in multipartFormData.parts {
            switch bodyPart.provider {
            case .data(let data):
                append(data: data, bodyPart: bodyPart)
            case .file(let url):
                append(fileURL: url, bodyPart: bodyPart)
            case .stream(let stream, let length):
                append(stream: stream, length: length, bodyPart: bodyPart)
            }
        }
    }
}
