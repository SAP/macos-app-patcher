/*
    MTApplicationRepository.swift
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
import Cocoa
import OSLog

actor MTApplicationRepository {

    static let shared = MTApplicationRepository()
    
    private var applications: [MTApplication] = []
    private var loadingTask: Task<[MTApplication], Error>?

    private init() {}
    
    func startLoading()
    {
        guard loadingTask == nil else {
            return
        }

        loadingTask = Task {
            try await loadApplications()
        }
    }

    func availableApplications() async throws -> [MTApplication] {
        
        startLoading()

        guard let loadingTask else {
            return applications
        }

        do {
            
            let loadedApplications = try await loadingTask.value
            applications = loadedApplications
            
            return loadedApplications
            
        } catch {
            
            self.loadingTask = nil
            throw error
        }
    }

    func reloadApplications() async throws -> [MTApplication] {
        
        loadingTask = nil
        applications = []
        
        startLoading()

        guard let loadingTask else {
            return applications
        }

        do {
            
            let loadedApplications = try await loadingTask.value
            applications = loadedApplications
            
            return loadedApplications
            
        } catch {
            
            self.loadingTask = nil
            throw error
        }
    }
    
    func refreshInstalledState(forIdentifier identifier: String) async -> MTApplication?
    {
        guard let application = applications.first(where: { $0.identifier == identifier }) else {
            return nil
        }

        let installedVersion = await MTInstalledApplicationResolver.installedVersion(forBundleIdentifier: identifier)

        await MainActor.run {
            application.installedVersion = installedVersion
        }
        
        return application
    }

    private func loadApplications() async throws -> [MTApplication]
    {
        let definitions = try await MTAppDefinitions.shared.loadDefinitions()
        let installedVersionsByBundleIdentifier = await MTInstalledApplicationResolver.installedVersions(
            forBundleIdentifiers: definitions.map(\.identifier)
        )

        return await withTaskGroup(of: (Int, MTApplication)?.self) { group in

            for (index, definition) in definitions.enumerated() {
                
                group.addTask {
                    
                    let appIcon = (definition.image != nil) ? NSImage(data: definition.image!) : NSImage(systemSymbolName: "questionmark.app.dashed", accessibilityDescription: "")
                    
                    let latestVersion = definition.latestVersion.trimmingCharacters(in: .whitespacesAndNewlines)
                    let downloadURL = definition.downloadURL.trimmingCharacters(in: .whitespacesAndNewlines)

                    guard !latestVersion.isEmpty, !downloadURL.isEmpty else {
                        Logger().log("SAPCorp: Skipping \(definition.name, privacy: .public) because no valid release info is available in manifest")
                        return nil
                    }
                    
                    guard
                        let packageURL = URL(string: downloadURL),
                        packageURL.scheme?.lowercased() == "https",
                        packageURL.pathExtension.lowercased() == "pkg"
                    else {
                        
                        Logger().log("SAPCorp: Skipping \(definition.name, privacy: .public) because download URL is not a valid https pkg url")
                        return nil
                    }
                    
                    let installedVersion = installedVersionsByBundleIdentifier[definition.identifier]
                    
                    let application = await MTApplication(
                        
                        name: definition.name,
                        url: definition.url,
                        identifier: definition.identifier,
                        infoByLanguageCode: definition.infoByLanguageCode,
                        image: appIcon,
                        installedVersion: installedVersion,
                        latestVersion: latestVersion,
                        releaseNotes: definition.releaseNotes,
                        releaseDate: definition.releaseDate,
                        downloadURL: downloadURL,
                        sha256Checksum: definition.sha256Checksum
                    )

                    return (index, application)
                }
            }

            var indexedApplications: [(Int, MTApplication)] = []

            for await indexedApplication in group {
                
                if let indexedApplication {
                    indexedApplications.append(indexedApplication)
                }
            }

            return indexedApplications
                .sorted { $0.0 < $1.0 }
                .map { $0.1 }
        }
    }
}
