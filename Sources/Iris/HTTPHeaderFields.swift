//
//  HTTPHeaderFields.swift
//  Iris
//
//  Case-insensitive HTTP header field helpers.
//

import Foundation

extension Dictionary where Key == String, Value == String {

    mutating func setHTTPHeaderField(_ name: String, value: String) {
        if let existingKey = keys.first(where: { $0.compare(name, options: .caseInsensitive) == .orderedSame }) {
            self[existingKey] = value
        } else {
            self[name] = value
        }
    }

    mutating func mergeHTTPHeaderFields(_ fields: [String: String]) {
        for (name, value) in fields {
            setHTTPHeaderField(name, value: value)
        }
    }
}
