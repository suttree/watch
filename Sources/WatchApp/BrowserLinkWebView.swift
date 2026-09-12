import WebKit

/// Reuses WebKit's link action so it retains the exact URL, including inside frames.
final class BrowserLinkWebView: WKWebView {
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        Self.addBrowserAction(to: menu)
    }

    static func addBrowserAction(to menu: NSMenu) {
        guard !menu.items.contains(where: { $0.identifier?.rawValue == "WatchOpenInBrowser" }),
              let native = menu.items.first(where: {
                  $0.identifier?.rawValue == "WKMenuItemIdentifierOpenLinkInNewWindow"
              }), let item = native.copy() as? NSMenuItem else { return }
        item.title = "Open in browser"
        item.identifier = NSUserInterfaceItemIdentifier("WatchOpenInBrowser")
        item.image = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
        menu.insertItem(item, at: 0)
        menu.insertItem(.separator(), at: 1)
    }
}
