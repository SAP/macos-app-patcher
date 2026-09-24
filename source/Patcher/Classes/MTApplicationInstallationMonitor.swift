/*
    MTApplicationInstallationMonitor.swift
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

import AppKit
import CoreServices
import OSLog

private let MonitorEventCallback: FSEventStreamCallback = { _, clientCallBackInfo, _, _, _, _ in
    
    guard let clientCallBackInfo else { return }
    
    let monitor = Unmanaged<MTApplicationInstallationMonitor>
        .fromOpaque(clientCallBackInfo)
        .takeUnretainedValue()
    
    Task { @MainActor in
        monitor.applicationsDirectoryDidChange()
    }
}

@MainActor
final class MTApplicationInstallationMonitor {
    
    private enum ApplicationLocation: Equatable {
        
        case installed(path: String)
        case notInstalled
    }
    
    private let applicationsDirectoryURL: URL
    private let eventStreamLatency: CFTimeInterval
    private let eventStreamQueue = DispatchQueue(label: "corp.sap.Patcher.application-installation-monitor")
    
    private var eventStream: FSEventStreamRef?
    private var lastSnapshot: [String: ApplicationLocation] = [:]
    private var identifiersCurrentlyRefreshing: Set<String> = []
    
    init(
        applicationsDirectoryURL: URL = URL(fileURLWithPath: "/Applications", isDirectory: true),
        eventStreamLatency: TimeInterval = 5
    ) {
        self.applicationsDirectoryURL = applicationsDirectoryURL
        self.eventStreamLatency = eventStreamLatency
    }
    
    @available(*, deprecated, renamed: "init(applicationsDirectoryURL:eventStreamLatency:)")
    convenience init(pollingInterval: TimeInterval) {
        
        self.init(eventStreamLatency: pollingInterval)
    }
    
    func start() {
        
        guard eventStream == nil else { return }
        
        lastSnapshot = makeSnapshot()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationsDidChange),
            name: MTCachedApplications.applicationsDidChangeNotification,
            object: MTCachedApplications.shared
        )
        
        startMonitoringApplicationsDirectory()
    }
    
    func stop() {
        
        stopMonitoringApplicationsDirectory()
        
        NotificationCenter.default.removeObserver(self)
        
        lastSnapshot = [:]
        identifiersCurrentlyRefreshing = []
    }
    
    @objc private func applicationsDidChange() {
        
        lastSnapshot = makeSnapshot()
    }
    
    fileprivate func applicationsDirectoryDidChange() {
        
        guard eventStream != nil else { return }
        
        checkInstalledApplicationLocations()
    }
    
    private func startMonitoringApplicationsDirectory() {
        
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        
        let pathsToWatch = [applicationsDirectoryURL.path] as CFArray
        
        let createFlags =
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagWatchRoot) |
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagIgnoreSelf)
        
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            MonitorEventCallback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            eventStreamLatency,
            createFlags
        ) else {
            
            Logger().fault("SAPCorp: Failed to create file system event stream for \(self.applicationsDirectoryURL.path, privacy: .public)")
            return
        }
        
        FSEventStreamSetDispatchQueue(stream, eventStreamQueue)
        
        guard FSEventStreamStart(stream) else {
            
            FSEventStreamSetDispatchQueue(stream, nil)
            FSEventStreamInvalidate(stream)
            
            Logger().fault("SAPCorp: Failed to start file system event stream for \(self.applicationsDirectoryURL.path, privacy: .public)")
            return
        }
        
        eventStream = stream
    }
    
    private func stopMonitoringApplicationsDirectory() {
        
        guard let eventStream else { return }
        
        FSEventStreamStop(eventStream)
        FSEventStreamSetDispatchQueue(eventStream, nil)
        FSEventStreamInvalidate(eventStream)
        
        self.eventStream = nil
    }
    
    private func checkInstalledApplicationLocations() {
        
        let currentSnapshot = makeSnapshot()
        
        if lastSnapshot.isEmpty {
            
            lastSnapshot = currentSnapshot
            return
        }
        
        let changedIdentifiers = changedApplicationIdentifiers(
            oldSnapshot: lastSnapshot,
            currentSnapshot: currentSnapshot
        )
        
        guard !changedIdentifiers.isEmpty else { return }
        
        lastSnapshot = currentSnapshot
        
        for identifier in changedIdentifiers {
            
            refreshInstalledStateIfNeeded(forIdentifier: identifier)
        }
    }
    
    private func changedApplicationIdentifiers(oldSnapshot: [String: ApplicationLocation], currentSnapshot: [String: ApplicationLocation]) -> [String]
    {
        let allIdentifiers = Set(oldSnapshot.keys).union(currentSnapshot.keys)
        
        return allIdentifiers
            .filter { identifier in
                
                guard !identifiersCurrentlyRefreshing.contains(identifier) else { return false }
                
                return oldSnapshot[identifier] != currentSnapshot[identifier]
            }
            .sorted()
    }
    
    private func refreshInstalledStateIfNeeded(forIdentifier identifier: String) {
        
        guard !identifiersCurrentlyRefreshing.contains(identifier) else { return }
        
        identifiersCurrentlyRefreshing.insert(identifier)
        
        Logger().log("SAPCorp: Detected change for \(identifier, privacy: .public)")
        
        MTDaemonSession.shared.refreshInstalledState(forIdentifier: identifier) { [weak self] error in
            
            Task { @MainActor in
                
                guard let self else { return }
                
                self.identifiersCurrentlyRefreshing.remove(identifier)
                self.lastSnapshot = self.makeSnapshot()
                
                if let error {
                    
                    Logger().error("SAPCorp: Failed to refresh installed state for \(identifier, privacy: .public): \(String(describing: error), privacy: .public)")
                }
            }
        }
    }
    
    private func makeSnapshot() -> [String: ApplicationLocation] {
                
        let applications = MTCachedApplications.shared.applications
        let identifiers = applications.map(\.identifier)
        let locationsByIdentifier = MTApplicationLocationPolicy.applicationLocations(forBundleIdentifiers: identifiers)
        
        var snapshot: [String: ApplicationLocation] = [:]
        
        for application in applications {
            
            if let applicationURL = locationsByIdentifier[application.identifier] {
                
                snapshot[application.identifier] = .installed(
                    path: applicationURL.standardizedFileURL.resolvingSymlinksInPath().path
                )
                
            } else {
                
                snapshot[application.identifier] = .notInstalled
            }
        }
        
        return snapshot
    }
}
