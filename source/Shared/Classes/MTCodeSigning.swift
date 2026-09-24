/*
    MTCodeSigning.swift
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
import Security

extension SecCertificate {
    var commonName: String? {
        var name: CFString?
        guard SecCertificateCopyCommonName(self, &name) == errSecSuccess else {
            return nil
        }
        return name as String?
    }
}

class MTCodeSigning {
    
    enum CodeSigningError: Error {
        case copyCodeObject(OSStatus)
        case copyStaticCode(OSStatus)
        case copySigningInfo(OSStatus)
        case noCertificate
        case noCommonName
    }
    
    func signingAuthority() throws -> String
    {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess,
              let code else {
            throw CodeSigningError.copyCodeObject(errSecInternalError)
        }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
              let staticCode else {
            throw CodeSigningError.copyStaticCode(errSecInternalError)
        }

        var info: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            .init(rawValue: kSecCSSigningInformation),
            &info
        ) == errSecSuccess,
        let info = info as? [String: Any],
        let certificates = info[kSecCodeInfoCertificates as String] as? [SecCertificate],
        let cn = certificates.first?.commonName
        else {
            throw CodeSigningError.noCommonName
        }

        return cn
    }
    
    func codeSigningRequirements(commonName: String, bundleIdentifier: String, versionString: String) -> String
    {
        return "anchor trusted and certificate leaf [subject.CN] = \"\(commonName)\" and info [CFBundleShortVersionString] >= \"\(versionString)\" and info [CFBundleIdentifier] = \(bundleIdentifier)"
    }
}
