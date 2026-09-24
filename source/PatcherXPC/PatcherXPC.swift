/*
    PatcherXPC.swift
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

class PatcherXPC: PatcherXPCProtocol {
    
    func connect(daemonEndpointReply: @escaping (NSXPCListenerEndpoint) -> Void) {
        
        let daemonConnection = NSXPCConnection(machServiceName: "corp.sap.PatcherDaemon.xpc", options: .privileged)
        daemonConnection.remoteObjectInterface = NSXPCInterface(with: PatcherDaemonProtocol.self)
        daemonConnection.resume()
        
        guard let proxy = daemonConnection.remoteObjectProxyWithErrorHandler({ error in
            
            Logger().fault("SAPCorp: Failed to connect to daemon: \(String(describing: error), privacy: .public)")
            
        }) as? PatcherDaemonProtocol else {
            
            Logger().fault("SAPCorp: Invalid proxy response from daemon")
            return
        }
        
        proxy.connect(endpointReply: { endpoint in
            
            DispatchQueue.main.async { daemonEndpointReply(endpoint) }
            daemonConnection.invalidate()
        })
    }
}
