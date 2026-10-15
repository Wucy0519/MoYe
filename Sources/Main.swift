import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var documentController: MarkdownDocumentController!
    func applicationWillFinishLaunching(_ notification: Notification) {
        documentController = MarkdownDocumentController()
        NSDocumentController.shared.autosavingDelay = 10
        buildMenus()
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        DispatchQueue.main.async { DefaultApp.offer(firstLaunch: true) }
    }
    @objc func chooseDefaultApplication(_ sender: Any?) { DefaultApp.offer(firstLaunch: false) }
    @objc func openMarkdownService(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        let markdown = urls.filter { ["md", "markdown", "mdown", "mkd", "mmd"].contains($0.pathExtension.lowercased()) }
        guard !markdown.isEmpty else { error.pointee = "请选择 Markdown 文件。"; return }
        for url in markdown {
            documentController.openDocument(withContentsOf: url, display: true) { _, _, problem in if let problem { NSApp.presentError(problem) } }
        }
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        for path in filenames {
            documentController.openDocument(withContentsOf: URL(fileURLWithPath: path), display: true) { _, _, error in if let error { NSApp.presentError(error) } }
        }
        sender.reply(toOpenOrPrint: .success)
    }
    func buildMenus() {
        let menu = NSMenu(); NSApp.mainMenu = menu
        func section(_ name: String) -> NSMenu {
            let item = NSMenuItem(title: name, action: nil, keyEquivalent: "")
            let sub = NSMenu(title: name); item.submenu = sub; menu.addItem(item); return sub
        }
        func add(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = .command, tag: Int = 0, target: AnyObject? = nil) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers; item.tag = tag; item.target = target; menu.addItem(item)
        }
        let app = section("墨页")
        add(app, "关于墨页", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), target: NSApp)
        add(app, "默认打开 Markdown 文件…", #selector(chooseDefaultApplication(_:)), target: self)
        app.addItem(.separator())
        add(app, "隐藏墨页", #selector(NSApplication.hide(_:)), "h", target: NSApp)
        add(app, "隐藏其他", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option], target: NSApp)
        add(app, "显示全部", #selector(NSApplication.unhideAllApplications(_:)), target: NSApp)
        app.addItem(.separator()); add(app, "退出墨页", #selector(NSApplication.terminate(_:)), "q", target: NSApp)
        let file = section("文件")
        add(file, "新建", #selector(NSDocumentController.newDocument(_:)), "n", target: documentController)
        add(file, "打开…", #selector(NSDocumentController.openDocument(_:)), "o", target: documentController)
        add(file, "打开文件夹…", #selector(EditorWindowController.chooseFolder))
        let recentItem = NSMenuItem(title: "最近打开", action: nil, keyEquivalent: ""); let recent = NSMenu(title: "最近打开")
        recent.perform(NSSelectorFromString("_setMenuName:"), with: "NSRecentDocumentsMenu")
        add(recent, "清除菜单", #selector(NSDocumentController.clearRecentDocuments(_:)), target: documentController)
        recentItem.submenu = recent; file.addItem(recentItem)
        file.addItem(.separator())
        add(file, "关闭", #selector(NSWindow.performClose(_:)), "w")
        add(file, "保存", #selector(NSDocument.save(_:)), "s")
        add(file, "另存为…", #selector(NSDocument.saveAs(_:)), "s", [.command, .shift])
        add(file, "以 UTF-8 另存为…", #selector(EditorWindowController.saveUTF8(_:)))
        add(file, "恢复到上次保存…", #selector(NSDocument.revertToSaved(_:)))
        file.addItem(.separator()); add(file, "导出 HTML…", #selector(EditorWindowController.exportHTML(_:)))
        add(file, "打印 / 导出 PDF…", #selector(EditorWindowController.exportPDF(_:)), "p")
        let edit = section("编辑")
        add(edit, "撤销", NSSelectorFromString("undo:"), "z")
        add(edit, "重做", NSSelectorFromString("redo:"), "z", [.command, .shift])
        edit.addItem(.separator())
        add(edit, "剪切", #selector(NSText.cut(_:)), "x"); add(edit, "复制", #selector(NSText.copy(_:)), "c")
        add(edit, "粘贴", #selector(NSText.paste(_:)), "v"); add(edit, "全选", #selector(NSText.selectAll(_:)), "a")
        edit.addItem(.separator())
        add(edit, "查找…", #selector(EditorWindowController.find(_:)), "f", tag: NSTextFinder.Action.showFindInterface.rawValue)
        add(edit, "查找并替换…", #selector(EditorWindowController.find(_:)), "f", [.command, .option], tag: NSTextFinder.Action.showReplaceInterface.rawValue)
        add(edit, "查找下一个", #selector(EditorWindowController.find(_:)), "g", tag: NSTextFinder.Action.nextMatch.rawValue)
        let format = section("格式")
        add(format, "加粗", #selector(EditorWindowController.bold(_:)), "b"); add(format, "斜体", #selector(EditorWindowController.italic(_:)), "i")
        add(format, "行内代码", #selector(EditorWindowController.inlineCode(_:)), "e")
        add(format, "删除线", #selector(EditorWindowController.strike(_:)))
        format.addItem(.separator())
        for level in 1...6 { add(format, "\(level) 级标题", #selector(EditorWindowController.heading(_:)), "\(level)", [.command, .option], tag: level) }
        format.addItem(.separator())
        add(format, "引用", #selector(EditorWindowController.quote(_:))); add(format, "无序列表", #selector(EditorWindowController.list(_:)))
        add(format, "任务列表", #selector(EditorWindowController.taskList(_:))); add(format, "代码块", #selector(EditorWindowController.codeBlock(_:)))
        add(format, "表格", #selector(EditorWindowController.insertTable(_:)))
        add(format, "链接", #selector(EditorWindowController.insertLink(_:)), "k"); add(format, "插入本地图片…", #selector(EditorWindowController.insertImage(_:)))
        let view = section("视图")
        add(view, "编辑模式", #selector(EditorWindowController.editMode(_:)), "1", [.command, .control])
        add(view, "双栏预览", #selector(EditorWindowController.splitMode(_:)), "2", [.command, .control])
        add(view, "阅读模式", #selector(EditorWindowController.readMode(_:)), "3", [.command, .control])
        view.addItem(.separator()); add(view, "显示 / 隐藏侧栏", #selector(EditorWindowController.toggleSidebar), "\\")
        add(view, "双栏同步滚动", #selector(EditorWindowController.toggleScrollSync(_:))); view.items.last?.state = .on
        add(view, "刷新文件列表", #selector(EditorWindowController.refreshFiles))
        add(view, "切换外观（系统 / 浅色 / 深色）", #selector(EditorWindowController.cycleTheme))
        func scaleMenu(_ action: Selector) -> NSMenu {
            let menu = NSMenu()
            for percent in DisplayScale.percents {
                let item = NSMenuItem(title: "\(percent)%", action: action, keyEquivalent: "")
                item.tag = percent; menu.addItem(item)
            }
            return menu
        }
        let editorScale = NSMenuItem(title: "左栏显示比例", action: nil, keyEquivalent: "")
        editorScale.submenu = scaleMenu(#selector(EditorWindowController.setEditorDisplayScale(_:))); view.addItem(editorScale)
        let previewScale = NSMenuItem(title: "右栏显示比例", action: nil, keyEquivalent: "")
        previewScale.submenu = scaleMenu(#selector(EditorWindowController.setPreviewDisplayScale(_:))); view.addItem(previewScale)
        add(view, "增大左栏字号", #selector(EditorWindowController.fontLarger(_:)), "+")
        add(view, "减小左栏字号", #selector(EditorWindowController.fontSmaller(_:)), "-")
        add(view, "增大右栏字号", #selector(EditorWindowController.previewLarger(_:)), "+", [.command, .option])
        add(view, "减小右栏字号", #selector(EditorWindowController.previewSmaller(_:)), "-", [.command, .option])
        let windows = section("窗口"); NSApp.windowsMenu = windows
        add(windows, "最小化", #selector(NSWindow.performMiniaturize(_:)), "m")
        add(windows, "缩放", #selector(NSWindow.performZoom(_:)))
        add(windows, "全屏", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control])
    }
}

@main enum Main {
    static func main() {
        if CommandLine.arguments.contains("--self-test") { SelfTests.run(); return }
        let app = NSApplication.shared
        let delegate = AppDelegate(); app.delegate = delegate; app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}
