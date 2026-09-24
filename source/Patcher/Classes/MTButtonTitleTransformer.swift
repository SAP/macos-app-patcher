/*
    MTButtonTitleTransformer.swift
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

@objc(MTButtonTitleTransformer)

final class MTButtonTitleTransformer: ValueTransformer {
    
    static var reinstallApp = false

    override class func transformedValueClass() -> AnyClass {
        NSString.self
    }

    override class func allowsReverseTransformation() -> Bool {
        false
    }

    override func transformedValue(_ value: Any?) -> Any? {
        
        var returnValue: String?


        if value != nil {
            
                returnValue = (Self.reinstallApp) ? String(localized: "ButtonTitleReinstall") : String(localized: "ButtonTitleOpen")
            
        } else {
            
            returnValue = String(localized: "ButtonTitleInstall")
        }

        return returnValue
    }
}
