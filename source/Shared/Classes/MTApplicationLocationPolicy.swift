/*
    MTApplicationLocationPolicy.swift
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

enum MTApplicationLocationPolicy {
    
    private static let applicationsURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
    
    static func applicationLocation(forBundleIdentifier bundleIdentifier: String) -> URL? {
        
        applicationLocations(forBundleIdentifiers: [bundleIdentifier])[bundleIdentifier]
    }
    
    static func applicationLocations<S: Sequence>(forBundleIdentifiers bundleIdentifiers: S) -> [String: URL] where S.Element == String {
        
        let requestedBundleIdentifiers = Set(bundleIdentifiers)
        
        guard !requestedBundleIdentifiers.isEmpty else { return [:] }
        
        let applicationURLs: [URL]
        
        do {

            applicationURLs = try FileManager.default.contentsOfDirectory(
                at: applicationsURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            
        } catch {
            
            Logger().error("SAPCorp: Failed to read \(self.applicationsURL.path, privacy: .public): \(String(describing: error), privacy: .public)")
            return [:]
        }
        
        var locationsByBundleIdentifier: [String: URL] = [:]
        
        for applicationURL in applicationURLs.sorted(by: { $0.path.localizedStandardCompare($1.path) == .orderedAscending }) {
            
            guard applicationURL.pathExtension.lowercased() == "app" else {
                continue
            }

            guard let infoDictionary = NSDictionary(contentsOf: applicationURL.appendingPathComponent("Contents/Info.plist")),
                  let bundleIdentifier = infoDictionary["CFBundleIdentifier"] as? String,
                  requestedBundleIdentifiers.contains(bundleIdentifier) else {
                continue
            }
            
            if locationsByBundleIdentifier[bundleIdentifier] == nil {
                
                locationsByBundleIdentifier[bundleIdentifier] = applicationURL
                    .standardizedFileURL
                    .resolvingSymlinksInPath()
            }
        }
        
        return locationsByBundleIdentifier
    }
}
