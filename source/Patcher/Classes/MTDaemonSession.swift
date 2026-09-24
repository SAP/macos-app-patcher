/*
    MTDaemonSession.swift
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

final class MTDaemonSession: NSObject, MTInstallDelegate, @unchecked Sendable {
    
    static let shared = MTDaemonSession()
    
    private var connection: MTDaemonConnection?
    private var daemon: PatcherDaemonProtocol?
    private var startTask: Task<Void, Never>?
    
    private override init() {}
    
    @MainActor
    func start() async {
        
        if daemon != nil {
            return
        }
        
        if let startTask {
            await startTask.value
            return
        }
        
        let task = Task { @MainActor in
            
            do {
                
                let connection = MTDaemonConnection()
                let daemon = try await connection.connect(exportedObject: self)
                
                self.connection = connection
                self.daemon = daemon
                
                let didRegister = await registerInstallDelegate(on: daemon)
                
                if !didRegister {
                    Logger().error("SAPCorp: Failed to register install delegate")
                }
                                
            } catch {
                
                Logger().error("SAPCorp: Failed to start daemon session: \(String(describing: error), privacy: .public)")
            }
        }
        
        startTask = task
        await task.value
        startTask = nil
    }
    
    @MainActor
    func refreshApplications(reply: ((_ error: Error?) -> Void)? = nil) {
        
        guard let daemon else {
            
            Task { @MainActor in
                
                await start()
                
                guard self.daemon != nil else {
                    
                    reply?(
                        NSError(
                            domain: "corp.sap.Patcher",
                            code: 1,
                            userInfo: [
                                NSLocalizedDescriptionKey: "Daemon session is not connected"
                            ]
                        )
                    )
                    
                    return
                }
                
                refreshApplications(reply: reply)
            }
            
            return
        }
        
        daemon.availableApplications { applications, error in
            
            Task { @MainActor in
                
                if let error {
                    
                    reply?(error)
                    return
                }
                
                MTCachedApplications.shared.applications = applications
                reply?(nil)
            }
        }
    }
    
    @MainActor
    func refreshInstalledState(forIdentifier identifier: String, reply: ((_ error: Error?) -> Void)? = nil) {
        
        guard let daemon else {
            
            Task { @MainActor in
                
                await start()
                
                guard self.daemon != nil else {
                    
                    reply?(
                        NSError(
                            domain: "corp.sap.Patcher",
                            code: 1,
                            userInfo: [
                                NSLocalizedDescriptionKey: "Daemon session is not connected"
                            ]
                        )
                    )
                    
                    return
                }
                
                refreshInstalledState(forIdentifier: identifier, reply: reply)
            }
            
            return
        }
        
        daemon.refreshInstalledStateForApplicationWithIdentifier(identifier) { application, error in
            
            Task { @MainActor in
                
                if let error {
                    
                    reply?(error)
                    return
                }
                
                if let application {
                    self.updateCachedInstalledState(from: application)
                }
                
                reply?(nil)
            }
        }
    }
        
    @MainActor
    func installApplication(withIdentifier identifier: String, reply: @escaping (_ error: Error?) -> Void)
    {
        Task { @MainActor in
            
            await start()
            
            guard let daemon else {
                
                reply(
                    NSError(
                        domain: "corp.sap.Patcher",
                        code: 1,
                        userInfo: [
                            NSLocalizedDescriptionKey: "Daemon session is not connected"
                        ]
                    )
                )
                
                return
            }
            
            daemon.installApplicationWithIdentifier(identifier) { error in
                
                Task { @MainActor in
                    
                    if error != nil {
                                                
                        self.updateCachedApplication(
                            withIdentifier: identifier,
                            isInstalling: false,
                            installProgress: 0
                        )
                    }
                                        
                    reply(error)
                }
            }
        }
    }
    
    @MainActor
    func setUpdateStrategy(_ updateStrategy: Int, reply: @escaping (_ success: Bool, _ error: Error?) -> Void) {
        
        Task { @MainActor in
            
            await start()
            
            guard let daemon else {
                
                reply(
                    false,
                    NSError(
                        domain: "corp.sap.Patcher",
                        code: 1,
                        userInfo: [
                            NSLocalizedDescriptionKey: "Daemon session is not connected"
                        ]
                    )
                )
                
                return
            }
            
            daemon.setUpdateStrategy(updateStrategy) { success in
                
                Task { @MainActor in
                    
                    reply(success, nil)
                }
            }
        }
    }
    
    @MainActor
    func setDeferralDays(_ deferral: Int, reply: @escaping (_ success: Bool, _ error: Error?) -> Void) {
        
        Task { @MainActor in
            
            await start()
            
            guard let daemon else {
                
                reply(
                    false,
                    NSError(
                        domain: "corp.sap.Patcher",
                        code: 1,
                        userInfo: [
                            NSLocalizedDescriptionKey: "Daemon session is not connected"
                        ]
                    )
                )
                
                return
            }
            
            daemon.setDeferralDays(deferral, reply: { success in
                
                Task { @MainActor in
                    
                    reply(success, nil)
                }
            })
        }
    }

    @MainActor
    func invalidate() {
        
        connection?.invalidate()
        connection = nil
        daemon = nil
        startTask = nil
    }
    
    @MainActor
    private func registerInstallDelegate(on daemon: PatcherDaemonProtocol) async -> Bool {
        
        await withCheckedContinuation { continuation in
            
            daemon.registerInstallDelegate { success in
                continuation.resume(returning: success)
            }
        }
    }
    
    @MainActor
    private func updateCachedApplication(
        withIdentifier identifier: String,
        isInstalling: Bool,
        installProgress: Float
    ) {
        guard let application = MTCachedApplications.shared.applications.first(where: { $0.identifier == identifier }) else {
            return
        }
        
        application.isInstalling = isInstalling
        application.installProgress = min(max(installProgress, 0), 1)
        
        NotificationCenter.default.post(
            name: MTCachedApplications.applicationsDidChangeNotification,
            object: MTCachedApplications.shared
        )
    }
    
    @MainActor
    private func updateCachedInstalledState(from refreshedApplication: MTApplication) {
        
        guard let cachedApplication = MTCachedApplications.shared.applications.first(where: { $0.identifier == refreshedApplication.identifier }) else {
            return
        }
        
        cachedApplication.installedVersion = refreshedApplication.installedVersion
        
        NotificationCenter.default.post(
            name: MTCachedApplications.applicationsDidChangeNotification,
            object: MTCachedApplications.shared
        )
    }
    
    // MARK: - MTInstallDelegate
    
    func installationIsQueued(for application: MTApplication) {
        
        Task { @MainActor in
            
            self.updateCachedApplication(
                withIdentifier: application.identifier,
                isInstalling: true,
                installProgress: 0
            )
        }
    }
    
    func installationDidStart(for application: MTApplication) {
                
        Task { @MainActor in
            
            self.updateCachedApplication(
                withIdentifier: application.identifier,
                isInstalling: true,
                installProgress: 0
            )
        }
    }
    
    func installationDidFinish(for application: MTApplication) {
        
        Task { @MainActor in
            
            self.updateCachedApplication(
                withIdentifier: application.identifier,
                isInstalling: true,
                installProgress: 1
            )
            
            self.refreshApplications()
        }
    }
    
    func installationDidFail(for application: MTApplication, withError error: NSError) {
                        
        Task { @MainActor in
                        
            self.updateCachedApplication(
                withIdentifier: application.identifier,
                isInstalling: false,
                installProgress: 0
            )
            
            self.refreshApplications()
        }
    }
    
    func installationProgress(for application: MTApplication, didUpdate progress: Float) {
                
        Task { @MainActor in
            
            self.updateCachedApplication(
                withIdentifier: application.identifier,
                isInstalling: true,
                installProgress: progress
            )
        }
    }
}
