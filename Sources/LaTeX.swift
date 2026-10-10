import Foundation

enum LaTeX {
    /// Convert TeX delimiters, retaining the math source rather than changing its meaning.
    static func markdownFormula(_ source: String) -> String? {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("$"), trimmed.hasSuffix("$") { return nil }
        var result = source
        var converted = false
        let delimiters: [(String, Bool)] = [
            (#"(?s)\\\[(.+?)\\\]"#, true),
            (#"(?s)\\\((.+?)\\\)"#, false),
            (#"(?s)\\begin\{(equation\*?|displaymath|math|align\*?|gather\*?)\}(.+?)\\end\{\1\}"#, true)
        ]
        for (pattern, display) in delimiters {
            let regex = try! NSRegularExpression(pattern: pattern)
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                let ns = result as NSString
                let environment = match.numberOfRanges == 3 ? ns.substring(with: match.range(at: 1)) : ""
                let group = match.numberOfRanges == 3 ? 2 : 1
                var body = ns.substring(with: match.range(at: group)).trimmingCharacters(in: .whitespacesAndNewlines)
                if environment.hasPrefix("align") { body = "\\begin{aligned}\n" + body + "\n\\end{aligned}" }
                if environment.hasPrefix("gather") { body = "\\begin{gathered}\n" + body + "\n\\end{gathered}" }
                let block = display && environment != "math"
                let replacement = block ? "$$\n\(body)\n$$" : "$\(body)$"
                result = ns.replacingCharacters(in: match.range, with: replacement)
                converted = true
            }
        }
        if converted { return result }
        // Only known mathematical commands qualify as unwrapped TeX; normal prose does not.
        let commands = try! NSRegularExpression(pattern: #"\\(?:frac|dfrac|tfrac|sqrt|sum|prod|int|iint|lim|sin|cos|tan|log|ln|exp|alpha|beta|gamma|delta|theta|lambda|mu|pi|sigma|phi|omega|infty|partial|nabla|vec|mathbf|mathrm|mathbb|left|right|begin\{(?:matrix|pmatrix|bmatrix|aligned|cases)\})(?![A-Za-z])"#)
        guard !trimmed.contains("$"), commands.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil else { return nil }
        var depth = 0
        for character in trimmed {
            if character == "{" { depth += 1 }
            if character == "}" { depth -= 1; if depth < 0 { return nil } }
        }
        guard depth == 0 else { return nil }
        return trimmed.contains("\n") ? "$$\n\(trimmed)\n$$" : "$\(trimmed)$"
    }
}
