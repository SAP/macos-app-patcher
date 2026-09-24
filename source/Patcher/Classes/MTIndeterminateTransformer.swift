//
//  MTIndeterminateTransformer.swift
//  Patcher
//
//  Created by Thielemann, Marc on 03.06.26.
//

import Foundation

@objc(MTIndeterminateTransformer)
final class MTIndeterminateTransformer: ValueTransformer {

    override class func allowsReverseTransformation() -> Bool {
        false
    }

    override func transformedValue(_ value: Any?) -> Any? {
        
        var indeterminate = true
        
        if let application = value as? MTApplication {
            
            indeterminate = (application.isInstalling && application.installProgress == 1)
        }
        
        return indeterminate
    }
}
