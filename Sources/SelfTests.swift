import AppKit

enum SelfTests {
    static func run() {
        func check(_ condition: Bool, _ message: String) { if !condition { fputs("FAIL: \(message)\n", stderr); exit(1) }; print("PASS: \(message)") }
        let sample = "# 中文 **标题**\n\n## 子标题\n\n| A | B |\n| - | - |\n| 1 | 2 |\n\n- [x] 完成\n- [ ] 待办\n\n~~删除~~\n\n```swift\nlet x = 1\n```\n\nhttps://example.com\n\n<script>alert(1)</script>\n\n[危险](javascript:alert(1))\n"
        let rendered = Markdown.render(sample)
        check(rendered.headings.count == 2 && rendered.headings[0].title == "中文 标题" && rendered.headings[1].line == 3, "大纲解析中文、内联格式和行号")
        check(rendered.body.contains("id=\"heading-0\""), "标题锚点")
        check(rendered.body.contains("<table>") && rendered.body.contains("<del>删除</del>"), "GFM 表格和删除线")
        check(rendered.body.contains("type=\"checkbox\"") && rendered.body.contains("checked"), "任务列表")
        check(rendered.body.contains("language-swift") && rendered.body.contains("https://example.com"), "代码块与自动链接")
        check(!rendered.body.contains("<script>") && !rendered.body.contains("href=\"javascript:"), "过滤原始 HTML 和危险链接")
        check(Markdown.render("```\n# 假标题\n```\n\n真正标题\n===").headings.map(\.title) == ["真正标题"], "代码块不污染大纲，支持 Setext 标题")
        let page = Markdown.page(rendered, title: "<title>")
        check(page.contains("&lt;title&gt;") && page.contains("Content-Security-Policy"), "HTML 转义与内容策略")
        let mathSource = #"行内 $\frac{a_1}{b}$ 和 \(\sqrt{x}\)。"# + "\n\n$$\na^2+b^2=c^2\n$$\n\n## 后续标题"
        let math = Markdown.render(mathSource)
        check(math.body.contains(#"\frac{a_1}{b}"#) && math.body.contains(#"\sqrt{x}"#) && math.body.contains("data-display=\"true\""), "数学源码保留反斜杠、下划线及行内块级类型")
        check(math.headings.last?.line == 7, "多行公式后标题行号保留")
        let codeMath = Markdown.render("`$x$`\n\n```tex\n$$\\frac{a}{b}$$\n```\n\n    $indented$\n\n价格 \\$20 和 $30")
        check(!codeMath.body.contains("moye-math"), "代码块、行内代码、缩进代码和货币跳过数学渲染")
        check(Markdown.render("$x$ $y$ $z$").body.components(separatedBy: "class=\"moye-math\"").count == 4, "多个单字符公式识别")
        check(!MathRuntime.script.isEmpty && MathRuntime.script.contains("MathJax"), "应用内离线 MathJax 资源可读取")
        let bold = Formatting.emphasis(in: "中文😀", selection: NSRange(location: 0, length: 4), marker: "**")
        check(bold.replacement == "**中文😀**" && bold.selection == NSRange(location: 2, length: 4), "加粗保留中文及 emoji 选区")
        let regular = Formatting.emphasis(in: "**中文😀**", selection: NSRange(location: 2, length: 4), marker: "**", removeOnly: true)
        check(regular.replacement == "中文😀" && regular.range == NSRange(location: 0, length: 8), "常规字重移除选区外加粗符号")
        let heading = Formatting.heading(in: "## 旧标题\n正文\n", selection: NSRange(location: 3, length: 3), level: 4)
        check(heading.replacement == "#### 旧标题\n" && heading.range.length == 7, "更换标题级别不叠加井号")
        let multiline = Formatting.heading(in: "第一行\n第二行\n第三行", selection: NSRange(location: 0, length: 8), level: 2)
        check(multiline.replacement == "## 第一行\n## 第二行\n" && multiline.range.length == 8, "多行标题不影响选区末尾之后的行")
        let setext = Formatting.heading(in: "标题\n===\n正文", selection: NSRange(location: 0, length: 2), level: 3)
        check(setext.replacement == "### 标题\n" && setext.range.length == 7, "转换 Setext 标题并移除下划线")
        let paragraph = Formatting.heading(in: "### 标题", selection: NSRange(location: 4, length: 2), level: 0)
        check(paragraph.replacement == "标题", "标题恢复正文")
        check(LaTeX.markdownFormula(#"\(\frac{a}{b}\)"#) == #"$\frac{a}{b}$"#, "LaTeX 行内公式转换")
        check(LaTeX.markdownFormula(#"\[x^2 + y^2\]"#) == "$$\nx^2 + y^2\n$$", "LaTeX 块级公式转换")
        check(LaTeX.markdownFormula(#"\begin{align}a&=b\\c&=d\end{align}"#) == "$$\n\\begin{aligned}\na&=b\\\\c&=d\n\\end{aligned}\n$$", "align 环境保留多行对齐")
        check(LaTeX.markdownFormula(#"面积为 \(a b\)，周长为 \(2a+2b\)。"#) == "面积为 $a b$，周长为 $2a+2b$。", "公式转换保留周围中文")
        check(LaTeX.markdownFormula(#"\sqrt{x}"#) == #"$\sqrt{x}$"#, "识别未加分隔符的数学命令")
        check(LaTeX.markdownFormula("普通文字") == nil && LaTeX.markdownFormula(#"$\alpha$"#) == nil && LaTeX.markdownFormula(#"\frac{a"#) == nil, "排除普通文字、现有 Markdown 公式和残缺表达式")
        do {
            let doc = MarkdownDocument()
            let bytes = "# 测试\r\n内容 😀\r\n".data(using: .utf8)!
            try doc.read(from: bytes, ofType: "net.daringfireball.markdown")
            let savedUTF8 = try doc.data(ofType: "net.daringfireball.markdown")
            check(doc.text == "# 测试\n内容 😀\n" && savedUTF8 == bytes, "UTF-8 中文和 CRLF 无损往返")
            let utf16 = "# UTF16\r\n中文".data(using: .utf16)!
            try doc.read(from: utf16, ofType: "net.daringfireball.markdown")
            let savedUTF16 = try doc.data(ofType: "net.daringfireball.markdown")
            check(doc.sourceEncoding == .utf16 && String(data: savedUTF16, encoding: .utf16) == "# UTF16\r\n中文", "UTF-16 往返")
            do { try doc.read(from: Data([0xff, 0x00, 0xfe]), ofType: "net.daringfireball.markdown"); check(false, "拒绝错误编码") } catch { print("PASS: 拒绝错误编码") }
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("moye-test-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            doc.sourceEncoding = .utf8; doc.lineEnding = "\n"; doc.text = "# 新文件\n保存成功"
            let url = directory.appendingPathComponent("测试.md")
            try doc.write(to: url, ofType: "net.daringfireball.markdown")
            check(try String(contentsOf: url, encoding: .utf8) == doc.text, "磁盘写入和重新读取")
        } catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
        if CommandLine.arguments.contains("--scroll-test") { runScrollTests(); return }
        guard CommandLine.arguments.contains("--editor-test") else { print("全部数据自检通过"); return }
        _ = NSApplication.shared
        let editor = MarkdownTextView(); editor.allowsUndo = true
        editor.string = "- [x] 完成"; editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0)); editor.insertNewline(nil)
        check(editor.string == "- [x] 完成\n- [ ] ", "任务列表回车续写")
        editor.string = "9. 项目"; editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0)); editor.insertNewline(nil)
        check(editor.string == "9. 项目\n10. ", "有序列表递增")
        editor.string = "- "; editor.setSelectedRange(NSRange(location: 2, length: 0)); editor.insertNewline(nil)
        check(editor.string == "\n", "空列表回车退出")
        editor.string = "中文😀"; editor.setSelectedRange(NSRange(location: 0, length: 4)); editor.wrap("**", "**")
        check(editor.string == "**中文😀**" && editor.selectedRange().length == 4, "格式操作使用正确 UTF-16 选区")
        editor.undoManager?.undo(); check(editor.string == "中文😀", "格式操作可撤销")
        print("全部自检通过")
    }

    static func runScrollTests() {
        _ = NSApplication.shared
        func waitFor(_ condition: () -> Bool) -> Bool {
            let deadline = Date().addingTimeInterval(15)
            while !condition(), Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
            return condition()
        }
        func check(_ condition: Bool, _ message: String) {
            guard condition else { fputs("FAIL: \(message)\n", stderr); exit(1) }
            print("PASS: \(message)")
        }
        let document = MarkdownDocument()
        document.text = (1...100).map { "## 第 \($0) 节\n\n正文内容与行内公式 $x^2$。\n" }.joined(separator: "\n")
        let controller = EditorWindowController(document: document)
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        check(waitFor { controller.ready }, "离线公式排版完成后双栏就绪")
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        func evaluate(_ script: String) -> Double? {
            var done = false; var value: Double?
            controller.preview.evaluateJavaScript(script) { result, _ in value = result as? Double; done = true }
            _ = waitFor { done }; return value
        }
        func editorRatio() -> Double {
            ScrollSync.ratio(offset: Double(controller.editorScroll.contentView.bounds.minY), extent: Double(controller.editorScrollExtent))
        }
        let ratioScript = "window.scrollY/Math.max(1,document.documentElement.scrollHeight-innerHeight)"
        // Use ordinary scrolling, not setScrollRatio: it represents user-driven preview movement.
        _ = evaluate("window.scrollTo(0,0.5*(document.documentElement.scrollHeight-innerHeight)); 0")
        let previewSynced = waitFor { abs(editorRatio() - 0.5) < 0.015 }
        check(previewSynced, "右侧滚动带动左侧编辑区")
        let clip = controller.editorScroll.contentView
        clip.scroll(to: NSPoint(x: 0, y: 0.8 * controller.editorScrollExtent))
        controller.editorScroll.reflectScrolledClipView(clip)
        check(waitFor { abs((evaluate(ratioScript) ?? -1) - 0.8) < 0.015 }, "左侧滚动带动右侧预览")
        _ = evaluate("window.scrollTo(0,document.documentElement.scrollHeight); 0")
        let bottomSynced = waitFor { abs(editorRatio() - 1) < 0.015 }
        if !bottomSynced { print("底部诊断：\(editorRatio()) offset=\(clip.bounds.minY) extent=\(controller.editorScrollExtent) frame=\(controller.editor.frame.height) preview=\(evaluate(ratioScript) ?? -1)") }
        check(bottomSynced, "预览滚动到底部时编辑区同步到底部")
        controller.syncScroll = false
        _ = evaluate("window.scrollTo(0,0); 0")
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        check(abs(editorRatio() - 1) < 0.015, "关闭同步后两栏独立滚动")
        controller.syncScroll = true
        _ = evaluate("window.scrollTo(0,0.25*(document.documentElement.scrollHeight-innerHeight)); 0")
        check(waitFor { abs(editorRatio() - 0.25) < 0.015 }, "重新开启同步后恢复双向滚动")
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        check(abs(editorRatio() - 0.25) < 0.015 && abs((evaluate(ratioScript) ?? -1) - 0.25) < 0.015, "两栏同步后位置稳定，无循环反馈")
        controller.window?.orderOut(nil)
        print("全部双栏滚动集成检查通过")
    }
}
