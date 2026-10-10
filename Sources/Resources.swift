import AppKit
import WebKit
import UniformTypeIdentifiers

final class LocalImageHandler: NSObject, WKURLSchemeHandler {
    var root: URL?
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let root, let url = urlSchemeTask.request.url,
              url.host == "document", let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            urlSchemeTask.didFailWithError(URLError(.badURL)); return
        }
        let file = root.appendingPathComponent(String(components.path.dropFirst())).standardizedFileURL.resolvingSymlinksInPath()
        let directory = root.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        let allowed = ["png", "jpg", "jpeg", "gif", "webp", "avif", "heic", "tiff", "bmp", "svg"]
        guard file.path.hasPrefix(directory), allowed.contains(file.pathExtension.lowercased()) else {
            urlSchemeTask.didFailWithError(URLError(.noPermissionsToReadFile)); return
        }
        do {
            let data = try Data(contentsOf: file)
            let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            urlSchemeTask.didReceive(URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: nil))
            urlSchemeTask.didReceive(data); urlSchemeTask.didFinish()
        } catch { urlSchemeTask.didFailWithError(error) }
    }
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
