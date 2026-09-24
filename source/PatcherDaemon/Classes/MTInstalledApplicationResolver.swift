/*
    MTInstalledApplicationResolver.swift
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
import OSLog

enum MTInstalledApplicationResolver {

    static func installedVersion(forBundleIdentifier bundleIdentifier: String) -> String?
    {
        guard let appURL = MTApplicationLocationPolicy.applicationLocation(forBundleIdentifier: bundleIdentifier) else {
            return nil
        }
        
        return installedVersion(forApplicationAt: appURL)
    }
    
    static func installedVersions<S: Sequence>(forBundleIdentifiers bundleIdentifiers: S) -> [String: String] where S.Element == String {
        
        let locationsByBundleIdentifier = MTApplicationLocationPolicy.applicationLocations(
            forBundleIdentifiers: bundleIdentifiers
        )
        
        var versionsByBundleIdentifier: [String: String] = [:]
        
        for (bundleIdentifier, applicationURL) in locationsByBundleIdentifier {
            
            if let installedVersion = installedVersion(forApplicationAt: applicationURL) {
                versionsByBundleIdentifier[bundleIdentifier] = installedVersion
            }
        }
        
        return versionsByBundleIdentifier
    }
    
    static func installedVersion(forApplicationAt appURL: URL) -> String?
    {
        // we don't use NSBundle here because it caches the Info.plist and therefore it returns
        // the wrong (old) version if we call it right after updating an application.
        guard let infoDictionary = NSDictionary(contentsOf: appURL.appendingPathComponent("Contents/Info.plist")),
              let version = infoDictionary["CFBundleShortVersionString"] as? String else {
            Logger().error("SAPCorp: Failed to get CFBundleShortVersionString for installed application at \(appURL.path, privacy: .public)")
            return nil
        }
        
        return MTVersion.normalized(from: version)
    }
}
