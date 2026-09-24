/*
    MTUpdatesViewController.swift
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

class MTUpdatesViewController: NSViewController {

    @IBOutlet weak var arrayController: NSArrayController!
    @IBOutlet weak var tableView: NSTableView!
    
    @objc dynamic var updateCheckDone: Bool = false
    
    override func viewDidLoad() {
        
        super.viewDidLoad()
        
        tableView.usesAutomaticRowHeights = true
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationsDidChange),
            name: MTCachedApplications.applicationsDidChangeNotification,
            object: MTCachedApplications.shared
        )
        
        configureArrayController()
        updateContent()
        
        Task { [weak self] in
            
            await MTDaemonSession.shared.start()
            
            MTDaemonSession.shared.refreshApplications { error in
                
                DispatchQueue.main.async { self?.updateCheckDone = true }
                
                guard let error else { return }

                Logger().error("SAPCorp: Failed to load applications: \(String(describing: error), privacy: .public)")

                DispatchQueue.main.async { [weak self] in
                    
                    guard let self = self else { return }

                    let alert = NSAlert()
                    alert.messageText = String(localized: "ApplicationsLoadFailedErrorTitle")
                    alert.informativeText = String(localized: "ApplicationsLoadFailedErrorText")
                    alert.addButton(withTitle: String(localized: "ButtonTitleQuit"))
                    alert.alertStyle = .critical

                    if let window = self.view.window {
                        
                        alert.beginSheetModal(for: window) { _ in
                            NSApp.terminate(nil)
                        }
                        
                    } else {
                        
                        // fallback in case the window doesn't exist yet
                        let response = alert.runModal()
                        if response == .alertFirstButtonReturn {
                            NSApp.terminate(nil)
                        }
                    }
                }
            }
        }
    }
    
    override func viewWillAppear() {
        
        super.viewWillAppear()
        
        arrayController.rearrangeObjects()
        tableView.reloadData()
    }
    
    deinit {
        
        NotificationCenter.default.removeObserver(self)
    }
    
    @IBAction func installButtonClicked(_ sender: NSButton) {
        
        let buttonPoint = sender.convert(NSPoint.zero, to: tableView)
        let row = tableView.row(at: buttonPoint)

        guard row >= 0, let objects = arrayController.arrangedObjects as? [MTApplication] else { return }
        
        let item = objects[row]
        
        guard !item.isInstalling else { return }
        
        confirmSelfUpdateIfNeeded(for: item) { [weak self] shouldInstall in
            
            guard let self, shouldInstall else { return }
            
            self.installApplication(item)
        }
    }
    
    @objc private func applicationsDidChange() {
        
        DispatchQueue.main.async {
            self.updateContent()
        }
    }
    
    private func configureArrayController() {
        
        var deferralDays = UserDefaults.standard.integer(forKey: kMTDefaultsUpdateDeferralDaysKey)
        if !(0...28).contains(deferralDays) { deferralDays = 0 }
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -deferralDays, to: Date()) ?? Date()
                                
        arrayController.filterPredicate = NSPredicate { object, _ in
            
            guard let application = object as? MTApplication, let installedVersion = application.installedVersion else { return false }
            let latestVersion = application.latestVersion
                                                    
            guard MTVersion.compare(latestVersion, installedVersion) == .orderedDescending else { return false }
            
            guard deferralDays > 0 else { return true }
            
            let iso8601Formatter = ISO8601DateFormatter()
            guard let date = iso8601Formatter.date(from: application.releaseDate) else {
                
                Logger().error("SAPCorp: Ignoring update for \(application.name, privacy: .public) because release date is invalid: \(application.releaseDate, privacy: .public)")
                return false
            }
            
            return date <= cutoffDate
        }
    }
    
    private func updateContent() {
        
        arrayController.content = MTCachedApplications.shared.applications.sorted(by: {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        })
        
        arrayController.rearrangeObjects()
        tableView.reloadData()
    }
    
    private func confirmSelfUpdateIfNeeded(for application: MTApplication, completion: @escaping (_ shouldInstall: Bool) -> Void) {
        
        guard application.isSelfUpdate else {
            completion(true)
            return
        }
        
        let alert = NSAlert()
        alert.messageText = String(localized: "SelfUpdateWarningTitle")
        alert.informativeText = String(localized: "SelfUpdateWarningText")
        alert.addButton(withTitle: String(localized: "ButtonTitleUpdate"))
        alert.addButton(withTitle: String(localized: "ButtonTitleCancel"))
        alert.alertStyle = .warning
        
        if let window = view.window {
            
            alert.beginSheetModal(for: window) { response in
                
                if response == .alertFirstButtonReturn { UserDefaults.standard.set(true, forKey: kMTDefaultsRelaunchAfterSelfUpdateKey) }
                completion(response == .alertFirstButtonReturn)
            }
            
        } else {
            
            let response = alert.runModal()
            
            if response == .alertFirstButtonReturn { UserDefaults.standard.set(true, forKey: kMTDefaultsRelaunchAfterSelfUpdateKey) }
            completion(response == .alertFirstButtonReturn)
        }
    }
    
    private func installApplication(_ application: MTApplication) {
        
        application.isInstalling = true
        application.installProgress = 0
        reloadRow(for: application)
        
        MTDaemonSession.shared.installApplication(withIdentifier: application.identifier) { [weak self] error in
            
            guard let self else { return }
            
            if error != nil {
                
                let alert = NSAlert()
                alert.messageText = String(localized: "UpdateFailedErrorTitle")
                alert.informativeText = String(format: String(localized: "UpdateFailedErrorText"), application.name)
                alert.addButton(withTitle: String(localized: "ButtonTitleOK"))
                alert.alertStyle = .critical
                
                if let window = self.view.window {
                    alert.beginSheetModal(for: window)
                } else {
                    alert.runModal()
                }
                
                application.isInstalling = false
                application.installProgress = 0
                self.reloadRow(for: application)
            }
        }
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
    
    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }
}
