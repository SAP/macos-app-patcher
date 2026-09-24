/*
    AppDelegate.swift
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

import Cocoa
import OSLog

@main
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    
    private var settingsWindowController: NSWindowController!
    private let applicationInstallationMonitor = MTApplicationInstallationMonitor()

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        
        // register our value transformers
        let titleTransformer = MTButtonTitleTransformer()
        ValueTransformer.setValueTransformer(
            titleTransformer,
            forName: NSValueTransformerName("MTButtonTitleTransformer")
        )
        
        let versionInfoTransformer = MTVersionInfoTransformer()
        ValueTransformer.setValueTransformer(
            versionInfoTransformer,
            forName: NSValueTransformerName("MTVersionInfoTransformer")
        )
        
        let markdownTransformer = MTMarkdownTransformer()
        ValueTransformer.setValueTransformer(
            markdownTransformer,
            forName: NSValueTransformerName("MTMarkdownTransformer")
        )
        
        Task { @MainActor in
            
            await MTDaemonSession.shared.start()
            applicationInstallationMonitor.start()
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool
    {
        return true
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        
        applicationInstallationMonitor.stop()
        MTDaemonSession.shared.invalidate()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    // MARK: - IBActions
    
    @IBAction func showSettingsWindow(_ sender: Any) {
        
        if settingsWindowController == nil {
            
            let storyboard = NSStoryboard(name: NSStoryboard.Name("Main"), bundle: nil)
            settingsWindowController = storyboard.instantiateController(withIdentifier: "corp.sap.Patcher.SettingsController") as? NSWindowController
        }
        
        NSApp.activate(ignoringOtherApps: true)
        
        settingsWindowController.showWindow(nil)
        settingsWindowController.window?.makeKeyAndOrderFront(nil)
    }
    
    @IBAction func openGitHub(_ sender: Any)
    {
        NSWorkspace.shared.open(URL(string: kMTGitHubURL)!)
    }
}

