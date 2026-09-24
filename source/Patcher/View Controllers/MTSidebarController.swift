/*
    MTSidebarController.swift
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

class MTSidebarController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    
    @IBOutlet weak var sidebarOutlineView: NSOutlineView!
    
    private static let updatesViewControllerIdentifier = "corp.sap.Patcher.Views.Updates"
    private static let discoverViewControllerIdentifier = "corp.sap.Patcher.Views.Discover"
    
    private var sidebarItems: [MTSidebarItem] = []
    private var viewControllers: [String: NSViewController] = [:]
    
    override func viewDidLoad() {
        
        super.viewDidLoad()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationsDidChange),
            name: MTCachedApplications.applicationsDidChangeNotification,
            object: MTCachedApplications.shared
        )
        
        UserDefaults.standard.addObserver(
            self,
            forKeyPath: kMTDefaultsHideDiscoverSectionKey,
            options: [.new],
            context: nil
        )
    }
    
    override func viewDidAppear() {
        
        super.viewDidAppear()

        reloadSidebarItemsPreservingSelection(fallbackIdentifier: MTSidebarController.updatesViewControllerIdentifier)
    }
    
    @objc private func applicationsDidChange() {
        
        DispatchQueue.main.async {
            self.reloadSidebarItemsPreservingSelection()
        }
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?)
    {
        if keyPath == kMTDefaultsHideDiscoverSectionKey {
            
            DispatchQueue.main.async {
                self.reloadSidebarItemsPreservingSelection()
            }
        }
    }
    
    deinit {
        
        NotificationCenter.default.removeObserver(self)
        UserDefaults.standard.removeObserver(self, forKeyPath: kMTDefaultsHideDiscoverSectionKey, context: nil)
    }
    
    private func makeSidebarItems() -> [MTSidebarItem] {
        
        var items: [MTSidebarItem] = [
            MTSidebarItem(
                label: String(localized: "SidebarItemTitleUpdates"),
                image: NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: nil),
                targetViewControllerIdentifier: MTSidebarController.updatesViewControllerIdentifier,
                enabled: true
            )
        ]
        
        let hideDiscoverSection = UserDefaults.standard.bool(forKey: kMTDefaultsHideDiscoverSectionKey)
        
        if !hideDiscoverSection {
            
            items.append(
                MTSidebarItem(
                    label: String(localized: "SidebarItemTitleDiscover"),
                    image: NSImage(systemSymbolName: "star", accessibilityDescription: nil),
                    targetViewControllerIdentifier: MTSidebarController.discoverViewControllerIdentifier,
                    enabled: MTCachedApplications.shared.applications.count > 0
                )
            )
        }
        
        return items
    }
    
    private func reloadSidebarItemsPreservingSelection(fallbackIdentifier: String = MTSidebarController.updatesViewControllerIdentifier) {
        
        let selectedIdentifier = selectedSidebarItem()?.targetViewControllerIdentifier
        
        sidebarItems = makeSidebarItems()
        sidebarOutlineView.reloadData()
        
        let identifierToSelect: String
        
        if let selectedIdentifier, sidebarItems.contains(where: { $0.targetViewControllerIdentifier == selectedIdentifier }) {
            
            identifierToSelect = selectedIdentifier
            
        } else {
            
            identifierToSelect = fallbackIdentifier
        }
        
        if let row = rowForSidebarItem(withIdentifier: identifierToSelect) {
            
            sidebarOutlineView.selectRowIndexes(
                IndexSet(integer: row),
                byExtendingSelection: false
            )
        }
    }
    
    private func selectedSidebarItem() -> MTSidebarItem? {
        
        let selectedRow = sidebarOutlineView.selectedRow
        
        guard selectedRow >= 0 else {
            return nil
        }
        
        return sidebarOutlineView.item(atRow: selectedRow) as? MTSidebarItem
    }
    
    private func rowForSidebarItem(withIdentifier identifier: String) -> Int? {
        
        guard let item = sidebarItems.first(where: { $0.targetViewControllerIdentifier == identifier }) else {
            return nil
        }
        
        let row = sidebarOutlineView.row(forItem: item)
        
        return row >= 0 ? row : nil
    }
    
    // MARK: - NSOutlineViewDelegate
    
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        
        guard let sidebarItem = item as? MTSidebarItem else { return nil }

        let cell = outlineView.makeView(
            withIdentifier: NSUserInterfaceItemIdentifier("MainCell"),
            owner: self
        ) as! NSTableCellView

        cell.textField?.stringValue = sidebarItem.label
        cell.imageView?.image = sidebarItem.image
        cell.textField?.textColor = sidebarItem.enabled ? .labelColor : .disabledControlTextColor
        cell.imageView?.alphaValue = sidebarItem.enabled ? 1.0 : 0.35

        return cell
    }
    
    func outlineViewSelectionDidChange(_ notification: Notification) {
        
        let row = sidebarOutlineView.selectedRow

        guard row >= 0, let item = sidebarOutlineView.item(atRow: row) as? MTSidebarItem else {
            return
        }

        let identifier = item.targetViewControllerIdentifier
        var targetVC = viewControllers[identifier]
        
        if targetVC == nil {
                    
            targetVC = storyboard?.instantiateController(withIdentifier: identifier) as? NSViewController
            if let targetVC { viewControllers[identifier] = targetVC }
        }

        if let targetVC,
           let splitVC = parent as? NSSplitViewController {

            let splitItem = NSSplitViewItem(viewController: targetVC)

            if let oldItem = splitVC.splitViewItems.last { splitVC.removeSplitViewItem(oldItem) }
            splitVC.addSplitViewItem(splitItem)
            
            view.window?.title = item.label
        }
    }
    
    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        
        guard let sidebarItem = item as? MTSidebarItem else { return false }
        return sidebarItem.enabled
    }
    
    // MARK: - NSOutlineViewDataSource
    
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        
        return sidebarItems[index]
    }
    
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        
        return false
    }
    
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        
        return (item == nil) ? sidebarItems.count : 0
    }
}
