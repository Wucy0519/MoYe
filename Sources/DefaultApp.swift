import AppKit
import UniformTypeIdentifiers

enum DefaultApp {
    static func offer(firstLaunch: Bool) {
        if firstLaunch && UserDefaults.standard.bool(forKey: "defaultAppChoicePresented") { return }
        let alert = NSAlert()
        alert.messageText = "使用墨页默认打开 Markdown 文件？"
        alert.informativeText = "选择“设为默认”后，双击此账户下的 .md 文件将使用墨页打开。macOS 按 Markdown 文件类型设置，因此同类型的 .markdown 等文件也可能受影响。你可以随时在 Finder 的“显示简介 → 打开方式 → 全部更改”中改回其他应用。"
        alert.addButton(withTitle: "保留现有设置")
        alert.addButton(withTitle: "设为默认")
        let response = alert.runModal()
        UserDefaults.standard.set(true, forKey: "defaultAppChoicePresented")
        guard response == .alertSecondButtonReturn else { return }
        let type = UTType(filenameExtension: "md") ?? UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
        NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: type) { error in
            DispatchQueue.main.async {
                if let error { NSApp.presentError(error) }
                else {
                    let notice = NSAlert(); notice.messageText = "已将墨页设为 Markdown 默认打开应用"
                    notice.informativeText = "现在可在 Finder 中双击 .md 文件打开。"; notice.runModal()
                }
            }
        }
    }
}
