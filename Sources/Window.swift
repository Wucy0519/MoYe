import AppKit
import WebKit
import UniformTypeIdentifiers

final class EditorWindowController: NSWindowController, NSTextViewDelegate, NSTableViewDataSource, NSTableViewDelegate, WKNavigationDelegate {
    weak var markdownDocument: MarkdownDocument?
    let editor = MarkdownTextView()
    let editorScroll = NSScrollView()
    let imageHandler = LocalImageHandler()
    var preview: WKWebView!
    let split = NSSplitView()
    let sidebar = NSStackView()
    let sidebarTabs = NSSegmentedControl(labels: ["大纲", "文件"], trackingMode: .selectOne, target: nil, action: nil)
    let table = NSTableView()
    let status = NSTextField(labelWithString: "")
    let folderLabel = NSTextField(labelWithString: "当前文档大纲")
    let modeControl = NSSegmentedControl(labels: ["编辑", "双栏", "阅读"], trackingMode: .selectOne, target: nil, action: nil)
    var headings: [Heading] = []
    var files: [URL] = []
    var folder: URL?
    var pending: DispatchWorkItem?
    var rendered = RenderedMarkdown(body: "", headings: [])
    var restoringScroll: Double = 0
    var rendering = false
    var ready = false
    var syncScroll = true
    let previewScrollHandler = PreviewScrollHandler()
    var applyingPreviewScroll = false
    var previewDrivenEditorY: CGFloat?
    var mode = 1
    var lastText = ""
    var renderRevision = 0
    let renderQueue = DispatchQueue(label: "com.wcy.moye.render", qos: .userInitiated)
    let selectionPopover = NSPopover()
    var selectionTask: DispatchWorkItem?
    var formatSelection = NSRange(location: 0, length: 0)
    var applyingSelectionFormat = false
    let headingPicker = NSPopUpButton()
    let pdfButton = NSButton()
    let marginPicker = NSPopUpButton()
    var formulaButton: SelectionMenuButton?

    init(document: MarkdownDocument) {
        markdownDocument = document
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1220, height: 820), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "墨页"; window.titlebarAppearsTransparent = true; window.minSize = NSSize(width: 760, height: 500)
        window.setFrameAutosaveName("MoYeEditorWindow"); window.center()
        super.init(window: window)
        buildUI(); applyTheme(); reloadText()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func button(_ title: String, _ action: Selector, symbol: String? = nil) -> NSButton {
        let result = NSButton(title: title, target: self, action: action)
        result.bezelStyle = .rounded
        if let symbol { result.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title); result.imagePosition = .imageLeading }
        return result
    }
    func buildUI() {
        guard let content = window?.contentView else { return }
        let root = NSStackView(); root.orientation = .vertical; root.spacing = 0; root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([root.leadingAnchor.constraint(equalTo: content.leadingAnchor), root.trailingAnchor.constraint(equalTo: content.trailingAnchor), root.topAnchor.constraint(equalTo: content.safeAreaLayoutGuide.topAnchor), root.bottomAnchor.constraint(equalTo: content.bottomAnchor)])
        let bar = NSStackView(); bar.spacing = 8; bar.edgeInsets = NSEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
        bar.addArrangedSubview(button("侧栏", #selector(toggleSidebar), symbol: "sidebar.left"))
        bar.addArrangedSubview(button("打开", #selector(openFile), symbol: "folder"))
        bar.addArrangedSubview(button("保存", #selector(saveFile), symbol: "square.and.arrow.down"))
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal); bar.addArrangedSubview(spacer)
        modeControl.target = self; modeControl.action = #selector(modeSelected); modeControl.selectedSegment = 1
        bar.addArrangedSubview(modeControl)
        bar.addArrangedSubview(button("外观", #selector(cycleTheme), symbol: "circle.lefthalf.filled"))
        root.addArrangedSubview(bar)
        split.isVertical = true; split.dividerStyle = .thin; split.autoresizingMask = [.width, .height]
        split.setContentHuggingPriority(.defaultLow, for: .vertical)
        root.addArrangedSubview(split)
        sidebar.orientation = .vertical; sidebar.spacing = 12; sidebar.alignment = .leading; sidebar.edgeInsets = NSEdgeInsets(top: 20, left: 14, bottom: 14, right: 14)
        let brand = NSTextField(labelWithString: "墨页  /  MOYE"); brand.font = .systemFont(ofSize: 13, weight: .semibold); brand.textColor = .secondaryLabelColor
        sidebar.addArrangedSubview(brand)
        sidebarTabs.target = self; sidebarTabs.action = #selector(sidebarTabChanged); sidebarTabs.selectedSegment = 0
        sidebar.addArrangedSubview(sidebarTabs)
        folderLabel.font = .systemFont(ofSize: 11); folderLabel.textColor = .secondaryLabelColor; folderLabel.lineBreakMode = .byTruncatingMiddle
        sidebar.addArrangedSubview(folderLabel)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title")); column.width = 205
        table.addTableColumn(column); table.headerView = nil; table.rowHeight = 34; table.dataSource = self; table.delegate = self
        table.backgroundColor = .clear; table.style = .sourceList; table.target = self; table.action = #selector(selectRow)
        let tableScroll = NSScrollView(); tableScroll.documentView = table; tableScroll.hasVerticalScroller = true; tableScroll.drawsBackground = false
        sidebar.addArrangedSubview(tableScroll)
        sidebar.addArrangedSubview(button("选择文件夹…", #selector(chooseFolder), symbol: "folder.badge.plus"))
        let exportLabel = NSTextField(labelWithString: "导出文档")
        exportLabel.font = .systemFont(ofSize: 11, weight: .medium); exportLabel.textColor = .secondaryLabelColor
        sidebar.addArrangedSubview(exportLabel)
        let marginLabel = NSTextField(labelWithString: "PDF 页边距")
        marginLabel.font = .systemFont(ofSize: 11); marginLabel.textColor = .secondaryLabelColor
        sidebar.addArrangedSubview(marginLabel)
        PDFMargin.allCases.forEach { marginPicker.addItem(withTitle: $0.title) }
        marginPicker.selectItem(at: UserDefaults.standard.integer(forKey: "pdfMargin"))
        marginPicker.target = self; marginPicker.action = #selector(marginChanged)
        sidebar.addArrangedSubview(marginPicker)
        pdfButton.title = "打印 / 导出 PDF…"; pdfButton.target = self; pdfButton.action = #selector(exportPDF(_:))
        pdfButton.bezelStyle = .rounded; pdfButton.image = NSImage(systemSymbolName: "doc.richtext", accessibilityDescription: "PDF")
        pdfButton.imagePosition = .imageLeading; pdfButton.isEnabled = false
        sidebar.addArrangedSubview(pdfButton)
        sidebar.addArrangedSubview(button("导出 HTML…", #selector(exportHTML(_:)), symbol: "chevron.left.forwardslash.chevron.right"))
        split.addArrangedSubview(sidebar)
        sidebar.widthAnchor.constraint(equalToConstant: 230).isActive = true
        tableScroll.widthAnchor.constraint(equalTo: sidebar.widthAnchor, constant: -28).isActive = true
        sidebarTabs.widthAnchor.constraint(equalTo: tableScroll.widthAnchor).isActive = true
        folderLabel.widthAnchor.constraint(equalTo: tableScroll.widthAnchor).isActive = true
        editor.isRichText = false; editor.isAutomaticQuoteSubstitutionEnabled = false; editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false; editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isGrammarCheckingEnabled = false; editor.isContinuousSpellCheckingEnabled = false
        editor.allowsUndo = true; editor.usesFindBar = true; editor.isIncrementalSearchingEnabled = true
        editor.delegate = self; editor.textContainerInset = NSSize(width: 26, height: 30)
        editor.onSelectionFinished = { [weak self] in self?.scheduleSelectionOptions() }
        configureSelectionOptions()
        editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false
        editor.minSize = NSSize(width: 0, height: 0); editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.autoresizingMask = [.width]; editor.textContainer?.widthTracksTextView = true
        editorScroll.hasVerticalScroller = true; editorScroll.autohidesScrollers = true; editorScroll.documentView = editor
        editorScroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(editorScrolled), name: NSView.boundsDidChangeNotification, object: editorScroll.contentView)
        split.addArrangedSubview(editorScroll)
        let config = WKWebViewConfiguration(); config.setURLSchemeHandler(imageHandler, forURLScheme: "moye-resource")
        previewScrollHandler.owner = self
        config.userContentController.add(previewScrollHandler, name: "moyeScroll")
        preview = WKWebView(frame: .zero, configuration: config); preview.navigationDelegate = self
        split.addArrangedSubview(preview)
        status.font = .monospacedSystemFont(ofSize: 11, weight: .regular); status.textColor = .secondaryLabelColor
        let footer = NSStackView(views: [status]); footer.edgeInsets = NSEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        root.addArrangedSubview(footer)
        for view in [bar, split, footer] { view.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.split.setPosition(230, ofDividerAt: 0)
            self.split.setPosition(230 + max(250, (self.split.bounds.width - 230) / 2), ofDividerAt: 1)
            self.window?.makeFirstResponder(self.editor)
        }
    }
    deinit { NotificationCenter.default.removeObserver(self); pending?.cancel(); selectionTask?.cancel() }
    func reloadText() {
        editor.string = markdownDocument?.text ?? ""; lastText = editor.string
        editor.highlight(); requestRender(immediate: true); updateStatus()
    }
    func fileLocationChanged() { imageHandler.root = markdownDocument?.fileURL?.deletingLastPathComponent(); requestRender(immediate: true) }
    func textDidChange(_ notification: Notification) {
        guard editor.string != lastText else { return }
        lastText = editor.string; markdownDocument?.text = editor.string; markdownDocument?.updateChangeCount(.changeDone)
        requestRender(); updateStatus()
    }
    func textViewDidChangeSelection(_ notification: Notification) { updateStatus(); scheduleSelectionOptions() }
    func configureSelectionOptions() {
        selectionPopover.behavior = .semitransient; selectionPopover.animates = false
        let controller = NSViewController()
        let box = NSStackView(); box.orientation = .vertical; box.spacing = 2; box.alignment = .leading
        box.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        func row(_ title: String, _ symbol: String, _ action: Selector) {
            let row = SelectionMenuButton(title: title, symbol: symbol, target: self, action: action)
            box.addArrangedSubview(row); row.widthAnchor.constraint(equalToConstant: 224).isActive = true
        }
        let convert = SelectionMenuButton(title: "转换公式", symbol: "function", target: self, action: #selector(selectionConvertFormula))
        convert.widthAnchor.constraint(equalToConstant: 224).isActive = true
        formulaButton = convert; box.addArrangedSubview(convert); convert.isHidden = true
        row("加粗", "bold", #selector(selectionBold))
        row("常规字重", "textformat", #selector(selectionRegular))
        row("斜体", "italic", #selector(selectionItalic))
        headingPicker.addItem(withTitle: "变为标题…")
        for level in 1...6 { headingPicker.addItem(withTitle: "\(level) 级标题"); headingPicker.lastItem?.tag = level }
        headingPicker.addItem(withTitle: "恢复正文"); headingPicker.lastItem?.tag = 0
        headingPicker.target = self; headingPicker.action = #selector(selectionHeading)
        box.addArrangedSubview(headingPicker)
        headingPicker.widthAnchor.constraint(equalToConstant: 224).isActive = true
        let separator = NSBox(); separator.boxType = .separator; box.addArrangedSubview(separator)
        separator.widthAnchor.constraint(equalToConstant: 224).isActive = true
        row("代码块", "curlybraces", #selector(selectionInsertCode))
        row("本地图片…", "photo", #selector(selectionInsertImage))
        row("链接", "link", #selector(selectionInsertLink))
        row("表格", "tablecells", #selector(selectionInsertTable))
        row("无序列表", "list.bullet", #selector(selectionInsertList))
        row("有序列表", "list.number", #selector(selectionInsertOrderedList))
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 412))
        box.translatesAutoresizingMaskIntoConstraints = false; container.addSubview(box)
        NSLayoutConstraint.activate([box.leadingAnchor.constraint(equalTo: container.leadingAnchor), box.trailingAnchor.constraint(equalTo: container.trailingAnchor), box.topAnchor.constraint(equalTo: container.topAnchor), box.bottomAnchor.constraint(equalTo: container.bottomAnchor)])
        controller.view = container; selectionPopover.contentViewController = controller
        selectionPopover.contentSize = NSSize(width: 260, height: 412)
    }
    func scheduleSelectionOptions() {
        selectionTask?.cancel()
        guard !applyingSelectionFormat else { return }
        guard editor.selectedRange().length > 0, mode != 2, !editor.hasMarkedText() else { selectionPopover.close(); return }
        let task = DispatchWorkItem { [weak self] in self?.showSelectionOptions() }
        selectionTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: task)
    }
    func showSelectionOptions() {
        guard let window, window.isKeyWindow, window.firstResponder === editor,
              NSEvent.pressedMouseButtons == 0, !editor.hasMarkedText(), editor.selectedRange().length > 0, mode != 2 else { return }
        formatSelection = editor.selectedRange()
        let selected = (editor.string as NSString).substring(with: formatSelection)
        let hasFormula = LaTeX.markdownFormula(selected) != nil
        formulaButton?.isHidden = !hasFormula
        selectionPopover.contentSize = NSSize(width: 260, height: hasFormula ? 448 : 412)
        var actual = NSRange()
        let rect = editor.firstRect(forCharacterRange: NSRange(location: formatSelection.location, length: 1), actualRange: &actual)
        let local = editor.convert(window.convertFromScreen(rect), from: nil)
        guard local.intersects(editor.visibleRect) else { selectionPopover.close(); return }
        headingPicker.selectItem(at: 0)
        if selectionPopover.isShown { selectionPopover.close() }
        selectionPopover.show(relativeTo: local, of: editor, preferredEdge: .maxX)
    }
    func performSelectionFormat(_ action: () -> Void) {
        applyingSelectionFormat = true; selectionTask?.cancel(); selectionPopover.close()
        window?.makeFirstResponder(editor)
        editor.setSelectedRange(formatSelection); action()
        applyingSelectionFormat = false
    }
    @objc func selectionBold() { performSelectionFormat { editor.toggleEmphasis("**") } }
    @objc func selectionConvertFormula() {
        guard let converted = LaTeX.markdownFormula((editor.string as NSString).substring(with: formatSelection)) else { return }
        performSelectionFormat {
            editor.apply(TextEdit(range: formatSelection, replacement: converted, selection: NSRange(location: formatSelection.location, length: converted.utf16.count)))
        }
    }
    @objc func selectionRegular() { performSelectionFormat { editor.regularWeight() } }
    @objc func selectionItalic() { performSelectionFormat { editor.toggleEmphasis("*") } }
    @objc func selectionHeading() {
        guard headingPicker.indexOfSelectedItem > 0, let item = headingPicker.selectedItem else { return }
        performSelectionFormat { editor.setHeading(item.tag) }
    }
    func insertAfterSelection(_ text: String) {
        performSelectionFormat {
            editor.setSelectedRange(NSRange(location: NSMaxRange(formatSelection), length: 0))
            editor.insertText(text, replacementRange: editor.selectedRange())
        }
    }
    @objc func selectionInsertCode() { insertAfterSelection("\n\n```\n代码\n```\n\n") }
    @objc func selectionInsertLink() { insertAfterSelection(" [链接文字](https://example.com)") }
    @objc func selectionInsertTable() { insertAfterSelection("\n\n| 列一 | 列二 |\n| --- | --- |\n| 内容 | 内容 |\n\n") }
    @objc func selectionInsertList() { insertAfterSelection("\n\n- 列表项\n- 列表项\n\n") }
    @objc func selectionInsertOrderedList() { insertAfterSelection("\n\n1. 列表项\n2. 列表项\n\n") }
    @objc func selectionInsertImage() {
        performSelectionFormat {
            editor.setSelectedRange(NSRange(location: NSMaxRange(formatSelection), length: 0))
            insertImage(nil)
        }
    }
    func updateStatus() {
        let ns = editor.string as NSString
        let location = min(editor.selectedRange().location, ns.length)
        let line = ns.substring(to: location).filter { $0 == "\n" }.count + 1
        let chars = editor.string.filter { !$0.isWhitespace }.count
        let encoding = markdownDocument?.sourceEncoding == .utf16 ? "UTF-16" : "UTF-8"
        let ending = markdownDocument?.lineEnding == "\r\n" ? "CRLF" : "LF"
        status.stringValue = "\(chars) 字符   ·   \(ns.length == 0 ? 0 : editor.string.filter { $0 == "\n" }.count + 1) 行   ·   第 \(line) 行   ·   \(encoding) / \(ending)   ·   \(markdownDocument?.isDocumentEdited == true ? "修改待保存" : "已保存")"
    }
    func requestRender(immediate: Bool = false) {
        pending?.cancel(); renderRevision += 1
        let revision = renderRevision
        let text = editor.string
        let task = DispatchWorkItem { [weak self] in
            let result = Markdown.render(text)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.renderRevision == revision else { return }
                self.editor.highlight(); self.rendered = result; self.headings = result.headings
                if self.sidebarTabs.selectedSegment == 0 { self.table.reloadData() }
                self.loadPreview()
            }
        }
        pending = task
        renderQueue.asyncAfter(deadline: .now() + (immediate ? 0 : 0.22), execute: task)
    }
    func loadPreview() {
        imageHandler.root = markdownDocument?.fileURL?.deletingLastPathComponent()
        let title = markdownDocument?.displayName ?? "未命名"
        let html = Markdown.page(rendered, title: title, base: "moye-resource://document/", interactive: true)
        if ready {
            preview.evaluateJavaScript("window.scrollY / Math.max(1, document.documentElement.scrollHeight-innerHeight)") { [weak self] value, _ in
                guard let self else { return }
                self.restoringScroll = value as? Double ?? 0; self.ready = false; self.rendering = true; self.pdfButton.isEnabled = false
                self.preview.loadHTMLString(html, baseURL: URL(string: "moye-resource://document/"))
            }
        } else { rendering = true; pdfButton.isEnabled = false; preview.loadHTMLString(html, baseURL: URL(string: "moye-resource://document/")) }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let revision = renderRevision
        webView.callAsyncJavaScript("await window.moyeMathReady; return true;", arguments: [:], in: nil, in: .page, completionHandler: { [weak self] result in
            guard let self, self.renderRevision == revision else { return }
            switch result {
            case .success:
                self.rendering = false; self.ready = true; self.pdfButton.isEnabled = true
                webView.evaluateJavaScript("setScrollRatio(\(self.restoringScroll))")
                self.updateStatus()
            case .failure(let error):
                self.rendering = false; self.ready = false; self.pdfButton.isEnabled = false
                self.status.stringValue = "公式渲染失败：\(error.localizedDescription)"
            }
        })
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url else { decisionHandler(.allow); return }
        if url.scheme == "moye-resource" {
            if let fragment = url.fragment, url.path == "/" { webView.evaluateJavaScript("document.getElementById(\(jsString(fragment)))?.scrollIntoView()") }
            else if let root = imageHandler.root {
                let file = root.appendingPathComponent(String(URLComponents(url: url, resolvingAgainstBaseURL: false)?.path.dropFirst() ?? ""))
                if ["md", "markdown", "txt", "mdown", "mkd"].contains(file.pathExtension.lowercased()) { openDocument(file) }
            }
        } else if ["https", "http", "mailto"].contains(url.scheme ?? "") { NSWorkspace.shared.open(url) }
        decisionHandler(.cancel)
    }
    func jsString(_ value: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: [value]); let array = String(data: data, encoding: .utf8)!
        return String(array.dropFirst().dropLast())
    }
    var editorScrollExtent: CGFloat {
        if let container = editor.textContainer { editor.layoutManager?.ensureLayout(for: container) }
        let clip = editorScroll.contentView
        var bottom = clip.bounds
        bottom.origin.y = max(0, editor.bounds.maxY)
        return max(0, clip.constrainBoundsRect(bottom).origin.y)
    }
    @objc func editorScrolled() {
        selectionPopover.close()
        guard syncScroll, mode == 1, ready, !applyingPreviewScroll else { return }
        let offset = editorScroll.contentView.bounds.minY
        if let target = previewDrivenEditorY, abs(offset - target) < 1 { return }
        previewDrivenEditorY = nil
        let height = editorScrollExtent
        let ratio = ScrollSync.ratio(offset: Double(offset), extent: Double(height))
        restoringScroll = ratio; preview.evaluateJavaScript("setScrollRatio(\(ratio))")
    }
    func previewScrolled(ratio: Double) {
        guard syncScroll, mode == 1, ready, !rendering else { return }
        selectionTask?.cancel(); selectionPopover.close()
        let ratio = max(0, min(1, ratio))
        restoringScroll = ratio
        let clip = editorScroll.contentView
        let height = editorScrollExtent
        applyingPreviewScroll = true
        clip.scroll(to: NSPoint(x: clip.bounds.minX, y: CGFloat(ratio) * height))
        editorScroll.reflectScrolledClipView(clip)
        previewDrivenEditorY = clip.bounds.minY
        applyingPreviewScroll = false
    }
    @objc func modeSelected() { mode = modeControl.selectedSegment; applyMode() }
    func applyMode() {
        previewDrivenEditorY = nil
        selectionPopover.close(); selectionTask?.cancel()
        editorScroll.isHidden = mode == 2; preview.isHidden = mode == 0
        split.adjustSubviews(); if mode != 2 { window?.makeFirstResponder(editor) }
    }
    @objc func editMode(_ sender: Any?) { mode = 0; modeControl.selectedSegment = 0; applyMode() }
    @objc func splitMode(_ sender: Any?) { mode = 1; modeControl.selectedSegment = 1; applyMode() }
    @objc func readMode(_ sender: Any?) { mode = 2; modeControl.selectedSegment = 2; applyMode() }
    @objc func toggleSidebar() { sidebar.isHidden.toggle(); split.adjustSubviews() }
    @objc func toggleScrollSync(_ sender: NSMenuItem) { syncScroll.toggle(); previewDrivenEditorY = nil; sender.state = syncScroll ? .on : .off }
    @objc func openFile() { NSDocumentController.shared.openDocument(nil) }
    @objc func saveFile() { markdownDocument?.save(nil) }
    @objc func sidebarTabChanged() { folderLabel.stringValue = sidebarTabs.selectedSegment == 0 ? "当前文档大纲" : (folder?.lastPathComponent ?? "请选择 Markdown 文件夹"); table.reloadData() }
    @objc func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.prompt = "打开文件夹"
        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            self.folder = url; self.refreshFiles(); self.sidebarTabs.selectedSegment = 1; self.sidebarTabChanged()
        }
    }
    @objc func refreshFiles() {
        guard let folder else { return }
        let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants])
        var found: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            if ["md", "markdown", "mdown", "mkd", "txt"].contains(url.pathExtension.lowercased()), (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { found.append(url) }
            if found.count >= 10000 { break }
        }
        files = found.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }; table.reloadData()
    }
    func numberOfRows(in tableView: NSTableView) -> Int { sidebarTabs.selectedSegment == 0 ? headings.count : files.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let label = NSTextField(labelWithString: ""); label.font = .systemFont(ofSize: 12); label.lineBreakMode = .byTruncatingMiddle
        if sidebarTabs.selectedSegment == 0 {
            guard row < headings.count else { return label }
            let heading = headings[row]; label.stringValue = String(repeating: "  ", count: max(0, heading.level - 1)) + heading.title
            label.toolTip = heading.title
        } else {
            guard row < files.count else { return label }
            label.stringValue = String(files[row].path.dropFirst((folder?.path.count ?? 0) + 1)); label.toolTip = files[row].path
        }
        return label
    }
    @objc func selectRow() {
        let row = table.selectedRow; guard row >= 0 else { return }
        if sidebarTabs.selectedSegment == 0 {
            guard row < headings.count else { return }
            let ns = editor.string as NSString; var offset = 0
            for _ in 1..<max(1, headings[row].line) { let range = ns.lineRange(for: NSRange(location: offset, length: 0)); offset = min(ns.length, NSMaxRange(range)) }
            editor.setSelectedRange(NSRange(location: offset, length: 0)); editor.scrollRangeToVisible(editor.selectedRange())
            if ready { preview.evaluateJavaScript("scrollToHeading(\(row))") }
        } else if row < files.count { openDocument(files[row]) }
    }
    func openDocument(_ url: URL) {
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in if let error { NSApp.presentError(error) } }
    }
    @objc func cycleTheme() {
        let value = UserDefaults.standard.integer(forKey: "theme"); UserDefaults.standard.set((value + 1) % 3, forKey: "theme")
        for document in NSDocumentController.shared.documents { for controller in document.windowControllers { (controller as? EditorWindowController)?.applyTheme() } }
    }
    func applyTheme() {
        switch UserDefaults.standard.integer(forKey: "theme") { case 1: window?.appearance = NSAppearance(named: .aqua); case 2: window?.appearance = NSAppearance(named: .darkAqua); default: window?.appearance = nil }
        editor.backgroundColor = .textBackgroundColor; editor.insertionPointColor = .labelColor; editor.highlight()
    }
    func editable() { if mode == 2 { editMode(nil) }; window?.makeFirstResponder(editor) }
    @objc func bold(_ sender: Any?) { editable(); editor.toggleEmphasis("**") }
    @objc func italic(_ sender: Any?) { editable(); editor.toggleEmphasis("*") }
    @objc func inlineCode(_ sender: Any?) { editable(); editor.wrap("`", "`", placeholder: "code") }
    @objc func strike(_ sender: Any?) { editable(); editor.wrap("~~", "~~") }
    @objc func heading(_ sender: NSMenuItem) { editable(); editor.setHeading(sender.tag) }
    @objc func quote(_ sender: Any?) { editable(); editor.prefix("> ") }
    @objc func list(_ sender: Any?) { editable(); editor.prefix("- ") }
    @objc func taskList(_ sender: Any?) { editable(); editor.prefix("- [ ] ") }
    @objc func codeBlock(_ sender: Any?) { editable(); editor.wrap("\n```\n", "\n```\n", placeholder: "code") }
    @objc func insertTable(_ sender: Any?) { editable(); editor.insertText("\n| 列一 | 列二 |\n| --- | --- |\n| 内容 | 内容 |\n", replacementRange: editor.selectedRange()) }
    @objc func insertLink(_ sender: Any?) { editable(); editor.wrap("[", "](https://example.com)", placeholder: "链接文字") }
    @objc func insertImage(_ sender: Any?) {
        editable()
        let insertionRange = editor.selectedRange()
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]
        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            guard let documentURL = self.markdownDocument?.fileURL else {
                let alert = NSAlert(); alert.messageText = "请先保存文档"; alert.informativeText = "保存后可以将图片复制到文档旁的 assets 文件夹，让文档和图片一起移动。"; alert.beginSheetModal(for: self.window!); return
            }
            do {
                let directory = documentURL.deletingLastPathComponent().appendingPathComponent("assets", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let destination = directory.appendingPathComponent(UUID().uuidString.prefix(8) + "-" + url.lastPathComponent)
                try FileManager.default.copyItem(at: url, to: destination)
                let relative = "assets/" + destination.lastPathComponent
                let encoded = relative.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "()#?"))) ?? relative
                self.editor.insertText("![图片](\(encoded))", replacementRange: insertionRange)
            } catch { NSApp.presentError(error) }
        }
    }
    @objc func find(_ sender: NSMenuItem) { editable(); let item = NSMenuItem(); item.tag = sender.tag; editor.performFindPanelAction(item) }
    @objc func fontLarger(_ sender: Any?) { setFontSize(1) }
    @objc func fontSmaller(_ sender: Any?) { setFontSize(-1) }
    func setFontSize(_ delta: Double) {
        let size = UserDefaults.standard.double(forKey: "editorFontSize").nonzeroOr(15)
        UserDefaults.standard.set(max(11, min(28, size + delta)), forKey: "editorFontSize"); editor.highlight()
    }
    @objc func saveUTF8(_ sender: Any?) {
        guard let document = markdownDocument else { return }
        let previous = document.sourceEncoding; document.sourceEncoding = .utf8
        document.saveAs(sender)
        // Save As may be cancelled; keeping UTF-8 is an explicit user choice and never alters the source file until a save.
        if previous != .utf8 { updateStatus() }
    }
    @objc func exportHTML(_ sender: Any?) {
        guard ready else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.html]; panel.nameFieldStringValue = (markdownDocument?.fileURL?.deletingPathExtension().lastPathComponent ?? "未命名") + ".html"
        panel.beginSheetModal(for: window!) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            self.preview.callAsyncJavaScript("await window.moyeMathReady; return {body:document.querySelector('main').innerHTML,styles:Array.from(document.querySelectorAll('style[id^=MJX]')).map(s=>s.outerHTML).join('')};", arguments: [:], in: nil, in: .page, completionHandler: { result in
                do {
                    let data = try result.get() as? [String: Any]
                    guard let body = data?["body"] as? String else { throw NSError(domain: "MoYe", code: 5, userInfo: [NSLocalizedDescriptionKey: "无法取得导出内容。"] ) }
                    let rendered = RenderedMarkdown(body: body, headings: [])
                    let base = self.markdownDocument?.fileURL?.deletingLastPathComponent().absoluteString
                    try Markdown.page(rendered, title: self.markdownDocument?.displayName ?? "未命名", base: base, typeset: false, mathStyles: data?["styles"] as? String ?? "").write(to: url, atomically: true, encoding: .utf8)
                } catch { NSApp.presentError(error) }
            })
        }
    }
    @objc func exportPDF(_ sender: Any?) {
        guard ready else { return }
        selectionPopover.close()
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        let margin = PDFMargin(rawValue: marginPicker.indexOfSelectedItem) ?? .normal
        info.topMargin = margin.points; info.bottomMargin = margin.points
        info.leftMargin = margin.points; info.rightMargin = margin.points
        info.isHorizontallyCentered = false; info.isVerticallyCentered = false
        let operation = preview.printOperation(with: info); operation.showsPrintPanel = true; operation.showsProgressPanel = true
        operation.runModal(for: window!, delegate: nil, didRun: nil, contextInfo: nil)
    }
    @objc func marginChanged() { UserDefaults.standard.set(marginPicker.indexOfSelectedItem, forKey: "pdfMargin") }
}
