/*
    Constants.swift
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

let kMTPreferenceDomain             = "corp.sap.Patcher"
let kMTGitHubURL                    = "https://github.com/SAP/macos-app-patcher"
let kMTPackageSignature             = "Developer ID Installer: SAP SE (7R5ZEU67FQ)"

let kMTNotificationIntervalMin      = 1
let kMTNotificationIntervalMax      = 24
let kMTNotificationIntervalDefault  = 3
let kMTUpdateDeferralDaysMin        = 0
let kMTUpdateDeferralDaysMax        = 28
let kMTUpdateDeferralDaysDefault    = 0
let kMTUpdateStrategyMin            = 0
let kMTUpdateStrategyMax            = 2
let kMTUpdateStrategyDefault        = 0

// MARK: - Notifications

let kMTNotificationNameApplicationsDidChange = "corp.sap.Patcher.ApplicationsDidChangeNotification"

// MARK: - UserDefaults

let kMTDefaultsSettingsSelectedTabKey           = "SettingsSelectedTab"
let kMTDefaultsHideDiscoverSectionKey           = "HideDiscoverSection"
let kMTDefaultsUpdateStrategyKey                = "UpdateStrategy"
let kMTDefaultsUpdateNotificationIntervalKey    = "UpdateNotificationInterval"
let kMTDefaultsUpdateDeferralDaysKey            = "UpdateDeferralDays"
let kMTDefaultsLastNotificationSentDateKey      = "LastNotificationSentDate"
let kMTDefaultsUpdateCheckLastDateKey           = "LastUpdateCheckDate"
let kMTDefaultsUpdateCheckAvailableItemsKey     = "LastUpdateCheckAvailableItems"
let kMTDefaultsRelaunchAfterSelfUpdateKey       = "RelaunchAfterSelfUpdate"
