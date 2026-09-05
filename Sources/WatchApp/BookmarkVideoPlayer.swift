import SwiftUI
import WebKit
import WatchCore

struct BookmarkVideoPlayer: NSViewRepresentable {
    let video: YouTubeVideo
    var autoplay = false
    var failed: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(failed: failed) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.mediaTypesRequiringUserActionForPlayback = autoplay ? [] : .all
        configuration.userContentController.add(context.coordinator, name: "watchPlayer")
        let view = WKWebView(frame: .zero, configuration: configuration)
        // Identify this desktop WebKit host as Safari so YouTube supplies its
        // desktop controls, including captions and settings.
        view.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        context.coordinator.attach(view)
        view.loadHTMLString("""
        <!doctype html><html><head><meta name="referrer" content="strict-origin-when-cross-origin">
        <style>html,body{margin:0;height:100%;background:black}iframe{width:100%;height:100%;border:0}</style></head>
        <body><iframe id="player" title="YouTube video player" tabindex="0" src="\(video.embedURL.absoluteString)&autoplay=\(autoplay ? 1 : 0)&controls=1&disablekb=0&fs=1&enablejsapi=1&origin=https%3A%2F%2Fapp.watch.prototype" allow="autoplay; encrypted-media; picture-in-picture; fullscreen" allowfullscreen></iframe>
        <script>
        let player;
        function send(value) { window.webkit.messageHandlers.watchPlayer.postMessage(value); }
        function watchSeek(seconds) {
          if (player && typeof player.getCurrentTime === 'function') {
            player.seekTo(Math.max(0, player.getCurrentTime() + seconds), true);
          }
        }
        function onYouTubeIframeAPIReady() {
          player = new YT.Player('player', {events: {
            onReady: function() { document.getElementById('player').focus(); send({ready:true}); },
            onError: function(event) { send({error:event.data}); }
          }});
        }
        </script><script src="https://www.youtube.com/iframe_api"></script></body></html>
        """, baseURL: URL(string: "https://app.watch.prototype/"))
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {}

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.detach()
        view.configuration.userContentController.removeScriptMessageHandler(forName: "watchPlayer")
        view.stopLoading()
        view.loadHTMLString("", baseURL: nil)
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        weak var webView: WKWebView?
        private var keyMonitor: Any?
        let failed: (String) -> Void
        init(failed: @escaping (String) -> Void) {
            self.failed = failed
        }
        func attach(_ view: WKWebView) {
            webView = view
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let handled = MainActor.assumeIsolated {
                    guard let view = self?.webView,
                          event.window === view.window,
                          view.window?.isKeyWindow == true,
                          let responder = view.window?.firstResponder as? NSView,
                          responder === view || responder.isDescendant(of: view),
                          event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
                          let seconds = Self.seekOffset(for: event.keyCode) else { return false }
                    view.evaluateJavaScript("watchSeek(\(seconds))", completionHandler: nil)
                    return true
                }
                return handled ? nil : event
            }
        }
        static func seekOffset(for keyCode: UInt16) -> Int? {
            switch keyCode {
            case 123: return -5
            case 124: return 5
            default: return nil
            }
        }
        func detach() {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
            webView = nil
        }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let payload = message.body as? [String: Any] else { return }
            if payload["ready"] as? Bool == true, let webView,
               webView.window?.isKeyWindow == true, webView.window?.attachedSheet == nil {
                webView.window?.makeFirstResponder(webView)
            }
            if let error = payload["error"] as? Int {
                failed("YouTube couldn't play this video here, error \(error). Use the open-original icon next to the title.")
            }
        }
    }
}
