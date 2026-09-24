/*
    MTColoredButton.swift
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

class MTColoredButton: NSButton {

    override var title: String {
        didSet {
            updateAttributedTitle()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        updateAttributedTitle()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        updateAttributedTitle()
    }

    private func updateAttributedTitle() {
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .foregroundColor: NSColor.controlAccentColor,
                .font: font ?? NSFont.systemFont(ofSize: 13)
            ]
        )
    }
}
