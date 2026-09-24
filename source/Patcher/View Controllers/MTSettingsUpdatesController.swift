/*
    MTSettingsUpdatesController.swift
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

class MTSettingsUpdatesController: NSViewController {
    
    @IBOutlet weak var updateStrategyButton: NSPopUpButton!
    @IBOutlet weak var notificationIntervalSlider: NSSlider!
    @IBOutlet weak var deferralDaysSlider: NSSlider!
    
    @objc dynamic var configuredByProfileLabel: String = ""
    @objc dynamic var disableNotificationIntervalSlider: Bool = false
    private var keysToObserve: [String] = [
        kMTDefaultsUpdateStrategyKey,
        kMTDefaultsUpdateNotificationIntervalKey,
        kMTDefaultsUpdateDeferralDaysKey
    ]
    
    override func viewDidLoad() {
        
        super.viewDidLoad()
        
        self.configuredByProfileLabel = String(localized: "configuredByProfileLabel")
        
        setUpdateStrategyButton()
        setNotificationInterval()
        setUpdateDeferralDays()
    }
    
    override func viewWillAppear()
    {
        super.viewWillAppear()
        
        for key in keysToObserve {
            
            UserDefaults.standard.addObserver(
                self,
                forKeyPath: key,
                options: [.new],
                context: nil
            )
        }
    }
    
    override func viewWillDisappear()
    {
        super.viewWillDisappear()
        
        for key in keysToObserve {
            
            UserDefaults.standard.removeObserver(
                self,
                forKeyPath: key,
                context: nil
            )
        }
    }
    
    func setUpdateStrategyButton() -> Void
    {
        DispatchQueue.main.async {
            self.willChangeValue(forKey: "updateStrategyIsForced")
            var updateStrategy = UserDefaults.standard.integer(forKey: kMTDefaultsUpdateStrategyKey)
            if !(kMTUpdateStrategyMin...kMTUpdateStrategyMax).contains(updateStrategy) { updateStrategy = kMTUpdateStrategyDefault }
            self.updateStrategyButton.selectItem(withTag: updateStrategy)
            self.didChangeValue(forKey: "updateStrategyIsForced")
            
            self.disableNotificationIntervalSlider = (self.updateStrategyButton.selectedTag() != 1)
        }
    }
    
    func setNotificationInterval() -> Void
    {
        DispatchQueue.main.async {
            self.willChangeValue(forKey: "updateNotificationIntervalIsForced")
            var notificationInterval = UserDefaults.standard.integer(forKey: kMTDefaultsUpdateNotificationIntervalKey)
            if !(kMTNotificationIntervalMin...kMTNotificationIntervalMax).contains(notificationInterval) { notificationInterval = kMTNotificationIntervalDefault }
            self.notificationIntervalSlider.doubleValue = Double(notificationInterval)
            self.notificationIntervalSlider.toolTip = String(format: String(localized: "updateNotificationIntervalTooltip"), notificationInterval)
            self.didChangeValue(forKey: "updateNotificationIntervalIsForced")
        }
    }
    
    func setUpdateDeferralDays() -> Void
    {
        DispatchQueue.main.async {
            self.willChangeValue(forKey: "updateDeferralDaysIsForced")
            var deferralDays = UserDefaults.standard.integer(forKey: kMTDefaultsUpdateDeferralDaysKey)
            if !(kMTUpdateDeferralDaysMin...kMTUpdateDeferralDaysMax).contains(deferralDays) { deferralDays = kMTUpdateDeferralDaysDefault }
            self.deferralDaysSlider.doubleValue = Double(deferralDays)
            self.deferralDaysSlider.toolTip = String(format: String(localized: "updateDeferralDaysTooltip"), deferralDays)
            self.didChangeValue(forKey: "updateDeferralDaysIsForced")
        }
    }
    
    @objc func updateStrategyIsForced() -> Bool {

        return UserDefaults.standard.objectIsForced(forKey: kMTDefaultsUpdateStrategyKey)
    }
    
    @objc func updateNotificationIntervalIsForced() -> Bool {
        
        return UserDefaults.standard.objectIsForced(forKey: kMTDefaultsUpdateNotificationIntervalKey)
    }
    
    @objc func updateDeferralDaysIsForced() -> Bool {
        
        return UserDefaults.standard.objectIsForced(forKey: kMTDefaultsUpdateDeferralDaysKey)
    }
    
    @IBAction func updateStrategyChanged(_ sender: NSPopUpButton)
    {
        self.disableNotificationIntervalSlider = (self.updateStrategyButton.selectedTag() != 1)
        
        MTDaemonSession.shared.setUpdateStrategy(sender.selectedTag()) { success, error in
            
            if !success { self.setUpdateStrategyButton() }
        }
    }
    
    @IBAction func notificationIntervalChanged(_ sender: NSSlider)
    {
        UserDefaults.standard.set(NSNumber(value: Int(sender.doubleValue)), forKey: kMTDefaultsUpdateNotificationIntervalKey)
    }
    
    @IBAction func deferralDaysChanged(_ sender: NSSlider)
    {
        let deferral = Int(sender.doubleValue)
        
        MTDaemonSession.shared.setDeferralDays(deferral) { success, error in
         
            if !success { self.setUpdateDeferralDays() }
        }
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?)
    {
        if keyPath == kMTDefaultsUpdateStrategyKey {

            setUpdateStrategyButton()
            
        } else if keyPath == kMTDefaultsUpdateNotificationIntervalKey {
            
            setNotificationInterval()
            
        } else if keyPath == kMTDefaultsUpdateDeferralDaysKey {
            
            setUpdateDeferralDays()
        }
    }
    
    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }
}
