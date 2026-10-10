import AppKit

final class MarkdownTextView: NSTextView {
    var onSelectionFinished: (() -> Void)?
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        onSelectionFinished?()
    }
    func apply(_ edit: TextEdit) {
        guard (string as NSString).substring(with: edit.range) != edit.replacement else { return }
        insertText(edit.replacement, replacementRange: edit.range)
        setSelectedRange(edit.selection)
    }
    func toggleEmphasis(_ marker: String) {
        apply(Formatting.emphasis(in: string, selection: selectedRange(), marker: marker))
    }
    func regularWeight() {
        let selection = selectedRange()
        let asterisk = Formatting.emphasis(in: string, selection: selection, marker: "**", removeOnly: true)
        if (string as NSString).substring(with: asterisk.range) != asterisk.replacement { apply(asterisk) }
        else { apply(Formatting.emphasis(in: string, selection: selection, marker: "__", removeOnly: true)) }
    }
    func setHeading(_ level: Int) { apply(Formatting.heading(in: string, selection: selectedRange(), level: level)) }
    override func insertNewline(_ sender: Any?) {
        let ns = string as NSString
        let selected = selectedRange()
        guard selected.length == 0 else { super.insertNewline(sender); return }
        let lineRange = ns.lineRange(for: NSRange(location: selected.location, length: 0))
        let before = ns.substring(with: NSRange(location: lineRange.location, length: selected.location - lineRange.location))
        let pattern = "^(\\s*)(?:([-+*]) (?:\\[([ xX])\\] )?|(\\d+)[.)] |> )(.*)$"
        guard let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: before, range: NSRange(location: 0, length: (before as NSString).length)) else { super.insertNewline(sender); return }
        let value = before as NSString
        func group(_ index: Int) -> String { match.range(at: index).location == NSNotFound ? "" : value.substring(with: match.range(at: index)) }
        if group(5).trimmingCharacters(in: .whitespaces).isEmpty {
            insertText("\n", replacementRange: NSRange(location: lineRange.location, length: before.utf16.count))
        } else {
            let marker: String
            if !group(4).isEmpty { marker = "\((Int(group(4)) ?? 0) + 1). " }
            else if !group(2).isEmpty { marker = group(2) + " " + (match.range(at: 3).location == NSNotFound ? "" : "[ ] ") }
            else { marker = "> " }
            insertText("\n" + group(1) + marker, replacementRange: selected)
        }
    }
    func wrap(_ left: String, _ right: String, placeholder: String = "文字") {
        let range = selectedRange()
        let content = range.length > 0 ? (string as NSString).substring(with: range) : placeholder
        insertText(left + content + right, replacementRange: range)
        setSelectedRange(NSRange(location: range.location + left.utf16.count, length: content.utf16.count))
    }
    func prefix(_ prefix: String) {
        let ns = string as NSString, selection = selectedRange()
        var range = ns.lineRange(for: selection)
        if selection.length > 0, range.length > 0, selection.location + selection.length < range.location + range.length {
            range = ns.lineRange(for: NSRange(location: selection.location, length: selection.length - 1))
        }
        let original = ns.substring(with: range)
        var lines = original.components(separatedBy: "\n")
        let ends = lines.last == ""
        if ends { lines.removeLast() }
        let remove = lines.allSatisfy { $0.hasPrefix(prefix) }
        let result = lines.map { remove ? String($0.dropFirst(prefix.count)) : prefix + $0 }.joined(separator: "\n") + (ends ? "\n" : "")
        insertText(result, replacementRange: range)
        setSelectedRange(NSRange(location: range.location, length: result.utf16.count))
    }
    func highlight() {
        guard !hasMarkedText(), let storage = textStorage else { return }
        let all = NSRange(location: 0, length: storage.length)
        let font = NSFont.monospacedSystemFont(ofSize: UserDefaults.standard.double(forKey: "editorFontSize").nonzeroOr(15), weight: .regular)
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 5
        storage.beginEditing()
        storage.setAttributes([.font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph], range: all)
        let rules: [(String, [NSAttributedString.Key: Any])] = [
            ("(?m)^#{1,6} .*$", [.foregroundColor: NSColor.systemTeal, .font: NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .semibold)]),
            ("(?m)^>.*$", [.foregroundColor: NSColor.secondaryLabelColor]),
            ("\\*\\*[^\\n*]+\\*\\*|__[^\\n_]+__", [.font: NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .bold)]),
            ("!?\\[[^\\n\\]]*\\]\\([^\\n)]*\\)", [.foregroundColor: NSColor.systemBlue]),
            ("`[^`\\n]+`", [.foregroundColor: NSColor.systemOrange, .backgroundColor: NSColor.quaternaryLabelColor]),
            ("(?ms)^(`{3,}|~{3,})[^\\n]*\\n.*?^\\1[^\\n]*$", [.foregroundColor: NSColor.secondaryLabelColor, .backgroundColor: NSColor.quaternaryLabelColor])
        ]
        for (pattern, attrs) in rules {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: string, range: all) { storage.addAttributes(attrs, range: match.range) }
        }
        storage.endEditing()
        typingAttributes = [.font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
    }
}

extension Double { func nonzeroOr(_ fallback: Double) -> Double { self == 0 ? fallback : self } }
