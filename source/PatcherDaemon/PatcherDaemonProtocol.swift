/*
    PatcherDaemonProtocol.swift
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

@objc protocol PatcherDaemonProtocol {
    
    func connect(endpointReply: @escaping (_ endpoint: NSXPCListenerEndpoint) -> Void)
    func registerInstallDelegate(reply: @escaping (_ success: Bool) -> Void)
    func availableApplications(reply: @escaping (_ applications: [MTApplication], _ error: NSError?) -> Void)
    func refreshInstalledStateForApplicationWithIdentifier(_ identifier: String, reply: @escaping (_ application: MTApplication?, _ error: NSError?) -> Void)
    func installApplicationWithIdentifier(_ identifier: String, reply: @escaping (_ error: NSError?) -> Void)
    
    func setUpdateStrategy(_ updateStrategy: Int, reply: @escaping (_ success: Bool) -> Void)
    func setDeferralDays(_ deferral: Int, reply: @escaping (_ success: Bool) -> Void)
}

