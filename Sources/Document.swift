import AppKit
import UniformTypeIdentifiers

final class MarkdownDocument: NSDocument {
    var text = ""
    var sourceEncoding = String.Encoding.utf8
    var lineEnding = "\n"
    override class var autosavesInPlace: Bool { true }
    override class var readableTypes: [String] { ["net.daringfireball.markdown", "public.plain-text"] }
    override class var writableTypes: [String] { readableTypes }
    override init() { super.init(); hasUndoManager = true }
    override func makeWindowControllers() {
        let controller = EditorWindowController(document: self)
        addWindowController(controller)
    }
    override func data(ofType typeName: String) throws -> Data {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        guard let data = normalized.replacingOccurrences(of: "\n", with: lineEnding).data(using: sourceEncoding) else {
            throw NSError(domain: "MoYe", code: 2, userInfo: [NSLocalizedDescriptionKey: "文本无法用原文件编码保存。请通过“文件 → 以 UTF-8 另存为”保存。"])
        }
        return data
    }
    override func read(from data: Data, ofType typeName: String) throws {
        let decoded: (String, String.Encoding)?
        if data.starts(with: [0xFF, 0xFE]), let value = String(data: data, encoding: .utf16) { decoded = (value, .utf16) }
        else if data.starts(with: [0xFE, 0xFF]), let value = String(data: data, encoding: .utf16) { decoded = (value, .utf16) }
        else if let value = String(data: data, encoding: .utf8) { decoded = (value, .utf8) }
        else { decoded = nil }
        guard let (value, encoding) = decoded else {
            throw NSError(domain: "MoYe", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法读取此文件的编码，目前支持 UTF-8 和 UTF-16。"])
        }
        sourceEncoding = encoding
        lineEnding = value.contains("\r\n") ? "\r\n" : (value.contains("\r") ? "\r" : "\n")
        text = value.replacingOccurrences(of: "\u{FEFF}", with: "").replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        for controller in windowControllers { (controller as? EditorWindowController)?.reloadText() }
    }
    override func writableTypes(for saveOperation: NSDocument.SaveOperationType) -> [String] { ["net.daringfireball.markdown", "public.plain-text"] }
    override func fileNameExtension(forType typeName: String, saveOperation: NSDocument.SaveOperationType) -> String? { typeName == "public.plain-text" ? "txt" : "md" }
    override func write(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType, originalContentsURL absoluteOriginalContentsURL: URL?) throws {
        try super.write(to: url, ofType: typeName, for: saveOperation, originalContentsURL: absoluteOriginalContentsURL)
        DispatchQueue.main.async { [weak self] in
            for controller in self?.windowControllers ?? [] { (controller as? EditorWindowController)?.fileLocationChanged() }
        }
    }
}

final class MarkdownDocumentController: NSDocumentController {
    override func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.data]; panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false; panel.title = "打开 Markdown 或文本文件"
        panel.begin { [weak self] response in
            guard response == .OK, let self else { return }
            for url in panel.urls {
                guard ["md", "markdown", "mdown", "mkd", "mmd", "txt"].contains(url.pathExtension.lowercased()) else {
                    NSApp.presentError(NSError(domain: "MoYe", code: 3, userInfo: [NSLocalizedDescriptionKey: "请选择 Markdown 或 .txt 文本文件。"])); continue
                }
                self.openDocument(withContentsOf: url, display: true) { _, _, error in if let error { NSApp.presentError(error) } }
            }
        }
    }
    override func documentClass(forType typeName: String) -> AnyClass? { MarkdownDocument.self }
    override var defaultType: String? { "net.daringfireball.markdown" }
    override func typeForContents(of url: URL) throws -> String { url.pathExtension.lowercased() == "txt" ? "public.plain-text" : "net.daringfireball.markdown" }
}
