/*
    MTAppDefinitions.swift
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
import CryptoKit
import OSLog

nonisolated struct MTApplicationDefinition: Sendable {

    let name: String
    let url: String
    let identifier: String
    let infoByLanguageCode: [String: String]?
    let image: Data?
    let latestVersion: String
    let releaseNotes: String
    let downloadURL: String
    let releaseDate: String
    let sha256Checksum: String
}

nonisolated private struct MTManifest: Decodable, Sendable {

    let definitions: [String: MTManifestDefinition]
    let releases: [String: MTManifestRelease]
}

nonisolated private struct MTManifestDefinition: Decodable, Sendable {

    let url: String
    let name: String
    let image: Data?
    let infoByLanguageCode: [String: String]?
    
    private enum CodingKeys: String, CodingKey {
        
        case url
        case name
        case image
        case info
    }
    
    init(from decoder: any Decoder) throws {
        
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        url = try container.decode(String.self, forKey: .url)
        name = try container.decode(String.self, forKey: .name)
        
        if let info = try container.decodeIfPresent([String: String].self, forKey: .info) {
            infoByLanguageCode = Dictionary(
                uniqueKeysWithValues: info.map {
                    ($0.key.lowercased(), $0.value)
                }
            )
        } else {
            infoByLanguageCode = nil
        }
        
        if let imageString = try container.decodeIfPresent(String.self, forKey: .image) {
            image = Self.data(fromPlistHexString: imageString)
        } else {
            image = nil
        }
    }
    
    private static func data(fromPlistHexString string: String) -> Data? {
        
        let hexCharacters = string
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "<", with: "")
            .replacingOccurrences(of: ">", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\t", with: "")
        
        guard hexCharacters.count.isMultiple(of: 2) else {
            return nil
        }
        
        var data = Data()
        data.reserveCapacity(hexCharacters.count / 2)
        
        var index = hexCharacters.startIndex
        
        while index < hexCharacters.endIndex {
            
            let nextIndex = hexCharacters.index(index, offsetBy: 2)
            let byteString = String(hexCharacters[index..<nextIndex])
            
            guard let byte = UInt8(byteString, radix: 16) else {
                return nil
            }
            
            data.append(byte)
            index = nextIndex
        }
        
        return data
    }
}

nonisolated private struct MTManifestRelease: Decodable, Sendable {

    let version: String
    let notes: String
    let url: String
    let date: String
    let checksum: String
    
    private enum CodingKeys: String, CodingKey {
        case version
        case notes
        case url
        case date
        case checksum
    }
}

actor MTAppDefinitions {

    static let shared = MTAppDefinitions()

    private let errorDomain = "corp.sap.Patcher"
    private let manifestInfoPlistKey = "ManifestURL"
    private let maximumManifestSize = 500 * 1024
    
    private init() {}
    
    func loadDefinitions() async throws -> [MTApplicationDefinition]
    {
        let data = try await loadManifestData()
        return try decodeDefinitions(from: data)
    }
    
    private func loadManifestData() async throws -> Data
    {
        guard let remoteURL = manifestURL else {
            
            throw makeError(
                code: 2000,
                description: "No valid manifest URL found in Info.plist."
            )
        }
        
        do {
            
            let data = try await downloadManifest(from: remoteURL)
            return data
            
        } catch {
            
            Logger().error("SAPCorp: Failed to download manifest: \(String(describing: error), privacy: .public)")
            throw error
        }
    }
    
    private var manifestURL: URL?
    {
        let configuredURLString = Bundle.main.object(forInfoDictionaryKey: manifestInfoPlistKey) as? String
        
        guard let configuredURLString else {
            return nil
        }
        
        let trimmedURLString = configuredURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedURLString.isEmpty else {
            return nil
        }
        
        return URL(string: trimmedURLString)
    }
    
    private func downloadManifest(from url: URL) async throws -> Data
    {
        guard url.scheme?.lowercased() == "https" else {
            
            throw makeError(
                code: 2001,
                description: "Manifest URL must use HTTPS: \(url.absoluteString)"
            )
        }
        
        let data = try await downloadData(
            from: url,
            acceptHeader: "application/json",
            failureDescription: "Manifest download"
        )
        
        guard data.count <= maximumManifestSize else {
            
            throw makeError(
                code: 2002,
                description: "Manifest is too large: \(data.count) bytes"
            )
        }
        
        try await validateManifestSignature(data, manifestURL: url)
        
        return data
    }
    
    private func validateManifestSignature(_ manifestData: Data, manifestURL: URL) async throws
    {
        let signatureURL = manifestURL.deletingPathExtension().appendingPathExtension("sig")
        
        let downloadedSignatureData = try await downloadData(
            from: signatureURL,
            acceptHeader: "text/plain",
            failureDescription: "Manifest signature download"
        )
        
        let publicKeyData = try loadManifestPublicKeyData()
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
        let signatureData = try normalizedManifestSignatureData(from: downloadedSignatureData)

        guard publicKey.isValidSignature(signatureData, for: manifestData) else {
            
            throw makeError(
                code: 2003,
                description: "Manifest signature validation failed."
            )
        }
    }
    
    private func loadManifestPublicKeyData() throws -> Data
    {
        guard let publicKeyURL = Bundle.main.url(forResource: "manifest", withExtension: "pem") else {
            
            throw makeError(
                code: 2005,
                description: "Manifest public key file manifest.pem was not found in the application bundle"
            )
        }
        
        let publicKeyFileData = try Data(contentsOf: publicKeyURL)
        return try normalizedCurve25519SigningPublicKeyData(from: publicKeyFileData)
    }
    
    private func normalizedCurve25519SigningPublicKeyData(from publicKeyFileData: Data) throws -> Data
    {
        if publicKeyFileData.count == 32 { return publicKeyFileData }
        
        if let publicKeyString = String(data: publicKeyFileData, encoding: .utf8) {
            
            if let pemData = decodedPEMData(from: publicKeyString) {
                return try normalizedCurve25519SigningPublicKeyDataFromDEROrRawData(pemData)
            }
            
            let base64String = publicKeyString.components(separatedBy: .whitespacesAndNewlines).joined()
            
            if let base64Data = Data(base64Encoded: base64String) {
                return try normalizedCurve25519SigningPublicKeyDataFromDEROrRawData(base64Data)
            }
        }
        
        return try normalizedCurve25519SigningPublicKeyDataFromDEROrRawData(publicKeyFileData)
    }
    
    private func normalizedCurve25519SigningPublicKeyDataFromDEROrRawData(_ data: Data) throws -> Data
    {
        if data.count == 32 { return data }
        
        let ed25519SubjectPublicKeyInfoPrefix: [UInt8] = [
            0x30, 0x2a,
            0x30, 0x05,
            0x06, 0x03, 0x2b, 0x65, 0x70,
            0x03, 0x21, 0x00
        ]
        
        if data.count == ed25519SubjectPublicKeyInfoPrefix.count + 32,
           Array(data.prefix(ed25519SubjectPublicKeyInfoPrefix.count)) == ed25519SubjectPublicKeyInfoPrefix {
            
            return Data(data.suffix(32))
        }
        
        throw makeError(
            code: 2006,
            description: "Manifest public key file manifest.pem does not contain a valid public key"
        )
    }
    
    private func decodedPEMData(from pemString: String) -> Data?
    {
        let base64String = pemString
            .components(separatedBy: .newlines)
            .map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter {
                !$0.isEmpty && !$0.hasPrefix("-----")
            }
            .joined()
        
        guard !base64String.isEmpty else {
            return nil
        }
        
        return Data(base64Encoded: base64String)
    }
    
    private func normalizedManifestSignatureData(from downloadedSignatureData: Data) throws -> Data
    {
        if downloadedSignatureData.count == 64 { return downloadedSignatureData }
        
        if let signatureString = String(data: downloadedSignatureData, encoding: .utf8) {
            
            let base64String = signatureString.components(separatedBy: .whitespacesAndNewlines).joined()
            
            if let signatureData = Data(base64Encoded: base64String),
               signatureData.count == 64 {
                
                return signatureData
            }
        }
        
        throw makeError(
            code: 2007,
            description: "Manifest signature has an invalid format"
        )
    }
    
    private func downloadData(from url: URL, acceptHeader: String, failureDescription: String) async throws -> Data
    {
        var request = URLRequest(url: url)
        request.setValue(acceptHeader, forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            
            throw makeError(
                code: 2004,
                description: "\(failureDescription) failed because no response was received"
            )
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            
            throw makeError(
                code: httpResponse.statusCode,
                description: "\(failureDescription) failed with error: \(httpResponse.statusCode)"
            )
        }
        
        return data
    }
    
    private func decodeDefinitions(from data: Data) throws -> [MTApplicationDefinition]
    {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let manifest = try decoder.decode(MTManifest.self, from: data)
        
        return manifest.definitions
            .compactMap { (identifier: String, definition: MTManifestDefinition) in
                guard let release = manifest.releases[identifier] else {
                    Logger().log("SAPCorp: Skipping \(definition.name, privacy: .public) because no release info exists in manifest")
                    return nil
                }
                return MTApplicationDefinition(
                    name: definition.name,
                    url: definition.url,
                    identifier: identifier,
                    infoByLanguageCode: definition.infoByLanguageCode,
                    image: definition.image,
                    latestVersion: MTVersion.normalized(from: release.version) ?? "0.0.0",
                    releaseNotes: release.notes,
                    downloadURL: release.url,
                    releaseDate: release.date,
                    sha256Checksum: release.checksum
                )
            }
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }
    
    private func makeError(code: Int, description: String) -> NSError
    {
        NSError(
            domain: errorDomain,
            code: code,
            userInfo: [
                NSLocalizedDescriptionKey: description
            ]
        )
    }
    
    private static var userAgent: String
    {
        let bundle = Bundle.main
        
        let appName =
            (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "Patcher"
        
        let appVersion =
            (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "0"
        
        return "\(appName)/\(appVersion)"
    }
}
