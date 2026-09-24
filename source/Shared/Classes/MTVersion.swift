/*
    MTVersion.swift
    Copyright 2026 SAP SE
     
    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at
     
    http://www.apache.org/licenses/LICENSE-2.0
     
    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.
*/

import Foundation

nonisolated enum MTVersion {

    static func normalized(from rawValue: String) -> String? {
        let filtered = rawValue.map { character -> Character in
            if character.isNumber || character == "." {
                return character
            } else {
                return " "
            }
        }

        let candidate = String(filtered)
            .components(separatedBy: .whitespacesAndNewlines)
            .first { $0.contains(where: \.isNumber) } ?? ""

        guard !candidate.isEmpty else {
            return nil
        }

        let trimmedDots = candidate.trimmingCharacters(in: CharacterSet(charactersIn: "."))

        guard !trimmedDots.isEmpty else {
            return nil
        }

        let components = trimmedDots
            .split(separator: ".", omittingEmptySubsequences: true)

        guard !components.isEmpty else {
            return nil
        }

        let normalizedComponents = components.compactMap { component -> String? in
            guard let intValue = Int(component) else {
                return nil
            }

            return String(intValue)
        }

        guard normalizedComponents.count == components.count else {
            return nil
        }

        return normalizedComponents.joined(separator: ".")
    }

    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let lhsComponents = lhs.split(separator: ".").compactMap { Int($0) }
        let rhsComponents = rhs.split(separator: ".").compactMap { Int($0) }
        let maxCount = max(lhsComponents.count, rhsComponents.count)

        for index in 0..<maxCount {
            let lhsValue = index < lhsComponents.count ? lhsComponents[index] : 0
            let rhsValue = index < rhsComponents.count ? rhsComponents[index] : 0

            if lhsValue < rhsValue {
                return .orderedAscending
            }

            if lhsValue > rhsValue {
                return .orderedDescending
            }
        }

        return .orderedSame
    }
}
