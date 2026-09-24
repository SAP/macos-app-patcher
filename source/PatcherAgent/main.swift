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
import UserNotifications
import OSLog

@MainActor
final class PatcherAgentAppDelegate: NSObject, NSApplicationDelegate {
    
    func applicationDidFinishLaunching(_ notification: Notification) {
                            
        Task { @MainActor in
            
            defer { NSApp.terminate(nil) }
            
            // if we have been called because the user clicked one of our notifications,
            // we just open the the Patcher application
            if notification.userInfo?[NSApplication.launchUserNotificationUserInfoKey] != nil {
                
                await openPatcherApplicationFromNotification()
                
            } else {
                
                await runAgent()
            }
        }
    }
}

private func runAgent() async
{
    if let userDefaults = UserDefaults(suiteName: kMTPreferenceDomain) {
        
        let availableUpdates = userDefaults.integer(forKey: kMTDefaultsUpdateCheckAvailableItemsKey)

        if availableUpdates > 0 {
            
            // get the notification interval
            var notificationInterval = userDefaults.integer(forKey: kMTDefaultsUpdateNotificationIntervalKey)
            if !(kMTNotificationIntervalMin...kMTNotificationIntervalMax).contains(notificationInterval) { notificationInterval = kMTNotificationIntervalDefault }
            
            // check when we sent the last notification
            let lastNotificationSentDate = UserDefaults.standard.object(forKey: kMTDefaultsLastNotificationSentDateKey) as? Date ?? Date.distantPast
            
            let now = Date()
            let tolerance: TimeInterval = 5 * 60

            if let earliestNotificationDate = Calendar.current.date(byAdding: .hour, value: notificationInterval, to: lastNotificationSentDate),
               Date() >= earliestNotificationDate.addingTimeInterval(-tolerance) {

                // send notification
                await postNotification(for: availableUpdates)
                UserDefaults.standard.set(now, forKey: kMTDefaultsLastNotificationSentDateKey)
            }
        }
    }
}

private func postNotification(for availableUpdates: Int) async {
        
    let notificationCenter = UNUserNotificationCenter.current()
    
    do {
        
        let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound])
        
        guard granted else {
            
            Logger().log("SAPCorp: Notification authorization not granted")
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = (availableUpdates == 1) ? String(localized: "NotificationTitleUpdateAvailableOne") : String(localized: "NotificationTitleUpdateAvailableMultiple")
        content.sound = .default
        content.threadIdentifier = "corp.sap.Patcher.updatesAvailable"
        content.body = (availableUpdates == 1) ? String(localized: "NotificationBodyUpdateAvailableOne") : String(format: String(localized: "NotificationBodyUpdateAvailableMultiple"), availableUpdates)
        
        let request = UNNotificationRequest(
            identifier: "corp.sap.Patcher.updatesAvailable.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        
        try await notificationCenter.add(request)
                    
    } catch {
        
        Logger().error("SAPCorp: Failed to post notification: \(String(describing: error), privacy: .public)")
    }
}

private func openPatcherApplicationFromNotification() async {
    
    guard let patcherURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: kMTPreferenceDomain) else {
        
        Logger().error("SAPCorp: Failed to find Patcher application with bundle identifier \(kMTPreferenceDomain, privacy: .public)")
        return
    }
    
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    
    do {
        
        Logger().log("SAPCorp: Opening Patcher application at \(patcherURL.path, privacy: .public)")
        
        _ = try await NSWorkspace.shared.openApplication(at: patcherURL, configuration: configuration)
                
    } catch {
        
        Logger().error("SAPCorp: Failed to open Patcher application: \(String(describing: error), privacy: .public)")
    }
}

@MainActor
private func runPatcherAgentApplication() {
    
    let app = NSApplication.shared
    let appDelegate = PatcherAgentAppDelegate()
    
    app.delegate = appDelegate
    app.run()
}

MainActor.assumeIsolated {
    
    runPatcherAgentApplication()
}
