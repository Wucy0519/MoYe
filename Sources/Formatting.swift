import Foundation

struct TextEdit {
    let range: NSRange
    let replacement: String
    let selection: NSRange
}

enum Formatting {
    static func emphasis(in text: String, selection: NSRange, marker: String, removeOnly: Bool = false) -> TextEdit {
        let ns = text as NSString
        let width = marker.utf16.count
        var range = selection
        var content = ns.substring(with: selection)
        if content.hasPrefix(marker), content.hasSuffix(marker), content.utf16.count >= width * 2 {
            content = String(content.dropFirst(marker.count).dropLast(marker.count))
            return TextEdit(range: range, replacement: content, selection: NSRange(location: range.location, length: content.utf16.count))
        }
        if selection.location >= width, NSMaxRange(selection) + width <= ns.length,
           ns.substring(with: NSRange(location: selection.location - width, length: width)) == marker,
           ns.substring(with: NSRange(location: NSMaxRange(selection), length: width)) == marker {
            range = NSRange(location: selection.location - width, length: selection.length + width * 2)
            return TextEdit(range: range, replacement: content, selection: NSRange(location: range.location, length: content.utf16.count))
        }
        if removeOnly { return TextEdit(range: selection, replacement: content, selection: selection) }
        if content.isEmpty { content = "文字" }
        return TextEdit(range: range, replacement: marker + content + marker, selection: NSRange(location: range.location + width, length: content.utf16.count))
    }

    static func heading(in text: String, selection: NSRange, level: Int) -> TextEdit {
        let ns = text as NSString
        // A selection ending at the start of another line does not include that line.
        let covered = NSRange(location: selection.location, length: max(0, selection.length - (selection.length > 0 ? 1 : 0)))
        var range = ns.lineRange(for: covered)
        var lines = ns.substring(with: range).components(separatedBy: "\n")
        let trailingNewline = lines.last == "" && range.length > 0
        if trailingNewline { lines.removeLast() }
        let atx = try! NSRegularExpression(pattern: "^ {0,3}#{1,6}(?:[ \\t]+|$)")
        let setext = try! NSRegularExpression(pattern: "^ {0,3}(?:=+|-+)[ \\t]*$")
        // Include a Setext underline immediately below a single selected title line.
        if lines.count == 1, NSMaxRange(range) < ns.length {
            let next = ns.lineRange(for: NSRange(location: NSMaxRange(range), length: 0))
            let value = ns.substring(with: next).trimmingCharacters(in: .newlines)
            if setext.firstMatch(in: value, range: NSRange(location: 0, length: value.utf16.count)) != nil,
               !lines[0].trimmingCharacters(in: .whitespaces).isEmpty {
                range.length += next.length
            }
        }
        let prefix = level == 0 ? "" : String(repeating: "#", count: min(6, max(1, level))) + " "
        var output: [String] = []
        for (index, line) in lines.enumerated() {
            if index > 0, setext.firstMatch(in: line, range: NSRange(location: 0, length: line.utf16.count)) != nil,
               !lines[index - 1].trimmingCharacters(in: .whitespaces).isEmpty { continue }
            let clean = atx.stringByReplacingMatches(in: line, range: NSRange(location: 0, length: line.utf16.count), withTemplate: "")
            output.append(clean.trimmingCharacters(in: .whitespaces).isEmpty ? clean : prefix + clean)
        }
        let replacement = output.joined(separator: "\n") + (trailingNewline ? "\n" : "")
        return TextEdit(range: range, replacement: replacement, selection: NSRange(location: range.location, length: replacement.utf16.count))
    }
}
