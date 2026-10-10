import Foundation

struct MathSource {
    let markdown: String
    let formulas: [(token: String, tex: String, display: Bool)]

    init(_ source: String) {
        // Ordered alternatives keep fenced/inline code, links and escaped dollars untouched.
        let pattern = #"(?m)^ {0,3}(`{3,}|~{3,})[^\n]*\n[\s\S]*?^ {0,3}\1[^\n]*(?:\n|$)|(?m)^(?: {4}|\t)[^\n]*(?:\n|$)|(`+)[^`]*?\2|!?\[[^\]\n]*\]\([^\)\n]*\)|\\\$|\$\$([\s\S]+?)\$\$|\\\[([\s\S]+?)\\\]|\\\(([^\n]+?)\\\)|(?<![\\$])\$(?![\s$])([^\n$]*?[^\s\\$])\$(?!\d)|(?<![\\$])\$(?![\s$])([^\s\\$])\$(?!\d)"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let ns = source as NSString
        let matches = regex.matches(in: source, range: NSRange(location: 0, length: ns.length))
        let prefix = "MOYEMATH" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        var formulas: [(token: String, tex: String, display: Bool)] = []
        var result = source
        var replacements: [(NSRange, String)] = []
        for match in matches {
            guard let group = (3...7).first(where: { match.range(at: $0).location != NSNotFound }) else { continue }
            let token = prefix + "N\(formulas.count)END"
            let tex = ns.substring(with: match.range(at: group))
            let display = group == 3 || group == 4
            formulas.append((token, tex, display))
            // Preserve line numbers for outline navigation.
            let newlines = ns.substring(with: match.range).filter { $0 == "\n" }.count
            replacements.append((match.range, token + String(repeating: "\n", count: newlines)))
        }
        for (range, replacement) in replacements.reversed() { result = (result as NSString).replacingCharacters(in: range, with: replacement) }
        markdown = result; self.formulas = formulas
    }
    func restore(_ html: String) -> String {
        var result = html
        for formula in formulas {
            let element = "<span class=\"moye-math\" data-display=\"\(formula.display ? "true" : "false")\">\(Markdown.escape(formula.tex))</span>"
            result = result.replacingOccurrences(of: formula.token, with: element)
        }
        return result
    }
    func restoreTitle(_ title: String) -> String {
        var result = title
        for formula in formulas { result = result.replacingOccurrences(of: formula.token, with: formula.tex) }
        return result
    }
}

enum MathRuntime {
    static let script: String = {
        guard let url = Bundle.main.url(forResource: "tex-svg-full", withExtension: "js", subdirectory: "MathJax"),
              let script = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return script.replacingOccurrences(of: "</script", with: "<\\/script")
    }()
    static var scripts: String {
        """
        <script>window.MathJax={loader:{load:[]},tex:{packages:['base','ams','newcommand','noundefined','configmacros','boldsymbol','mathtools','cancel','color'],maxBuffer:100000},svg:{fontCache:'none'},options:{enableMenu:false,enableAssistiveMml:false},startup:{typeset:false}};</script>
        <script>\(script)</script>
        <script>
        window.moyeMathReady=(async()=>{
          const nodes=Array.from(document.querySelectorAll('.moye-math'));
          if(!nodes.length)return;
          if(!window.MathJax?.startup?.promise)throw new Error('离线公式组件未加载');
          await MathJax.startup.promise;
          if(!document.getElementById('MJX-offline-styles')){const style=MathJax.startup.document.outputJax.styleSheet(MathJax.startup.document);style.id='MJX-offline-styles';document.head.appendChild(style);}
          for(const node of nodes){
            const tex=node.textContent;
            try{const output=await MathJax.tex2svgPromise(tex,{display:node.dataset.display==='true'});output.querySelectorAll('mjx-assistive-mml').forEach(n=>n.remove());node.replaceChildren(output);}
            catch(error){node.classList.add('math-error');node.textContent=tex;node.title='公式解析失败：'+error.message;}
          }
        })();
        </script>
        """
    }
}
