import WebKit

// WKUserContentController retains its handlers; keep the document window weak.
final class PreviewScrollHandler: NSObject, WKScriptMessageHandler {
    weak var owner: EditorWindowController?
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.webView === owner?.preview else { return }
        guard let position = message.body as? Double, position.isFinite else { return }
        owner?.previewScrolled(position: position)
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
    let moyeBlocks=null;
    function invalidateSourceBlocks(){moyeBlocks=null;}
    function rebuildSourceBlocks(){
        moyeBlocks=Array.from(document.querySelectorAll('[data-sourcepos]')).flatMap(el=>{
            const match=/^(\\d+):\\d+-(\\d+):\\d+/.exec(el.getAttribute('data-sourcepos')||'');
            if(!match) return [];
            const rect=el.getBoundingClientRect();
            const top=rect.top+window.scrollY;
            return [{start:+match[1], end:+match[2], top, bottom:top+rect.height}];
        });
    }
    function sourceBlocks(){
        if(!moyeBlocks) rebuildSourceBlocks();
        return moyeBlocks;
    }
    new ResizeObserver(()=>invalidateSourceBlocks()).observe(document.documentElement);
    function blockSpan(item){return item.end===item.start?1:(item.end-item.start);}
    function lineAtScroll(y){
        const items=sourceBlocks();
        if(!items.length) return 1;
        let chosen=null;
        for(const item of items){
            if(y<item.top || y>item.bottom) continue;
            const span=item.end-item.start;
            if(!chosen || span<chosen.end-chosen.start || (span===chosen.end-chosen.start && item.start>=chosen.start)) chosen=item;
        }
        if(!chosen){
            let prev=null, next=null;
            for(const item of items){
                if(item.bottom<=y && (!prev || item.bottom>prev.bottom)) prev=item;
                if(item.top>=y && (!next || item.top<next.top)) next=item;
            }
            if(prev && next && next.top>prev.bottom){
                const frac=(y-prev.bottom)/(next.top-prev.bottom);
                const prevPos=prev.start+blockSpan(prev);
                return prevPos+frac*(next.start-prevPos);
            }
            if(next) return next.start;
            return prev?prev.start+blockSpan(prev):1;
        }
        if(chosen.bottom<=chosen.top) return chosen.start;
        const frac=Math.min(1,Math.max(0,(y-chosen.top)/(chosen.bottom-chosen.top)));
        return chosen.start+frac*blockSpan(chosen);
    }
    function lineAtTop(){return lineAtScroll(window.scrollY);}
    function scrollToLine(line){
        const items=sourceBlocks();
        let y=0;
        if(line>1 && items.length){
            let chosen=null;
            for(const item of items){
                const limit=item.start+blockSpan(item);
                if(line<item.start || line>limit) continue;
                const span=item.end-item.start;
                if(!chosen || span<chosen.end-chosen.start) chosen=item;
            }
            if(!chosen){
                for(const item of items) if(item.start<=line && (!chosen || item.start>chosen.start)) chosen=item;
                y=chosen?chosen.top:0;
            }else if(chosen.bottom<=chosen.top){
                y=chosen.top;
            }else{
                const frac=Math.min(1,Math.max(0,(line-chosen.start)/blockSpan(chosen)));
                y=chosen.top+frac*(chosen.bottom-chosen.top);
            }
        }
        const extent=Math.max(0,document.documentElement.scrollHeight-innerHeight);
        moyeProgrammaticY=Math.max(0,Math.min(extent,y));
        window.scrollTo(0,moyeProgrammaticY);
        moyeProgrammaticY=window.scrollY;
    }
    function setScrollRatio(r){
        const extent=Math.max(0,document.documentElement.scrollHeight-innerHeight);
        moyeProgrammaticY=Math.round(Math.max(0,Math.min(1,r))*extent);
        window.scrollTo(0,moyeProgrammaticY);
        moyeProgrammaticY=window.scrollY;
    }
    window.addEventListener('scroll',()=>{
        if(moyeScrollFrame!==null) return;
        moyeScrollFrame=setTimeout(()=>{
            moyeScrollFrame=null;
            if(moyeProgrammaticY!==null && Math.abs(window.scrollY-moyeProgrammaticY)<1) return;
            moyeProgrammaticY=null;
            window.webkit?.messageHandlers?.moyeScroll?.postMessage(lineAtScroll(window.scrollY));
        },16);
    },{passive:true});
    </script>
    """
}
