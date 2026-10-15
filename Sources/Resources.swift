import AppKit
import WebKit
import UniformTypeIdentifiers

enum ImagePaths {
    static let extensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "avif", "heic", "tif", "tiff", "bmp", "svg"]
    static func isImage(_ url: URL) -> Bool { extensions.contains(url.pathExtension.lowercased()) }
    static func imageURLs(in pasteboard: NSPasteboard) -> [URL] {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.filter(isImage)
    }
    static func normalized(_ url: URL) -> URL { url.standardizedFileURL.resolvingSymlinksInPath() }
    /// Relative when the image is inside the document directory. Otherwise an absolute path.
    static func reference(image: URL, document: URL?) -> String {
        let imageURL = normalized(image)
        guard let document else { return imageURL.path }
        let directory = normalized(document.deletingLastPathComponent())
        let base = directory.path
        let prefix = base.hasSuffix("/") ? base : base + "/"
        let target = imageURL.path
        guard target == base || target.hasPrefix(prefix) else { return imageURL.path }
        let relative = target == base ? imageURL.lastPathComponent : String(target.dropFirst(prefix.count))
        return relative.isEmpty ? imageURL.lastPathComponent : relative
    }
    static func destination(_ path: String) -> String {
        let needsBrackets = path.contains(" ") || path.contains("(") || path.contains(")") || path.contains("<") || path.contains(">")
        guard needsBrackets else { return path }
        let escaped = path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "<", with: "\\<").replacingOccurrences(of: ">", with: "\\>")
        return "<\(escaped)>"
    }
    static func sanitizedAlt(_ text: String, fallback: String) -> String {
        let cleaned = text.replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")
            .replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let value = cleaned.isEmpty ? fallback.replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "") : cleaned
        return value.isEmpty ? "图片" : value
    }
    static func markdown(image: URL, document: URL?, alt: String) -> String {
        let label = sanitizedAlt(alt, fallback: image.deletingPathExtension().lastPathComponent)
        return "![\(label)](\(destination(reference(image: image, document: document))))"
    }
}

final class LocalImageHandler: NSObject, WKURLSchemeHandler {
    var root: URL?
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url, url.host == "document",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            urlSchemeTask.didFailWithError(URLError(.badURL)); return
        }
        let relative = String(components.path.dropFirst())
        let absolute = ImagePaths.normalized(URL(fileURLWithPath: "/" + relative))
        var file: URL?
        if let root {
            let directory = ImagePaths.normalized(root)
            let prefix = directory.path.hasSuffix("/") ? directory.path : directory.path + "/"
            let inside = ImagePaths.normalized(directory.appendingPathComponent(relative))
            if (inside.path == directory.path || inside.path.hasPrefix(prefix)), FileManager.default.fileExists(atPath: inside.path) {
                file = inside
            }
        }
        if file == nil, !relative.contains(".."), FileManager.default.fileExists(atPath: absolute.path) { file = absolute }
        guard let file, ImagePaths.isImage(file) else { urlSchemeTask.didFailWithError(URLError(.noPermissionsToReadFile)); return }
        do {
            let data = try Data(contentsOf: file)
            let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            urlSchemeTask.didReceive(URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: nil))
            urlSchemeTask.didReceive(data); urlSchemeTask.didFinish()
        } catch { urlSchemeTask.didFailWithError(error) }
    }
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
