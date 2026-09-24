/*
    main.swift
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
import OSLog
  
class ServiceDelegate: NSObject, NSXPCListenerDelegate {
    
    let patcherDaemon = PatcherDaemon()
    var activeConnections: NSMutableSet = []
    
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        
        var acceptConnection = false

        do {
            
            let signingAuthority = try MTCodeSigning().signingAuthority()
            let signingRequirement = MTCodeSigning().codeSigningRequirements(commonName: signingAuthority,
                                                                             bundleIdentifier: "corp.sap.Patcher*",
                                                                             versionString: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
            )

            // apply the signing requirement to the incoming connection
            newConnection.setCodeSigningRequirement(signingRequirement)

            newConnection.exportedInterface = NSXPCInterface(with: PatcherDaemonProtocol.self)
            newConnection.remoteObjectInterface = NSXPCInterface(with: MTInstallDelegate.self)
            
            patcherDaemon.listenerEndpoint = listener.endpoint
            newConnection.exportedObject = patcherDaemon
            
            newConnection.interruptionHandler = {
                
                DispatchQueue.main.async {
                    Logger().log("SAPCorp: \(newConnection, privacy: .public) interrupted")
                    self.activeConnections.remove(newConnection)
                }
            }
            
            newConnection.invalidationHandler = {
                
                DispatchQueue.main.async {
                    Logger().log("SAPCorp: \(newConnection, privacy: .public) invalidated")
                    self.activeConnections.remove(newConnection)
                }
            }
            
            newConnection.resume()
            
            DispatchQueue.main.async {
                Logger().log("SAPCorp: \(newConnection, privacy: .public) established")
                self.activeConnections.add(newConnection)
            }

            acceptConnection = true
            
        } catch {
            
            Logger().fault("SAPCorp: Failed to get signing authority: \(String(describing: error), privacy: .public)")
        }

        return acceptConnection
    }
}

func main()
{
    Logger().log("SAPCorp: Starting")
    
    let delegate = ServiceDelegate()
    
    let listener = NSXPCListener(machServiceName: "corp.sap.PatcherDaemon.xpc")
    listener.delegate = delegate
    listener.resume()
    
    // remove the available updates from our group prefs
    PatcherDaemon.setAvailableUpdates(nil)
    
    DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
        
        let updateStrategy = PatcherDaemon.updateStrategy()
        
        if updateStrategy == 0 || updateStrategy == 1 {
            
            // we don't start automatic updates if Patcher is running
            if delegate.activeConnections.count > 0 {
                
                Logger().log("SAPCorp: Deferring automatic update checks while the Patcher application is running")
                delegate.patcherDaemon.shouldTerminate = true
                
            } else {

                Logger().log("SAPCorp: Checking for updates…")
                
                Task {
                    
                    defer { delegate.patcherDaemon.shouldTerminate = true }
                    
                    do {
                        
                        let allApplications = try await MTApplicationRepository.shared.availableApplications()
                        
                        let deferralDays = PatcherDaemon.deferralDays()
                        let cutoffDate = Calendar.current.date(byAdding: .day, value: -deferralDays, to: Date()) ?? Date()
                        if deferralDays > 0 { Logger().log("SAPCorp: Only updates released before \(cutoffDate.description, privacy: .public), will be taken into account") }

                        // get the updates
                        let applicationsWithUpdates = allApplications.filter { application in
                            
                            let latestVersion = application.latestVersion
                            guard let installedVersion = application.installedVersion else { return false }
                            
                            guard MTVersion.compare(latestVersion, installedVersion) == .orderedDescending else { return false }
                            
                            guard deferralDays > 0 else { return true }
                            
                            let iso8601Formatter = ISO8601DateFormatter()
                            guard let date = iso8601Formatter.date(from: application.releaseDate) else {
                                
                                Logger().error("SAPCorp: Ignoring update for \(application.name, privacy: .public) because release date is invalid: \(application.releaseDate, privacy: .public)")
                                return false
                            }
                            
                            return date <= cutoffDate
                        }
                        
                        let updateCount = applicationsWithUpdates.count
                        
                        if updateCount > 0 {
                            Logger().log("SAPCorp: Found \(updateCount) update(s)")
                        } else {
                            Logger().log("SAPCorp: No updates found")
                        }
                        
                        if updateStrategy == 1 {
                            
                            PatcherDaemon.setAvailableUpdates(updateCount)
                            
                        } else {
                            
                            // ensure that Patcher updates are performed last
                            let updatesToInstall = applicationsWithUpdates.filter { !$0.isSelfUpdate } + applicationsWithUpdates.filter { $0.isSelfUpdate }
                            
                            for application in updatesToInstall {
                                
                                // check if the application is running
                                if application.isRunning {
                                    
                                    Logger().log("SAPCorp: Skipping update of \(application.name, privacy: .public) because it is currently running")
                                    
                                } else {
                                    
                                    let error = await withCheckedContinuation { continuation in
                                        
                                        delegate.patcherDaemon.installApplicationWithIdentifier(application.identifier) { error in
                                            continuation.resume(returning: error)
                                        }
                                    }
                                    
                                    if let error {
                                        Logger().log("SAPCorp: Failed to update \(application.name, privacy: .public): \(String(describing: error), privacy: .public)")
                                    }
                                }
                            }
                        }
                        
                        PatcherDaemon.setLastUpdateCheck(Date())
                        Logger().log("SAPCorp: Update check complete")
                        
                    } catch {
                        
                        Logger().error("SAPCorp: Update check failed: \(String(describing: error), privacy: .public)")
                    }
                }
            }
            
        } else {
            
            Logger().log("SAPCorp: Automatic updates are disabled")
            delegate.patcherDaemon.shouldTerminate = true
        }
    }
    
    while delegate.activeConnections.count > 0 || !delegate.patcherDaemon.shouldTerminate {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 60))
    }
    
    Logger().log("SAPCorp: Exiting")
    
    exit(EXIT_SUCCESS)
}

main()
