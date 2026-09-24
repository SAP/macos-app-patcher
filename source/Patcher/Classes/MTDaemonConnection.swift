/*
    MTDaemonConnection.swift
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

@MainActor
final class MTDaemonConnection {

    private var xpcServiceConnection: NSXPCConnection?
    private var daemonConnection: NSXPCConnection?
    private var listenerEndpoint: NSXPCListenerEndpoint?
    private var daemonProxy: PatcherDaemonProtocol?

    func connect(exportedObject: AnyObject? = nil) async throws -> PatcherDaemonProtocol {

        if let proxy = daemonProxy { return proxy }

        let endpoint = try await getListenerEndpoint()
        let connection = NSXPCConnection(listenerEndpoint: endpoint)
        
        let interface = NSXPCInterface(with: PatcherDaemonProtocol.self)
        let allowedClasses: NSSet = [MTApplication.self, NSArray.self]
        
        interface.setClasses(allowedClasses as! Set<AnyHashable>,
                             for: #selector(PatcherDaemonProtocol.availableApplications(reply:)),
                             argumentIndex: 0,
                             ofReply: true
        )
        
        connection.remoteObjectInterface = interface
        connection.exportedInterface = NSXPCInterface(with: MTInstallDelegate.self)

        if let exportedObject { connection.exportedObject = exportedObject }

        let proxy = connection.remoteObjectProxyWithErrorHandler { error in

                Logger().fault("SAPCorp: Daemon XPC error: \(String(describing: error), privacy: .public)")
            }
            as! PatcherDaemonProtocol

        connection.resume()

        daemonConnection = connection
        daemonProxy = proxy

        return proxy
    }

    private func getListenerEndpoint() async throws -> NSXPCListenerEndpoint
    {
        if let endpoint = listenerEndpoint { return endpoint }

        let proxy = try await connectToService()

        return try await withCheckedThrowingContinuation { continuation in

            proxy.connect(daemonEndpointReply: { endpoint in
                
                self.listenerEndpoint = endpoint
                continuation.resume(returning: endpoint)
            })
        }
    }

    private func connectToService() async throws -> PatcherXPCProtocol
    {
        if let connection = xpcServiceConnection {

            return connection.remoteObjectProxyWithErrorHandler { _ in } as! PatcherXPCProtocol
        }

        let connection = NSXPCConnection(serviceName: "corp.sap.PatcherXPC")
        connection.remoteObjectInterface = NSXPCInterface(with: PatcherXPCProtocol.self)

        connection.invalidationHandler = {
            
            DispatchQueue.main.async {
                
                self.daemonProxy = nil
                self.listenerEndpoint = nil
                self.daemonConnection = nil
                self.xpcServiceConnection = nil
                
                Logger().log("SAPCorp: XPC service connection invalidated")
            }
        }

        connection.interruptionHandler = {
            
            DispatchQueue.main.async {
                
                self.daemonProxy = nil
                self.listenerEndpoint = nil
                self.daemonConnection = nil
                self.xpcServiceConnection = nil
                
                Logger().log("SAPCorp: XPC service connection interrupted")
            }
        }

        connection.resume()

        xpcServiceConnection = connection

        return connection.remoteObjectProxyWithErrorHandler { error in

                Logger().fault("SAPCorp: XPC service error: \(String(describing: error), privacy: .public)")
        } as! PatcherXPCProtocol
    }

    func invalidate() {

        daemonConnection?.invalidate()
        xpcServiceConnection?.invalidate()

        daemonProxy = nil
        listenerEndpoint = nil
        daemonConnection = nil
        xpcServiceConnection = nil
    }
}

