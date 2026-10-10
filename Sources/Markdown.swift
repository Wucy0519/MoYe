import Foundation
import Darwin

@_silgen_name("cmark_parser_new") private func parserNew(_ options: Int32) -> OpaquePointer?
@_silgen_name("cmark_parser_feed") private func parserFeed(_ parser: OpaquePointer, _ text: UnsafePointer<CChar>, _ length: Int)
@_silgen_name("cmark_parser_finish") private func parserFinish(_ parser: OpaquePointer) -> OpaquePointer?
@_silgen_name("cmark_parser_free") private func parserFree(_ parser: OpaquePointer)
@_silgen_name("cmark_node_free") private func nodeFree(_ node: OpaquePointer)
@_silgen_name("cmark_render_html") private func renderHTML(_ node: OpaquePointer, _ options: Int32, _ extensions: OpaquePointer?) -> UnsafeMutablePointer<CChar>?
@_silgen_name("cmark_gfm_core_extensions_ensure_registered") private func registerExtensions()
@_silgen_name("cmark_find_syntax_extension") private func findExtension(_ name: UnsafePointer<CChar>) -> OpaquePointer?
@_silgen_name("cmark_parser_attach_syntax_extension") private func attachExtension(_ parser: OpaquePointer, _ ext: OpaquePointer) -> Int32
@_silgen_name("cmark_parser_get_syntax_extensions") private func getExtensions(_ parser: OpaquePointer) -> OpaquePointer?
@_silgen_name("cmark_node_first_child") private func firstChild(_ node: OpaquePointer) -> OpaquePointer?
@_silgen_name("cmark_node_next") private func nextNode(_ node: OpaquePointer) -> OpaquePointer?
@_silgen_name("cmark_node_get_type_string") private func typeString(_ node: OpaquePointer) -> UnsafePointer<CChar>?
@_silgen_name("cmark_node_get_literal") private func literal(_ node: OpaquePointer) -> UnsafePointer<CChar>?
@_silgen_name("cmark_node_get_heading_level") private func headingLevel(_ node: OpaquePointer) -> Int32
@_silgen_name("cmark_node_get_start_line") private func startLine(_ node: OpaquePointer) -> Int32

struct Heading { let title: String; let level: Int; let line: Int }
struct RenderedMarkdown { let body: String; let headings: [Heading] }

enum Markdown {
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
    static func render(_ text: String) -> RenderedMarkdown {
        let math = MathSource(text)
        let protected = math.markdown
        registerExtensions()
        guard let parser = parserNew(1 << 9) else { return RenderedMarkdown(body: "", headings: []) }
        defer { parserFree(parser) }
        for name in ["table", "strikethrough", "autolink", "tasklist", "tagfilter"] {
            name.withCString { if let ext = findExtension($0) { _ = attachExtension(parser, ext) } }
        }
        protected.withCString { parserFeed(parser, $0, protected.utf8.count) }
        guard let root = parserFinish(parser) else { return RenderedMarkdown(body: "", headings: []) }
        defer { nodeFree(root) }
        func plain(_ node: OpaquePointer) -> String {
            if let value = literal(node) { return String(cString: value) }
            var result = "", child = firstChild(node)
            while let current = child { result += plain(current); child = nextNode(current) }
            return result
        }
        var headings: [Heading] = []
        func walk(_ node: OpaquePointer) {
            if let type = typeString(node), String(cString: type) == "heading" {
                headings.append(Heading(title: math.restoreTitle(plain(node)), level: Int(headingLevel(node)), line: Int(startLine(node))))
            }
            var child = firstChild(node)
            while let current = child { walk(current); child = nextNode(current) }
        }
        walk(root)
        guard let output = renderHTML(root, 0, getExtensions(parser)) else { return RenderedMarkdown(body: "", headings: headings) }
        defer { free(output) }
        var body = math.restore(String(cString: output))
        if let regex = try? NSRegularExpression(pattern: "<h[1-6]>") {
            let matches = regex.matches(in: body, range: NSRange(body.startIndex..., in: body))
            for (index, match) in matches.enumerated().reversed() {
                let range = Range(match.range, in: body)!
                let tag = String(body[range].dropLast())
                body.replaceSubrange(range, with: tag + " id=\"heading-\(index)\">")
            }
        }
        return RenderedMarkdown(body: body, headings: headings)
    }

    static func page(_ rendered: RenderedMarkdown, title: String, base: String? = nil, interactive: Bool = false, typeset: Bool = true, mathStyles: String = "") -> String {
        let baseTag = base.map { "<base href=\"\(escape($0))\">" } ?? ""
        let policy = "default-src 'none'; img-src moye-resource: file: https: http: data:; style-src 'unsafe-inline'; script-src 'unsafe-inline'; base-uri moye-resource: file:;"
        return """
        <!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="\(policy)">\(baseTag)<title>\(escape(title))</title>
        <style>
        :root{color-scheme:light dark;--bg:#fcfbf8;--ink:#303331;--muted:#777e77;--line:#e4e6df;--accent:#43816d;--code:#f0f2ed}
        @media(prefers-color-scheme:dark){:root{--bg:#202422;--ink:#e0e5df;--muted:#9ba79d;--line:#3c443e;--accent:#8cc6ac;--code:#292f2a}}
        *{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:17px/1.85 -apple-system,BlinkMacSystemFont,"PingFang SC",sans-serif}
        main{max-width:820px;padding:48px 52px 120px;margin:auto;overflow-wrap:anywhere}h1,h2,h3,h4,h5,h6{line-height:1.4;scroll-margin-top:32px;font-weight:650;margin:1.7em 0 .65em}h1{font-size:2em;border-bottom:1px solid var(--line);padding-bottom:.45em}h2{font-size:1.5em}h3{font-size:1.2em}p{margin:1em 0}a{color:var(--accent);text-underline-offset:3px}blockquote{border-left:3px solid var(--accent);color:var(--muted);margin:1.5em 0;padding:.1em 1.2em;background:var(--code)}pre{padding:20px;border-radius:10px;background:var(--code);overflow:auto;line-height:1.6}code{font: .87em/1.6 Menlo,monospace;background:var(--code);border-radius:4px;padding:2px 5px}pre code{padding:0;background:none}img{max-width:100%;height:auto;border-radius:6px}table{border-collapse:collapse;display:block;overflow:auto;margin:1.5em 0}th,td{border:1px solid var(--line);padding:9px 16px}th{background:var(--code)}hr{border:0;border-top:1px solid var(--line);margin:2.5em 0}li{margin:.25em 0}input[type=checkbox]{accent-color:var(--accent)}::selection{background:#a6d5bf66}
        @media(max-width:600px){main{padding:28px 24px 80px}}@media print{:root{color-scheme:light;--bg:white;--ink:#222;--muted:#666;--line:#ddd;--code:#f5f5f5}body{font-size:11pt}main{max-width:none;padding:0}pre,blockquote,tr,img{break-inside:avoid}h1,h2,h3{break-after:avoid}a{color:inherit}pre{white-space:pre-wrap}}
        .moye-math[data-display=true]{display:block;text-align:center;margin:1.2em 0;overflow-x:auto;overflow-y:hidden;padding:.25em 0}mjx-container{max-width:100%}mjx-container svg{max-width:none}mjx-container svg path{fill:currentColor} .math-error{color:#b34939}@media print{.moye-math{break-inside:avoid}.moye-math[data-display=true]{overflow:visible}mjx-container svg{max-width:100%;height:auto}}
        </style>\(mathStyles)</head><body><main>\(rendered.body)</main>
        \(typeset ? MathRuntime.scripts : "")
        \(interactive ? ScrollSync.script : "")
        </body></html>
        """
    }
}
