/*
    PatcherDaemonPreferences.swift
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

extension PatcherDaemon {
    
    private static let allowedUpdateStrategies: Set<Int> = [0, 1, 2]
    private static let allowedDeferralDays = (0...28)
    private static let domain = kMTPreferenceDomain as CFString
    
    func setUpdateStrategy(_ updateStrategy: Int, reply: @escaping (_ success: Bool) -> Void)
    {
        let key = kMTDefaultsUpdateStrategyKey as CFString
        let value = NSNumber(value: updateStrategy)
        
        if Self.allowedUpdateStrategies.contains(value.intValue) {
            
            
            // set the value
            CFPreferencesSetValue(key, value, Self.domain, kCFPreferencesAnyUser, kCFPreferencesAnyHost)
            
            // read the value and compare it with the value we set
            let success = (Self.updateStrategy() == updateStrategy) ? true : false
            
            if success, updateStrategy != 1 { Self.setAvailableUpdates(nil) }
    
            reply(success)
            
        } else {
            
            reply(false)
        }
    }
    
    static func updateStrategy() -> Int
    {
        let key = kMTDefaultsUpdateStrategyKey as CFString
        
        var updateStrategy: Int = 0
        if let property = CFPreferencesCopyAppValue(key, Self.domain), let number = property as? NSNumber {
            
            if Self.allowedUpdateStrategies.contains(number.intValue) {
                
                updateStrategy = number.intValue
            }
        }
        
        return updateStrategy
    }
    
    static func setAvailableUpdates(_ availableUpdates: Int?)
    {
        let key = kMTDefaultsUpdateCheckAvailableItemsKey as CFString
        
        if let availableUpdates {
            
            let value = NSNumber(value: availableUpdates)
            
            // set the value
            CFPreferencesSetValue(key, value, Self.domain, kCFPreferencesAnyUser, kCFPreferencesAnyHost)
            
        } else {
            
            // remove the value
            CFPreferencesSetValue(key, nil, Self.domain, kCFPreferencesAnyUser, kCFPreferencesAnyHost)
        }
    }
    
    static func setLastUpdateCheck(_ lastCheck: Date)
    {
        let key = kMTDefaultsUpdateCheckLastDateKey as CFString
        let value = lastCheck as NSDate
            
        // set the value
        CFPreferencesSetValue(key, value, Self.domain, kCFPreferencesAnyUser, kCFPreferencesAnyHost)
    }
    
    static func deferralDays() -> Int
    {
        let key = kMTDefaultsUpdateDeferralDaysKey as CFString
        
        var deferral: Int = 0
        if let property = CFPreferencesCopyAppValue(key, Self.domain), let number = property as? NSNumber {
            
            if Self.allowedDeferralDays.contains(number.intValue) {
                
                deferral = number.intValue
            }
        }
        
        return deferral
    }
    
    func setDeferralDays(_ deferral: Int, reply: @escaping (_ success: Bool) -> Void)
    {
        let key = kMTDefaultsUpdateDeferralDaysKey as CFString
        let value = NSNumber(value: deferral)
            
        // set the value
        CFPreferencesSetValue(key, value, Self.domain, kCFPreferencesAnyUser, kCFPreferencesAnyHost)
        
        // read the value and compare it with the value we set
        let success = (Self.deferralDays() == deferral) ? true : false
        
        reply(success)
    }
}
