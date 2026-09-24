/*
    MTSettingsGeneralController.swift
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

class MTSettingsGeneralController: NSViewController {
    
    @objc dynamic var configuredByProfileLabel: String = ""
    
    override func viewDidLoad() {
        
        super.viewDidLoad()
        
        self.configuredByProfileLabel = String(localized: "configuredByProfileLabel")
    }
    
    override func viewWillAppear()
    {
        super.viewWillAppear()
        
        UserDefaults.standard.addObserver(
            self,
            forKeyPath: kMTDefaultsHideDiscoverSectionKey,
            options: [.new],
            context: nil
        )
    }
    
    override func viewWillDisappear()
    {
        super.viewWillDisappear()
        
        UserDefaults.standard.removeObserver(self, forKeyPath: kMTDefaultsHideDiscoverSectionKey, context: nil)
    }
    
    @objc func hideDiscoverSectionIsForced() -> Bool {
        
        return UserDefaults.standard.objectIsForced(forKey: kMTDefaultsHideDiscoverSectionKey)
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?)
    {
        if keyPath == kMTDefaultsHideDiscoverSectionKey {
            
            DispatchQueue.main.async {
                self.willChangeValue(forKey: "hideDiscoverSectionIsForced")
                self.didChangeValue(forKey: "hideDiscoverSectionIsForced")
            }
        }
    }
    
    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }
}
