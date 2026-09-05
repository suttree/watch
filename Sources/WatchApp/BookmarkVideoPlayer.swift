import SwiftUI
import WebKit
import WatchCore

struct BookmarkVideoPlayer: NSViewRepresentable {
    let video: YouTubeVideo
    var autoplay = false
    var playbackChanged: (Bool) -> Void
    var failed: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(playbackChanged: playbackChanged, failed: failed) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.mediaTypesRequiringUserActionForPlayback = autoplay ? [] : .all
        configuration.userContentController.add(context.coordinator, name: "watchPlayer")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.loadHTMLString("""
        <!doctype html><html><head><meta name="referrer" content="strict-origin-when-cross-origin">
        <style>html,body{margin:0;height:100%;background:black}iframe{width:100%;height:100%;border:0}</style></head>
        <body><iframe id="player" src="\(video.embedURL.absoluteString)&autoplay=\(autoplay ? 1 : 0)&enablejsapi=1&origin=https%3A%2F%2Fapp.watch.prototype" allow="autoplay; encrypted-media; picture-in-picture; fullscreen" allowfullscreen></iframe>
        <script>
        function send(value) { window.webkit.messageHandlers.watchPlayer.postMessage(value); }
        function onYouTubeIframeAPIReady() {
          new YT.Player('player', {events: {
            onStateChange: function(event) { send({playing:event.data === 1}); },
            onError: function(event) { send({error:event.data}); }
          }});
        }
        </script><script src="https://www.youtube.com/iframe_api"></script></body></html>
        """, baseURL: URL(string: "https://app.watch.prototype/"))
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {}

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.playbackChanged(false)
        view.configuration.userContentController.removeScriptMessageHandler(forName: "watchPlayer")
        view.stopLoading()
        view.loadHTMLString("", baseURL: nil)
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        let playbackChanged: (Bool) -> Void
        let failed: (String) -> Void
        init(playbackChanged: @escaping (Bool) -> Void, failed: @escaping (String) -> Void) {
            self.playbackChanged = playbackChanged
            self.failed = failed
        }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let payload = message.body as? [String: Any] else { return }
            if let playing = payload["playing"] as? Bool { playbackChanged(playing) }
            if let error = payload["error"] as? Int {
                playbackChanged(false)
                failed("YouTube couldn't play this video here, error \(error). Use the open-original icon next to the title.")
            }
        }
    }
}
