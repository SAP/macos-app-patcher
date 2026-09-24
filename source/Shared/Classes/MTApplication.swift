/*
    MTApplication.swift
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

import Cocoa
import OSLog

@objc(MTApplication)
final class MTApplication: NSObject, NSSecureCoding {

    static var supportsSecureCoding: Bool { true }
    
    @objc let name: String
    @objc let url: String
    @objc let identifier: String
    
    @objc dynamic var isRunning: Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first != nil
    }
    
    @objc dynamic var info: String? {
        Self.localizedText(from: infoByLanguageCode)
    }
    
    @objc dynamic var isSelfUpdate: Bool {
        identifier == kMTPreferenceDomain
    }
    
    private let infoByLanguageCode: [String: String]?
    
    @objc var image: NSImage?
    @objc dynamic var installedVersion: String?
    @objc dynamic var installProgress: Float
    @objc var latestVersion: String
    @objc var releaseNotes: String
    @objc var releaseDate: String
    @objc var downloadURL: String
    @objc var sha256Checksum: String
    @objc dynamic var isInstalling: Bool
    
    init(
        name: String,
        url: String,
        identifier: String,
        infoByLanguageCode: [String: String]?,
        image: NSImage?,
        installedVersion: String? = nil,
        installProgress: Float = 0,
        latestVersion: String,
        releaseNotes: String,
        releaseDate: String,
        downloadURL: String,
        sha256Checksum: String,
        isInstalling: Bool = false
    ) {
        self.name = name
        self.url = url
        self.identifier = identifier
        self.infoByLanguageCode = infoByLanguageCode
        self.image = image
        self.installedVersion = installedVersion
        self.installProgress = installProgress
        self.latestVersion = latestVersion
        self.releaseNotes = releaseNotes
        self.releaseDate = releaseDate
        self.downloadURL = downloadURL
        self.sha256Checksum = sha256Checksum
        self.isInstalling = isInstalling
    }
    
    private static func localizedText(from valuesByLanguageCode: [String: String]?) -> String? {
        
        guard let valuesByLanguageCode else {
            return nil
        }
        
        let languageCode = Locale.preferredLanguages
            .first
            .flatMap { Locale(identifier: $0).language.languageCode?.identifier }?
            .lowercased()
        ?? Locale.current.language.languageCode?.identifier.lowercased()
        
        if let languageCode, let localizedText = valuesByLanguageCode[languageCode] {
            return localizedText
        }
        
        return valuesByLanguageCode["default"]
    }
    
    // MARK: - NSSecureCoding
    
    func encode(with coder: NSCoder) {
        coder.encode(name as NSString, forKey: "name")
        coder.encode(url as NSString, forKey: "url")
        coder.encode(identifier as NSString, forKey: "identifier")
        coder.encode(isInstalling, forKey: "isInstalling")
        coder.encode(installProgress, forKey: "installProgress")
        coder.encode(latestVersion as NSString, forKey: "latestVersion")
        coder.encode(releaseNotes as NSString, forKey: "releaseNotes")
        coder.encode(releaseDate as NSString, forKey: "releaseDate")
        coder.encode(downloadURL as NSString, forKey: "downloadURL")
        coder.encode(sha256Checksum as NSString, forKey: "sha256Checksum")
        if let image { coder.encode(image as NSImage, forKey: "image") }
        if let infoByLanguageCode { coder.encode(infoByLanguageCode as NSDictionary, forKey: "infoByLanguageCode") }
        if let installedVersion { coder.encode(installedVersion as NSString, forKey: "installedVersion") }
    }
    
    required init?(coder: NSCoder)
    {
        guard
            let name = coder.decodeObject(of: NSString.self, forKey: "name") as String?,
            let url = coder.decodeObject(of: NSString.self, forKey: "url") as String?,
            let identifier = coder.decodeObject(of: NSString.self, forKey: "identifier") as String?,
            let latestVersion = coder.decodeObject(of: NSString.self, forKey: "latestVersion") as String?,
            let releaseNotes = coder.decodeObject(of: NSString.self, forKey: "releaseNotes") as String?,
            let releaseDate = coder.decodeObject(of: NSString.self, forKey: "releaseDate") as String?,
            let downloadURL = coder.decodeObject(of: NSString.self, forKey: "downloadURL") as String?,
            let sha256Checksum = coder.decodeObject(of: NSString.self, forKey: "sha256Checksum") as String?
        else {
            return nil
        }

        let infoByLanguageCode = coder.decodeObject(of: [NSDictionary.self, NSString.self], forKey: "infoByLanguageCode") as? [String: String]
        let image = coder.decodeObject(of: NSImage.self, forKey: "image") as NSImage?
        let installedVersion = coder.decodeObject(of: NSString.self, forKey: "installedVersion") as String?
        let installProgress = coder.decodeFloat(forKey: "installProgress")
        let isInstalling = coder.decodeBool(forKey: "isInstalling")
        
        self.name = name
        self.url = url
        self.identifier = identifier
        self.infoByLanguageCode = infoByLanguageCode
        self.image = image
        self.installedVersion = installedVersion
        self.installProgress = installProgress
        self.latestVersion = latestVersion
        self.releaseNotes = releaseNotes
        self.releaseDate = releaseDate
        self.downloadURL = downloadURL
        self.sha256Checksum = sha256Checksum
        self.isInstalling = isInstalling
    }
}
