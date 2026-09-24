/*
    MTDiscoverViewController.swift
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

class MTDiscoverViewController: NSViewController {
    
    @IBOutlet weak var arrayController: NSArrayController!
    @IBOutlet weak var tableView: NSTableView!
    
    private var eventMonitor: Any?
    private var reinstallApp: Bool = false {
        
        didSet {
            guard reinstallApp != oldValue else {
                return
            }
            
            MTButtonTitleTransformer.reinstallApp = reinstallApp
            reloadVisibleRows()
        }
    }
    
    override func viewDidLoad() {
        
        super.viewDidLoad()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationsDidChange),
            name: MTCachedApplications.applicationsDidChangeNotification,
            object: MTCachedApplications.shared
        )
        
        updateContent()
        
        reinstallApp = NSEvent.modifierFlags.contains(.option)
        MTButtonTitleTransformer.reinstallApp = reinstallApp
        
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            
            self?.reinstallApp = event.modifierFlags.contains(.option)            
            return event
        }
    }
    
    deinit {
        
        NotificationCenter.default.removeObserver(self)
        
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }
    
    @IBAction func discoverButtonClicked(_ sender: NSButton)
    {
        let buttonPoint = sender.convert(NSPoint.zero, to: tableView)
        let row = tableView.row(at: buttonPoint)

        if row >= 0 {
            
            if let objects = arrayController.arrangedObjects as? [MTApplication] {
                
                let item = objects[row]
                
                if item.installedVersion != nil && !reinstallApp {
                    
                    if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: item.identifier) {
                        
                        let configuration = NSWorkspace.OpenConfiguration()
                        
                        NSWorkspace.shared.openApplication(
                            at: appURL,
                            configuration: configuration
                        )
                    }
                        
                } else {
                    
                    guard !item.isInstalling else { return }
                   
                    item.isInstalling = true
                    item.installProgress = 0
                    reloadRow(for: item)
                    
                    MTDaemonSession.shared.installApplication(withIdentifier: item.identifier) { error in
                        
                        if error != nil {
                                                        
                            DispatchQueue.main.async {
                                
                                let alert = NSAlert()
                                alert.messageText = String(localized: "InstallationFailedErrorTitle")
                                alert.informativeText = String(format: String(localized: "InstallationFailedErrorText"), item.name)
                                alert.addButton(withTitle: String(localized: "ButtonTitleOK"))
                                alert.alertStyle = .critical
                                alert.beginSheetModal(for: self.view.window!)
                                
                                item.isInstalling = false
                                item.installProgress = 0
                                self.reloadRow(for: item)
                            }
                        }
                    }
                }
            }
        }
    }
    
    @IBAction func websiteButtonClicked(_ sender: NSButton)
    {
        let buttonPoint = sender.convert(NSPoint.zero, to: tableView)
        let row = tableView.row(at: buttonPoint)

        if row >= 0 {
            
            if let objects = arrayController.arrangedObjects as? [MTApplication] {
                
                let releaseURLString = objects[row].downloadURL
                var releaseURL: URL? = nil
                
                if let range = releaseURLString.range(of: "/releases") {
                    
                    releaseURL = URL(string: String(releaseURLString[..<range.lowerBound]))
                }
                
                if releaseURL != nil { NSWorkspace.shared.open(releaseURL!) }
            }
        }
    }
    
    @objc private func applicationsDidChange() {
        
        DispatchQueue.main.async {
            self.updateContent()
        }
    }
    
    private func updateContent() {
        
        arrayController.content = MTCachedApplications.shared.applications
            .filter { !$0.isSelfUpdate }
            .sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        
        arrayController.rearrangeObjects()
        tableView.reloadData()
    }
    
    private func localApplication(withIdentifier identifier: String) -> MTApplication?
    {
        if let arrangedObjects = arrayController.arrangedObjects as? [MTApplication],
           let application = arrangedObjects.first(where: { $0.identifier == identifier }) {
            
            return application
        }
        
        if let content = arrayController.content as? [MTApplication],
           let application = content.first(where: { $0.identifier == identifier }) {
            
            return application
        }
        
        return MTCachedApplications.shared.applications.first(where: { $0.identifier == identifier })
    }
    
    private func reloadRow(for application: MTApplication)
    {
        guard let arrangedObjects = arrayController.arrangedObjects as? [MTApplication],
              let row = arrangedObjects.firstIndex(where: { $0.identifier == application.identifier }) else {
            
            return
        }
        
        let columnIndexes = IndexSet(integersIn: 0..<tableView.numberOfColumns)
        tableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: columnIndexes)
    }
    
    private func reloadVisibleRows() {
        
        let visibleRows = tableView.rows(in: tableView.visibleRect)
        
        guard visibleRows.location != NSNotFound, visibleRows.length > 0 else {
            return
        }
        
        let rowIndexes = IndexSet(integersIn: visibleRows.location..<(visibleRows.location + visibleRows.length))
        let columnIndexes = IndexSet(integersIn: 0..<tableView.numberOfColumns)
        
        tableView.reloadData(forRowIndexes: rowIndexes, columnIndexes: columnIndexes)
    }
    
    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }
}
