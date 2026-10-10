import WebKit

// WKUserContentController retains its handlers; keep the document window weak.
final class PreviewScrollHandler: NSObject, WKScriptMessageHandler {
    weak var owner: EditorWindowController?
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.webView === owner?.preview,
              let ratio = message.body as? Double, ratio.isFinite else { return }
        owner?.previewScrolled(ratio: ratio)
    }
}

enum ScrollSync {
    static func ratio(offset: Double, extent: Double) -> Double {
        max(0, min(1, offset / max(1, extent)))
    }

    static let script = """
    <script>
    function scrollToHeading(i){document.getElementById('heading-'+i)?.scrollIntoView({behavior:'smooth'});}
    let moyeProgrammaticY = null;
    let moyeScrollFrame = null;
    function setScrollRatio(r){
        const extent = Math.max(0,document.documentElement.scrollHeight-innerHeight);
        moyeProgrammaticY = Math.round(Math.max(0,Math.min(1,r))*extent);
        window.scrollTo(0,moyeProgrammaticY);
        moyeProgrammaticY = window.scrollY;
    }
    window.addEventListener('scroll',()=>{
        if(moyeScrollFrame !== null) return;
        moyeScrollFrame = setTimeout(()=>{
            moyeScrollFrame = null;
            // Echoes of editor-driven/restored scrolling never travel back.
            if(moyeProgrammaticY !== null && Math.abs(window.scrollY-moyeProgrammaticY)<1) return;
            moyeProgrammaticY = null;
            const extent = Math.max(1,document.documentElement.scrollHeight-innerHeight);
            window.webkit?.messageHandlers?.moyeScroll?.postMessage(Math.max(0,Math.min(1,window.scrollY/extent)));
        },16);
    },{passive:true});
    </script>
    """
}
