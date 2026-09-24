/*
    MTMarkdownTransformer.swift
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
import Foundation

@objc(MTMarkdownTransformer)
final class MTMarkdownTransformer: ValueTransformer {

    override class func transformedValueClass() -> AnyClass {
        NSAttributedString.self
    }

    override class func allowsReverseTransformation() -> Bool {
        false
    }

    override func transformedValue(_ value: Any?) -> Any?
    {
        guard let markdown = value as? String ?? value as? NSString as String? else {
            return NSAttributedString(string: "")
        }

        return attributedReleaseNotes(from: markdown)
    }

    private func attributedReleaseNotes(from markdown: String) -> NSAttributedString
    {
        let normalizedMarkdown = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(
                of: #"(?i)<br\s*/?>"#,
                with: "",
                options: .regularExpression
            )

        let lines = normalizedMarkdown
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        let result = NSMutableAttributedString()

        for (index, line) in lines.enumerated() {

            let lineAttributedString: NSMutableAttributedString

            if let heading = Self.heading(in: line) {

                lineAttributedString = parsedInlineMarkdown(heading.content)
                applyDefaultTextAttributes(to: lineAttributedString)
                applyHeadingStyle(level: heading.level, to: lineAttributedString)

            } else if let unorderedListItem = Self.unorderedListItem(in: line) {

                lineAttributedString = NSMutableAttributedString(
                    string: "• ",
                    attributes: [
                        .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                        .foregroundColor: NSColor.labelColor
                    ]
                )

                let content = parsedInlineMarkdown(unorderedListItem.content)
                applyDefaultTextAttributes(to: content)
                lineAttributedString.append(content)

                applyListParagraphStyle(
                    indentationLevel: unorderedListItem.indentationLevel,
                    to: lineAttributedString
                )

            } else if let orderedListItem = Self.orderedListItem(in: line) {

                lineAttributedString = NSMutableAttributedString(
                    string: "\(orderedListItem.marker) ",
                    attributes: [
                        .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                        .foregroundColor: NSColor.labelColor
                    ]
                )

                let content = parsedInlineMarkdown(orderedListItem.content)
                applyDefaultTextAttributes(to: content)
                lineAttributedString.append(content)

                applyListParagraphStyle(
                    indentationLevel: orderedListItem.indentationLevel,
                    to: lineAttributedString
                )

            } else {

                lineAttributedString = parsedInlineMarkdown(line)
                applyDefaultTextAttributes(to: lineAttributedString)
            }

            result.append(lineAttributedString)

            if index < lines.count - 1 {
                result.append(NSAttributedString(string: "\n"))
            }
        }

        applyLinkStyle(to: result)

        return result
    }

    private func parsedInlineMarkdown(_ markdown: String) -> NSMutableAttributedString
    {
        do {
            let attributedString = try AttributedString(
                markdown: markdown,
                options: AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .inlineOnlyPreservingWhitespace
                )
            )

            return NSMutableAttributedString(
                attributedString: NSAttributedString(attributedString)
            )

        } catch {
            return NSMutableAttributedString(string: markdown)
        }
    }

    private func applyDefaultTextAttributes(to attributedString: NSMutableAttributedString)
    {
        guard attributedString.length > 0 else { return }

        let fullRange = NSRange(location: 0, length: attributedString.length)

        var rangesWithoutFont: [NSRange] = []
        var rangesWithoutForegroundColor: [NSRange] = []

        attributedString.enumerateAttribute(
            .font,
            in: fullRange
        ) { value, range, _ in

            if value == nil {
                rangesWithoutFont.append(range)
            }
        }

        attributedString.enumerateAttribute(
            .foregroundColor,
            in: fullRange
        ) { value, range, _ in

            if value == nil {
                rangesWithoutForegroundColor.append(range)
            }
        }

        for range in rangesWithoutFont {
            attributedString.addAttribute(
                .font,
                value: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                range: range
            )
        }

        for range in rangesWithoutForegroundColor {
            attributedString.addAttribute(
                .foregroundColor,
                value: NSColor.labelColor,
                range: range
            )
        }
    }

    private func applyHeadingStyle(
        level: Int,
        to attributedString: NSMutableAttributedString
    ) {
        guard attributedString.length > 0 else {
            return
        }

        let fontSize: CGFloat
        let spacingBefore: CGFloat
        let spacingAfter: CGFloat

        switch level {
        case 1:
            fontSize = NSFont.systemFontSize + 7
            spacingBefore = 10
            spacingAfter = 10

        case 2:
            fontSize = NSFont.systemFontSize + 5
            spacingBefore = 8
            spacingAfter = 8

        case 3:
            fontSize = NSFont.systemFontSize + 3
            spacingBefore = 6
            spacingAfter = 6

        default:
            fontSize = NSFont.systemFontSize
            spacingBefore = 4
            spacingAfter = 4
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.paragraphSpacingBefore = spacingBefore
        paragraphStyle.paragraphSpacing = spacingAfter

        attributedString.addAttributes(
            [
                .font: NSFont.systemFont(
                    ofSize: fontSize,
                    weight: .semibold
                ),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraphStyle
            ],
            range: NSRange(location: 0, length: attributedString.length)
        )
    }

    private func applyListParagraphStyle(
        indentationLevel: Int,
        to attributedString: NSMutableAttributedString
    ) {
        guard attributedString.length > 0 else { return }

        let baseIndent = CGFloat(indentationLevel) * 18
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.firstLineHeadIndent = baseIndent
        paragraphStyle.headIndent = baseIndent + 18
        paragraphStyle.paragraphSpacing = 2

        attributedString.addAttribute(
            .paragraphStyle,
            value: paragraphStyle,
            range: NSRange(location: 0, length: attributedString.length)
        )
    }

    private func applyLinkStyle(to attributedString: NSMutableAttributedString)
    {
        guard attributedString.length > 0 else { return }

        let fullRange = NSRange(location: 0, length: attributedString.length)

        attributedString.enumerateAttribute(
            .link,
            in: fullRange
        ) { value, range, _ in

            guard value != nil else {
                return
            }

            attributedString.addAttributes(
                [
                    .foregroundColor: NSColor.linkColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ],
                range: range
            )
        }
    }

    private static func heading(in line: String) -> (level: Int, content: String)?
    {
        let leadingSpaces = line.prefix { $0 == " " }.count

        guard leadingSpaces <= 3 else { return nil }

        let trimmedLine = line.dropFirst(leadingSpaces)

        var level = 0

        for character in trimmedLine {
            if character == "#" {
                level += 1
            } else {
                break
            }
        }

        guard (1...6).contains(level) else { return nil }

        let afterHashes = trimmedLine.dropFirst(level)

        guard afterHashes.isEmpty || afterHashes.first == " " || afterHashes.first == "\t" else {
            return nil
        }

        let content = afterHashes.drop { $0 == " " || $0 == "\t" }

        return (
            level: level,
            content: String(content)
        )
    }

    private static func unorderedListItem(in line: String) -> (indentationLevel: Int, content: String)?
    {
        let leadingWhitespace = line.prefix { $0 == " " || $0 == "\t" }
        let trimmedLine = line.dropFirst(leadingWhitespace.count)

        guard let marker = trimmedLine.first,
              marker == "-" || marker == "*" || marker == "+"
        else {
            return nil
        }

        let afterMarker = trimmedLine.dropFirst()

        guard afterMarker.first == " " || afterMarker.first == "\t" else {
            return nil
        }

        let content = afterMarker.drop { $0 == " " || $0 == "\t" }

        return (
            indentationLevel: indentationLevel(for: String(leadingWhitespace)),
            content: String(content)
        )
    }

    private static func orderedListItem(in line: String) -> (indentationLevel: Int, marker: String, content: String)?
    {
        let leadingWhitespace = line.prefix { $0 == " " || $0 == "\t" }
        let trimmedLine = line.dropFirst(leadingWhitespace.count)

        let digits = trimmedLine.prefix { $0.isNumber }

        guard !digits.isEmpty else { return nil }

        let afterDigits = trimmedLine.dropFirst(digits.count)

        guard let markerCharacter = afterDigits.first,
              markerCharacter == "." || markerCharacter == ")"
        else {
            return nil
        }

        let afterMarker = afterDigits.dropFirst()

        guard afterMarker.first == " " || afterMarker.first == "\t" else {
            return nil
        }

        let content = afterMarker.drop { $0 == " " || $0 == "\t" }

        return (
            indentationLevel: indentationLevel(for: String(leadingWhitespace)),
            marker: "\(digits)\(markerCharacter)",
            content: String(content)
        )
    }

    private static func indentationLevel(for whitespace: String) -> Int
    {
        let visualWidth = whitespace.reduce(0) { partialResult, character in

            if character == "\t" {
                return partialResult + 4
            } else {
                return partialResult + 1
            }
        }

        return visualWidth / 2
    }
}
