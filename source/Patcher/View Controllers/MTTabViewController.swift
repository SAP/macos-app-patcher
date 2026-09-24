/*
    MTTabViewController.swift
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

class MTTabViewController: NSTabViewController {

    private var allowSelection: Bool = false
    
    override func viewDidLoad() {
        
        super.viewDidLoad()
        
        // select the last tab the user selected
        let selectedTabIndex = UserDefaults.standard.integer(forKey: kMTDefaultsSettingsSelectedTabKey)
        allowSelection = true
        
        if selectedTabIndex >= 0 && selectedTabIndex < self.tabViewItems.count {
            self.selectedTabViewItemIndex = selectedTabIndex
        } else {
            self.selectedTabViewItemIndex = 0
        }
        
        self.view.window?.makeFirstResponder(nil)
    }
    
    override func viewWillAppear() {
        
        super.viewWillAppear()
        updateWindowTitle()
    }
    
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        
        super.tabView(tabView, didSelect: tabViewItem)
        updateWindowTitle()
        
        // we ignore the initial tab selection (the one we had to define in Xcode)
        if allowSelection {
            
            if let selectedItem = tabView.selectedTabViewItem {
                UserDefaults.standard.set(tabView.indexOfTabViewItem(selectedItem), forKey: kMTDefaultsSettingsSelectedTabKey)
            }
        }
    }
    
    private func updateWindowTitle() {
        
        // set the window title to the label of the selected tab
        let selectedItem = self.tabView.selectedTabViewItem
        self.tabView.window?.title = selectedItem?.label ?? ""
    }
}
