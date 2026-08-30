import AppKit
import Foundation
import WatchCore
import WebKit

/// Loads pages headlessly through WebKit (never shown on screen) purely as
/// an extraction engine — the same rendering engine Safari uses, so pages
/// that need real JS execution to produce their content still work, unlike a
/// plain HTML-over-HTTP fetch.
@MainActor
final class ArticleFetcher {
    /// These fetches are throwaway extraction, not browsing — an ephemeral
    /// data store means no cookies or site data persist across launches
    /// (appropriate for pages you never actually see). That alone doesn't
    /// stop the Keychain prompt, though: WebKit wraps WebCrypto keys with a
    /// Keychain item tied to the app's code signature even in an ephemeral
    /// session, and an ad-hoc dev build's signature changes on every rebuild,
    /// so macOS re-prompts each time some page's script touches it. WebKit
    /// exposes no API to supply that key ourselves, so the only lever is
    /// keeping pages away from WebCrypto in the first place.
    ///
    /// Note the two things this deliberately does beyond hiding
    /// `window.crypto.subtle`, both of which were letting the prompt through:
    /// it defines the override on `Crypto.prototype` as well, since a page
    /// can reach a `Crypto` instance the frame's own `crypto` shadowing
    /// doesn't cover; and it hands back a stub whose every method returns a
    /// rejected promise rather than `undefined`, so a script reaching for
    /// `crypto.subtle.importKey` fails its own call instead of throwing a
    /// TypeError partway through rendering the article we came for.
    ///
    /// Workers go too, and this is the part that actually stops the Keychain
    /// prompt. A user script does not run inside a worker, so a worker's
    /// `crypto.subtle` is the real one and no page-level override can reach
    /// it — Reuters and Ars both spin up blob workers, which is where the
    /// prompt was still coming from after the override above went in. They're
    /// replaced with inert stubs rather than removed: a page that calls
    /// `new Worker(...)` and gets a TypeError may abandon the render, while
    /// one whose worker simply never answers usually carries on and leaves the
    /// article text sitting in the DOM, which is all this is here for.
    private static let webCryptoBlockerSource = """
    (function () {
      try {
        var deny = function () {
          return Promise.reject(new DOMException('Disabled', 'NotSupportedError'));
        };
        var stub = new Proxy({}, { get: function () { return deny; } });
        var hide = function (target) {
          try {
            Object.defineProperty(target, 'subtle', {
              get: function () { return stub; },
              configurable: true
            });
          } catch (e) {}
        };
        if (self.Crypto && self.Crypto.prototype) { hide(self.Crypto.prototype); }
        if (self.crypto) { hide(self.crypto); }
        if (self.navigator && self.navigator.serviceWorker) {
          try { self.navigator.serviceWorker.register = deny; } catch (e) {}
        }

        var inert = function () {
          return {
            postMessage: function () {},
            terminate: function () {},
            addEventListener: function () {},
            removeEventListener: function () {},
            dispatchEvent: function () { return false; },
            onmessage: null,
            onmessageerror: null,
            onerror: null,
            port: {
              postMessage: function () {},
              start: function () {},
              close: function () {},
              addEventListener: function () {},
              removeEventListener: function () {}
            }
          };
        };
        try { self.Worker = function () { return inert(); }; } catch (e) {}
        try { self.SharedWorker = function () { return inert(); }; } catch (e) {}
      } catch (e) {}
    })();
    """

    /// Headless doesn't mean sizeless. A zero-frame webview still loads and
    /// still runs scripts, but it lays out into a 0×0 viewport, and two things
    /// fall off a cliff when it does: `innerText` — which every extraction
    /// script here depends on — reports nothing for elements that aren't being
    /// rendered, and responsive stylesheets collapse to their narrowest
    /// breakpoint, which on plenty of sites means hiding the main content
    /// outright. Pinboard came back with 273 anchors and 240 characters of
    /// text, all of it nav and footer, until this had a real size.
    private static let viewport = NSRect(x: 0, y: 0, width: 1280, height: 1600)

    /// WebKit's stock user agent stops at "AppleWebKit/605.1.15 (KHTML, like
    /// Gecko)" — no `Version/… Safari/…` on the end, which is a reliable
    /// tell that a page is being loaded by an embedded webview rather than by
    /// Safari. Reddit answers that UA with an empty shell: HTTP 200, correct
    /// title, zero anchors. Completing the string the way Safari sends it
    /// gets the real page.
    private static let safariUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Safari/605.1.15"

    /// Shared across every headless webview this fetcher creates. Left
    /// unset, each `WKWebViewConfiguration` gets its own process pool and
    /// WebKit spins up a brand-new WebContent process per fetch — a refresh
    /// that touches a few dozen story pages was launching a few dozen
    /// processes, fighting each other for CPU on top of whatever each page's
    /// own load actually cost. Safe to share for throwaway extraction views
    /// that render nothing on screen: `.nonPersistent()` on the data store
    /// below is what isolates cookies and storage between fetches, not the
    /// process pool.
    private static let processPool = WKProcessPool()

    private static func makeHeadlessWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.processPool = processPool
        configuration.websiteDataStore = .nonPersistent()
        let blockWebCrypto = WKUserScript(
            source: webCryptoBlockerSource,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        configuration.userContentController.addUserScript(blockWebCrypto)
        let webView = WKWebView(frame: viewport, configuration: configuration)
        webView.customUserAgent = safariUserAgent
        return webView
    }

    /// Up to `limit` headline-level stories from a tracked source's front
    /// page: the first few real h1/h2/h3 headings that carry a link,
    /// skipping ones inside nav/header/footer/aside boilerplate.
    ///
    /// Two things learned from inspecting real markup (theguardian.com) that
    /// shape this script: (1) a heading's own `innerText` often glues a
    /// category "kicker" onto the real headline with no separating space
    /// (e.g. "TariffsTrump announces…") because they're separate block
    /// children with layout-only spacing — a child element whose class
    /// contains "headline" is a much more reliable title when present.
    /// (2) the link and thumbnail for a headline are frequently *not* inside
    /// its immediate parent or even a `article`/`li` ancestor — they can sit
    /// several levels up, in a sibling subtree — so both need to search
    /// progressively wider ancestors rather than one fixed container.
    func fetchStories(from source: TrackedSource, limit: Int = 8) async -> [Story] {
        guard let url = URL(string: source.url) else {
            return []
        }

        // A pasted YouTube watch link is already a story. Rendering it in
        // WebKit first lands on Google's consent page, whose copy can look
        // like a real headline. Ask YouTube's public oEmbed endpoint for the
        // video's title instead, without needing an API key.
        if Self.isYouTubeVideoURL(url), let videoStory = await fetchYouTubeVideo(source: source, url: url) {
            return [videoStory]
        }

        if let feedStories = await fetchFeedStories(from: source, url: url, limit: limit), !feedStories.isEmpty {
            return feedStories
        }

        let webView = Self.makeHeadlessWebView()
        await load(webView, url: url)

        let script = """
        (function() {
            // Modern component-based sites (Reddit's current UI is the main
            // example) render posts inside Shadow DOM custom elements, which
            // a plain querySelectorAll can't see into at all — this walks
            // into every shadow root it finds, recursively.
            function queryAllDeep(selector, root) {
                root = root || document;
                var results = Array.prototype.slice.call(root.querySelectorAll(selector));
                var all = root.querySelectorAll('*');
                for (var i = 0; i < all.length; i++) {
                    if (all[i].shadowRoot) {
                        results = results.concat(queryAllDeep(selector, all[i].shadowRoot));
                    }
                }
                return results;
            }

            // Consent-management platforms (OneTrust, Cookiebot, etc.) and
            // similar chrome widgets frequently mark their own banner
            // heading as a real h1/h2/h3 for accessibility, which otherwise
            // sails right through a plain heading scan.
            var boilerplatePhrases = [
                'manage your data', 'manage preferences', 'manage cookies', 'cookie preferences',
                'cookie policy', 'cookie settings', 'privacy policy', 'privacy settings',
                'terms of service', 'terms of use', 'sign up', 'sign in', 'log in', 'subscribe',
                'newsletter', 'accept all', 'accept cookies',
                // Consent dialogs phrase themselves this way as often as they
                // mention cookies outright — Ars serves one whose heading is
                // "We and our partners process data for the following purposes".
                'we and our partners', 'process data', 'we value your privacy',
                'this page describes the purposes for which google uses cookies',
                // Site chrome that reads like a headline: logo links ("Ars
                // Technica homepage"), skip links, and ad slots.
                'homepage', 'skip to content', 'skip to main content',
                'advertisement', 'sponsored', 'all rights reserved', 'go to comments',
                // Reddit's footer locale links. Its footer isn't a <footer>
                // and carries no class the selector below can catch, so the
                // text is the only handle on them.
                'best of reddit'
            ];
            var chromeSelector = 'nav, header, footer, aside, [class*="cookie" i], [id*="cookie" i], [class*="consent" i], [id*="consent" i], [class*="onetrust" i], [id*="onetrust" i], [class*="promoted" i], [id*="promoted" i], [class*="sponsored" i], [class*="footer" i], [id*="footer" i]';
            function isBoilerplate(el) {
                var hit = el.closest(chromeSelector);
                // Consent libraries stamp state classes onto <body> — Ars
                // carries `fides-overlay-modal-link-shown` there — which would
                // otherwise mark every heading on the page as boilerplate.
                return hit !== null && hit !== document.body && hit !== document.documentElement;
            }
            function isBoilerplateText(text) {
                var lower = text.toLowerCase();
                return boilerplatePhrases.some(function(phrase) { return lower.indexOf(phrase) !== -1; });
            }
            function wordCount(text) {
                return text.split(/\\s+/).filter(function(w) { return w.length > 0; }).length;
            }
            /// Titles that are structurally not stories, whatever the site.
            function isJunkTitle(text) {
                if (isBoilerplateText(text)) return true;
                // A bare domain is an attribution label sitting beside the real
                // headline — Hacker News prints the source domain after every
                // title, and Bubbles does the same in parentheses.
                if (/^[a-z0-9][a-z0-9.-]*\\.[a-z]{2,}$/i.test(text)) return true;
                // Comment-count links: the Verge renders them as
                // "CommentsComment Icon Bubble14", which has no word boundary
                // after the first word to anchor against. Matching the plural
                // leaves a headline opening with "Commentary" alone.
                if (/^comments/i.test(text)) return true;
                // Fediverse and X handles, which aggregators list as the
                // discussion source next to a story.
                if (/^@/.test(text)) return true;
                // Reddit's user and subreddit chips.
                if (/^[ur]\\/\\S+$/i.test(text)) return true;
                return false;
            }
            /// Links that never point at a story, however their text reads.
            function isJunkLink(href) {
                if (!href) return true;
                if (/\\/(user|users|u)\\//i.test(href)) return true;
                if (/\\/(login|signup|sign-up|register|submit|settings|preferences)(\\/|$|\\?)/i.test(href)) return true;
                // Reddit serves its promoted posts off alb.reddit.com, and the
                // usual ad networks are worth naming while we're here.
                return /(alb\\.reddit\\.com|doubleclick\\.net|googlesyndication\\.com|amazon-adsystem\\.com|taboola\\.com|outbrain\\.com)/i.test(href);
            }
            function titleOf(h) {
                var headlineEl = h.querySelector('[class*="headline" i]');
                if (headlineEl) {
                    var t = headlineEl.innerText.trim().replace(/\\s+/g, ' ');
                    if (t.length > 10) return t;
                }
                return h.innerText.trim().replace(/\\s+/g, ' ');
            }
            function findLink(h) {
                var el = h;
                for (var depth = 0; depth < 6 && el; depth++) {
                    var link = el.querySelector('a[href]');
                    if (link) return { link: link, container: el };
                    el = el.parentElement;
                }
                return null;
            }
            function findImage(container) {
                var el = container;
                var img = el.querySelector ? el.querySelector('img') : null;
                var climb = 0;
                while (!img && el.parentElement && climb < 3) {
                    el = el.parentElement;
                    img = el.querySelector('img');
                    climb++;
                }
                return img ? (img.currentSrc || img.src || null) : null;
            }

            var seen = {};
            var seenURL = {};
            var out = [];

            // Tier 1: proper headline markup (news homepages with real
            // h1/h2/h3 elements per story).
            var headings = queryAllDeep('h1, h2, h3');
            for (var i = 0; i < headings.length && out.length < \(limit); i++) {
                var h = headings[i];
                if (isBoilerplate(h)) continue;
                var text = titleOf(h);
                if (text.length < 15 || text.length > 160) continue;
                // Real headlines are sentences; the headings that aren't
                // stories are almost always two- or three-word noun phrases —
                // "Featured Podcasts", "Upcoming Tech Events", "Community
                // highlights", "Ars Technica homepage". Requiring four words
                // separates them without needing to know any site's markup,
                // and on aggregators it clears tier 1 out of the way so the
                // link scan below can find the actual stories.
                if (wordCount(text) < 4) continue;
                if (isJunkTitle(text)) continue;
                if (seen[text]) continue;
                var found = findLink(h);
                if (!found) continue;
                if (isJunkLink(found.link.href)) continue;
                // Reddit lists a post's title on its own and again with the
                // vote and comment counts appended; same link, so dedupe on
                // that rather than on the text.
                if (seenURL[found.link.href]) continue;
                seen[text] = true;
                seenURL[found.link.href] = true;
                out.push({ title: text, url: found.link.href, image: findImage(found.container) });
            }

            // Tier 2: link-aggregator style sites (Hacker News, Pinboard,
            // Bubbles, Reddit) that list stories as plain <a> links with no
            // heading markup at all. Only kicks in when tier 1 found
            // basically nothing, since it's a much cruder heuristic.
            if (out.length < 3) {
                var anchors = queryAllDeep('a[href]');
                for (var j = 0; j < anchors.length && out.length < \(limit); j++) {
                    var a = anchors[j];
                    if (isBoilerplate(a)) continue;
                    var href = a.getAttribute('href') || '';
                    if (href.indexOf('mailto:') === 0 || href.indexOf('tel:') === 0 || href.indexOf('javascript:') === 0 || href.indexOf('#') === 0) continue;
                    var linkText = a.innerText.trim().replace(/\\s+/g, ' ');
                    if (linkText.length < 15 || linkText.length > 160) continue;
                    // Aggregators print the discussion source beside each
                    // story — "Daring Fireball", "MacRumors Forums", "Contact
                    // Editors". Two-word links are nearly always one of those;
                    // three is low enough to keep real short titles like
                    // "Thinking in Python" and "Stupid Summer People".
                    if (wordCount(linkText) < 3) continue;
                    // A link inside a paragraph is a citation in someone's
                    // prose, not an entry in a list of stories — the Verge's
                    // front page carries liveblog copy whose inline links
                    // otherwise read as headlines.
                    if (a.closest('p')) continue;
                    // A title wrapped in parens is almost always a source
                    // attribution link sitting right next to the real one
                    // (Bubbles does exactly this), not a story itself.
                    if (linkText.charAt(0) === '(' && linkText.charAt(linkText.length - 1) === ')') continue;
                    if (isJunkTitle(linkText)) continue;
                    if (seen[linkText]) continue;
                    if (!a.href) continue;
                    if (isJunkLink(a.href)) continue;
                    if (seenURL[a.href]) continue;
                    seen[linkText] = true;
                    seenURL[a.href] = true;
                    out.push({ title: linkText, url: a.href, image: findImage(a) });
                }
            }

            // Some WordPress themes, including Web Curios, put post links in
            // a block named `title` without using a heading element. Keep
            // this fallback scoped to title-like blocks so ordinary prose
            // links do not turn into stories.
            if (out.length < 3) {
                var titleLinks = queryAllDeep('.title a[href], [class*="entry-title" i] a[href], [class*="post-title" i] a[href]');
                for (var k = 0; k < titleLinks.length && out.length < \(limit); k++) {
                    var titleLink = titleLinks[k];
                    if (isBoilerplate(titleLink)) continue;
                    var titleHref = titleLink.getAttribute('href') || '';
                    var titleLinkText = titleLink.innerText.trim().replace(/\\s+/g, ' ');
                    if (titleLinkText.length < 8 || titleLinkText.length > 160) continue;
                    if (isJunkTitle(titleLinkText) || isJunkLink(titleHref)) continue;
                    if (seen[titleLinkText] || seenURL[titleLink.href]) continue;
                    seen[titleLinkText] = true;
                    seenURL[titleLink.href] = true;
                    out.push({ title: titleLinkText, url: titleLink.href, image: findImage(titleLink) });
                }
            }

            // A few sources use application-specific markup that deliberately
            // does not resemble a conventional news homepage. Keep these
            // selectors host-scoped so they cannot turn unrelated navigation
            // into stories for other feeds.
            var host = location.hostname.toLowerCase();
            if (host === 'www.reddit.com' || host === 'reddit.com') {
                var redditPosts = queryAllDeep('shreddit-post');
                for (var r = 0; r < redditPosts.length && out.length < \(limit); r++) {
                    var post = redditPosts[r];
                    var redditTitle = (post.getAttribute('post-title') || '').trim();
                    var redditHref = post.getAttribute('content-href') || '';
                    var redditLink = post.querySelector('a[slot="full-post-link"], a[href*="/comments/"]');
                    if (!redditHref && redditLink) redditHref = redditLink.href;
                    if (!redditTitle && redditLink) redditTitle = redditLink.innerText.trim();
                    if (!redditTitle || redditTitle.length < 8 || !redditHref) continue;
                    if (isJunkTitle(redditTitle) || isJunkLink(redditHref) || seenURL[redditHref]) continue;
                    seen[redditTitle] = true;
                    seenURL[redditHref] = true;
                    out.push({ title: redditTitle, url: redditHref, image: findImage(post) });
                }
            } else if (host === 'www.patreon.com' || host === 'patreon.com') {
                var patreonLinks = queryAllDeep('a[href*="/posts/"]');
                for (var p = 0; p < patreonLinks.length && out.length < \(limit); p++) {
                    var patreonLink = patreonLinks[p];
                    var patreonHref = patreonLink.href;
                    var patreonTitle = (patreonLink.getAttribute('aria-label') || patreonLink.getAttribute('title') || patreonLink.innerText || '').trim().replace(/\\s+/g, ' ');
                    if (patreonTitle.length < 8 || patreonTitle.length > 160) continue;
                    if (isJunkTitle(patreonTitle) || isJunkLink(patreonHref) || seenURL[patreonHref]) continue;
                    seen[patreonTitle] = true;
                    seenURL[patreonHref] = true;
                    out.push({ title: patreonTitle, url: patreonHref, image: findImage(patreonLink) });
                }
            } else if (host === 'technorati.com' || host === 'www.technorati.com') {
                var technoratiLinks = queryAllDeep('[class*="card" i] a[href], [class*="story" i] a[href], [class*="headline" i] a[href]');
                for (var t = 0; t < technoratiLinks.length && out.length < \(limit); t++) {
                    var technoratiLink = technoratiLinks[t];
                    var technoratiTitle = (technoratiLink.getAttribute('aria-label') || technoratiLink.getAttribute('title') || technoratiLink.innerText || '').trim().replace(/\\s+/g, ' ');
                    if (technoratiTitle.length < 8 || technoratiTitle.length > 160) continue;
                    if (isJunkTitle(technoratiTitle) || isJunkLink(technoratiLink.href) || seenURL[technoratiLink.href]) continue;
                    seen[technoratiTitle] = true;
                    seenURL[technoratiLink.href] = true;
                    out.push({ title: technoratiTitle, url: technoratiLink.href, image: findImage(technoratiLink) });
                }
            } else if (host === 'www.404media.co' || host === '404media.co') {
                var fourOhFourLinks = queryAllDeep('.post-card__title a[href]');
                for (var f = 0; f < fourOhFourLinks.length && out.length < \(limit); f++) {
                    var fourOhFourLink = fourOhFourLinks[f];
                    var fourOhFourTitle = (fourOhFourLink.getAttribute('aria-label') || fourOhFourLink.getAttribute('title') || fourOhFourLink.innerText || '').trim().replace(/\\s+/g, ' ');
                    if (fourOhFourTitle.length < 8 || fourOhFourTitle.length > 160) continue;
                    if (isJunkTitle(fourOhFourTitle) || isJunkLink(fourOhFourLink.href) || seenURL[fourOhFourLink.href]) continue;
                    seen[fourOhFourTitle] = true;
                    seenURL[fourOhFourLink.href] = true;
                    out.push({ title: fourOhFourTitle, url: fourOhFourLink.href, image: findImage(fourOhFourLink) });
                }
            } else if (host === 'www.bbc.com' || host === 'bbc.com') {
                var bbcLinks = queryAllDeep('[data-testid="card-headline"] a[href], [data-testid="card-headline"]');
                for (var b = 0; b < bbcLinks.length && out.length < \(limit); b++) {
                    var bbcHeading = bbcLinks[b];
                    var bbcFound = bbcHeading.matches('a[href]') ? { link: bbcHeading, container: bbcHeading } : findLink(bbcHeading);
                    if (!bbcFound) continue;
                    var bbcTitle = bbcHeading.innerText.trim().replace(/\\s+/g, ' ');
                    if (bbcTitle.length < 8 || bbcTitle.length > 160) continue;
                    if (isJunkTitle(bbcTitle) || isJunkLink(bbcFound.link.href) || seenURL[bbcFound.link.href]) continue;
                    seen[bbcTitle] = true;
                    seenURL[bbcFound.link.href] = true;
                    out.push({ title: bbcTitle, url: bbcFound.link.href, image: findImage(bbcFound.container) });
                }
            } else if (host === 'cutcher.co.uk' || host === 'www.cutcher.co.uk') {
                var cutcherLinks = queryAllDeep('article.linklog header h2 a[href]');
                for (var c = 0; c < cutcherLinks.length && out.length < \(limit); c++) {
                    var cutcherLink = cutcherLinks[c];
                    var cutcherTitle = cutcherLink.innerText.trim().replace(/\\s+/g, ' ');
                    if (cutcherTitle.length < 8 || cutcherTitle.length > 160) continue;
                    if (isJunkTitle(cutcherTitle) || isJunkLink(cutcherLink.href) || seenURL[cutcherLink.href]) continue;
                    seen[cutcherTitle] = true;
                    seenURL[cutcherLink.href] = true;
                    out.push({ title: cutcherTitle, url: cutcherLink.href, image: findImage(cutcherLink) });
                }
            }

            return out;
        })();
        """
        let rows = decodeJSONArray(await evaluateJSON(webView, script: script))
        let sourceName = source.name.isEmpty ? (url.host ?? source.url) : source.name
        let stories: [Story] = rows.compactMap { row in
            guard let title = row["title"] as? String, let storyURL = row["url"] as? String else {
                return nil
            }
            return Story(
                title: title,
                storyURL: storyURL,
                sourceID: source.id,
                sourceName: sourceName,
                imageURL: row["image"] as? String
            )
        }
        if !stories.isEmpty { return stories }

        // Some sources are single watch pages rather than index pages. If
        // the headline scan found no links, use the document's own title as
        // one queue item instead of returning an empty source. This covers
        // movie pages and channel landing pages whose markup is app-driven.
        let fallbackTitle = (decodeJSONObject(await evaluateJSON(webView, script: "({ title: document.title })"))?["title"] as? String)
            ?? url.lastPathComponent.replacingOccurrences(of: "-", with: " ").capitalized
        guard !fallbackTitle.isEmpty,
              !fallbackTitle.localizedCaseInsensitiveContains("google uses cookies"),
              !fallbackTitle.localizedCaseInsensitiveContains("privacy & terms") else { return [] }
        return [Story(title: fallbackTitle, storyURL: url.absoluteString, sourceID: source.id, sourceName: sourceName)]
    }

    private static func isYouTubeVideoURL(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        if host == "youtu.be" || host.hasSuffix(".youtu.be") { return !url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty }
        guard host == "youtube.com" || host.hasSuffix(".youtube.com") else { return false }
        let hasVideoID = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains(where: { $0.name == "v" && !($0.value ?? "").isEmpty }) == true
        return (url.path == "/watch" && hasVideoID) || url.path.hasPrefix("/shorts/") || url.path.hasPrefix("/embed/")
    }

    private func fetchYouTubeVideo(source: TrackedSource, url: URL) async -> Story? {
        guard var components = URLComponents(string: "https://www.youtube.com/oembed") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "url", value: url.absoluteString),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let endpoint = components.url else { return nil }
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 8
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              (200..<400).contains(httpResponse.statusCode),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let title = payload["title"] as? String,
              !title.isEmpty else { return nil }
        let sourceName = source.name.isEmpty ? "YouTube" : source.name
        return Story(title: title, storyURL: url.absoluteString, sourceID: source.id, sourceName: sourceName, imageURL: payload["thumbnail_url"] as? String)
    }

    /// Reads RSS 2.0 and Atom URLs directly. A direct feed is both faster and
    /// more reliable than rendering its publisher's homepage, while a normal
    /// webpage still falls through to the WebKit parser above.
    private func fetchFeedStories(from source: TrackedSource, url: URL, limit: Int) async -> [Story]? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/rss+xml, application/atom+xml, application/xml, text/xml, text/html;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue(Self.safariUserAgent, forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              (200..<400).contains(httpResponse.statusCode),
              let parser = FeedParser(data: data, baseURL: url),
              parser.parse(),
              !parser.entries.isEmpty else {
            return nil
        }

        let sourceName = source.name.isEmpty ? (url.host ?? source.url) : source.name
        return parser.entries.prefix(limit).compactMap { entry in
            guard let title = entry.title?.trimmingCharacters(in: .whitespacesAndNewlines),
                  title.count >= 3,
                  let rawURL = entry.link?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let storyURL = URL(string: rawURL, relativeTo: url)?.absoluteURL.absoluteString else {
                return nil
            }
            return Story(
                title: title,
                storyURL: storyURL,
                sourceID: source.id,
                sourceName: sourceName,
                imageURL: entry.image.flatMap { URL(string: $0, relativeTo: url)?.absoluteURL.absoluteString }
            )
        }
    }

    private final class FeedParser: NSObject, XMLParserDelegate {
        struct Entry {
            var title: String?
            var link: String?
            var image: String?
        }

        let data: Data
        let baseURL: URL
        private(set) var entries: [Entry] = []
        private var currentEntry: Entry?
        private var currentField: String?
        private var textBuffer = ""

        init?(data: Data, baseURL: URL) {
            guard !data.isEmpty else { return nil }
            self.data = data
            self.baseURL = baseURL
        }

        func parse() -> Bool {
            let parser = XMLParser(data: data)
            parser.delegate = self
            return parser.parse()
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String,
                    namespaceURI: String?, qualifiedName qName: String?,
                    attributes attributeDict: [String: String] = [:]) {
            let element = elementName.lowercased()
            if element == "item" || element == "entry" {
                currentEntry = Entry()
                currentField = nil
                textBuffer = ""
                return
            }
            guard currentEntry != nil else { return }

            if element == "link" {
                if let href = attributeDict["href"], !href.isEmpty {
                    currentEntry?.link = href
                } else {
                    currentField = "link"
                    textBuffer = ""
                }
            } else if element == "title" {
                currentField = "title"
                textBuffer = ""
            } else if element == "media:content" || element == "media:thumbnail" || element == "enclosure" {
                if currentEntry?.image == nil,
                   let mediaURL = attributeDict["url"] ?? attributeDict["href"],
                   attributeDict["type"]?.lowercased().hasPrefix("image/") != false {
                    currentEntry?.image = mediaURL
                }
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard currentField != nil else { return }
            textBuffer.append(string)
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String,
                    namespaceURI: String?, qualifiedName qName: String?) {
            let element = elementName.lowercased()
            if element == "item" || element == "entry" {
                if let currentEntry {
                    entries.append(currentEntry)
                }
                self.currentEntry = nil
                currentField = nil
                textBuffer = ""
                return
            }
            guard let currentField, currentField == element else { return }
            let value = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if currentField == "title" {
                self.currentEntry?.title = value
            } else if currentField == "link", self.currentEntry?.link == nil {
                self.currentEntry?.link = value
            }
            self.currentField = nil
            textBuffer = ""
        }
    }

    /// The full readable text of one story for its permalink page, plus a
    /// hero image if the page declares one via `og:image`.
    func fetchArticle(url: URL) async -> Article? {
        let webView = Self.makeHeadlessWebView()
        await load(webView, url: url)

        let script = """
        (function() {
            // Cookie-consent banners (OneTrust, Fides, Cookiebot, GDPR
            // notices generally) render their body copy as plain <p> tags
            // too, and often sit ahead of the real article in DOM order —
            // without this, "the first few paragraphs" can just be consent
            // legalese instead of the story.
            //
            // The body/documentElement guard is essential, not defensive:
            // consent libraries stamp their state onto <body> as a class, so
            // Ars ships every article with `fides-overlay-modal-link-shown`
            // on the body element. Matched naively, that marks *every*
            // paragraph on the page as consent boilerplate and the article
            // comes back empty — which is exactly what Ars did.
            var consentSelector = '[class*="cookie" i], [id*="cookie" i], [class*="consent" i], [id*="consent" i], [class*="onetrust" i], [id*="onetrust" i], [class*="gdpr" i], [id*="gdpr" i], [class*="fides" i], [id*="fides" i]';
            function isConsentContainer(el) {
                var hit = el.closest(consentSelector);
                return hit !== null && hit !== document.body && hit !== document.documentElement;
            }
            // Page furniture. Only meaningful outside the article itself: a
            // story's own <header> holds its standfirst, which is text we
            // want, so this is skipped once a specific article root is found.
            function isChrome(el) {
                return el.closest('nav, header, footer, aside') !== null;
            }
            var consentPhrases = [
                'we process your data', 'legitimate interest', 'transparency and consent framework',
                'this website uses cookies', 'this website uses essential cookies', 'manage your data',
                'manage preferences', 'accept all', 'accept cookies'
            ];
            function isConsentText(text) {
                var lower = text.toLowerCase();
                return consentPhrases.some(function(phrase) { return lower.indexOf(phrase) !== -1; });
            }

            // Promotional and recirculation copy that sites append after the
            // story proper: a newsletter pitch, then one-line teasers for
            // unrelated articles. Only treated as a marker in a short
            // paragraph — a story genuinely about newsletters shouldn't be
            // truncated at the word.
            var promoMarkers = [
                'subscribe and interact', 'sign up for our', 'sign up to our',
                'get up to date with our', 'newsletter', 'follow us on',
                'this article originally appeared', 'all rights reserved',
                'terms of use', 'privacy policy', 'daily digest'
            ];
            function isPromo(text) {
                if (text.length > 240) return false;
                var lower = text.toLowerCase();
                return promoMarkers.some(function(marker) { return lower.indexOf(marker) !== -1; });
            }

            function paragraphsIn(roots, trusted) {
                var found = [];
                roots.forEach(function(root) {
                    Array.prototype.push.apply(found, Array.from(root.querySelectorAll('p')));
                });
                return found
                    .filter(function(p) { return !isConsentContainer(p) && (trusted || !isChrome(p)); })
                    .map(function(p) { return p.innerText.trim(); })
                    .filter(function(t) { return t.length > 40 && !isConsentText(t); });
            }

            // The narrowest container that actually holds the story. This used
            // to be the selector list 'article p, main p, p', which reads as a
            // fallback chain but is really a union: the bare `p` matched every
            // paragraph on the page, so each article arrived with the site's
            // "more stories" teasers glued onto the end of it. Trying the
            // candidates in order and stopping at the first with real body text
            // keeps the tail out instead.
            var h1 = document.querySelector('h1');
            var h1Text = h1 ? h1.innerText.trim() : '';
            var ogTitleElement = document.querySelector('meta[property="og:title"], meta[name="twitter:title"]');
            var ogTitle = ogTitleElement ? (ogTitleElement.getAttribute('content') || '').trim() : '';
            // Some small blogs use their site masthead as the only h1 and put
            // the post title in og:title. A masthead link back to / is a
            // reliable signal that the h1 is branding, not the story title.
            var h1IsMasthead = h1 && (
                h1.querySelector('a[href="/"]') ||
                (document.title && document.title.toLowerCase().indexOf(h1Text.toLowerCase()) === 0)
            );
            var titleText = h1Text && !h1IsMasthead ? h1Text : (ogTitle || document.title);
            // Roots paired with whether they're specific enough to trust:
            // a named article container or the <article> holding the headline
            // is the story itself, so its <header> is part of the story. A
            // bare <main> or the whole body is not, and keeps the filter.
            var roots = [];
            // All of them, not the first: the Verge splits a post into one
            // `duet--article--article-body-component` div per block, so
            // querySelector finds a container holding a single paragraph and
            // the search falls through to a root wide enough to sweep in the
            // next post down the page.
            var named = Array.from(document.querySelectorAll('[itemprop="articleBody"], [data-pagefind-body], [data-component="text-block"], [class*="article-body" i], [class*="articlebody" i], [class*="post-content" i], [class*="post__content" i], [class*="entry-content" i], [class*="story-body" i]'));
            if (named.length) roots.push({ els: named, trusted: true });
            // The <article> holding the headline is the story; the others on
            // the page are teaser cards for something else.
            var articles = Array.from(document.querySelectorAll('article'));
            var owning = h1 ? articles.filter(function(a) { return a.contains(h1); })[0] : null;
            if (owning) roots.push({ els: [owning], trusted: true });
            if (articles.length === 1) roots.push({ els: [articles[0]], trusted: true });
            var main = document.querySelector('main');
            if (main) roots.push({ els: [main], trusted: false });
            roots.push({ els: [document.body], trusted: false });

            var paragraphs = [];
            for (var r = 0; r < roots.length; r++) {
                var candidate = paragraphsIn(roots[r].els, roots[r].trusted);
                var total = candidate.reduce(function(sum, t) { return sum + t.length; }, 0);
                if (total >= 400 || (r === roots.length - 1 && candidate.length > 0)) {
                    paragraphs = candidate;
                    break;
                }
            }

            var seen = {};
            var uniqueParagraphs = paragraphs.filter(function(t) {
                if (seen[t]) return false;
                seen[t] = true;
                return true;
            });

            // Everything from the first promo paragraph on is site furniture.
            for (var i = 0; i < uniqueParagraphs.length; i++) {
                if (isPromo(uniqueParagraphs[i])) {
                    uniqueParagraphs = uniqueParagraphs.slice(0, i);
                    break;
                }
            }
            var ogImage = document.querySelector('meta[property="og:image"]');

            // Whatever the page itself claims for a publish time, checked in
            // roughly most-to-least-reliable order: an explicit meta tag,
            // then a <time> element's machine-readable attribute, then
            // JSON-LD structured data (which sites feed to search engines,
            // so it's usually accurate when present at all).
            function extractPublishedAt() {
                var meta = document.querySelector(
                    'meta[property="article:published_time"], meta[name="article:published_time"], ' +
                    'meta[itemprop="datePublished"], meta[name="publish-date"], meta[name="date"], ' +
                    'meta[name="pubdate"], meta[name="parsely-pub-date"], meta[property="og:article:published_time"]'
                );
                if (meta) {
                    var content = meta.getAttribute('content');
                    if (content) return content;
                }
                var timeEl = document.querySelector('time[datetime]');
                if (timeEl) {
                    var datetime = timeEl.getAttribute('datetime');
                    if (datetime) return datetime;
                }
                var scripts = document.querySelectorAll('script[type="application/ld+json"]');
                for (var i = 0; i < scripts.length; i++) {
                    try {
                        var parsed = JSON.parse(scripts[i].textContent);
                        var queue = Array.isArray(parsed) ? parsed.slice() : [parsed];
                        while (queue.length) {
                            var node = queue.shift();
                            if (!node || typeof node !== 'object') continue;
                            if (node.datePublished) return node.datePublished;
                            if (node['@graph']) queue = queue.concat(node['@graph']);
                        }
                    } catch (e) {}
                }
                return null;
            }

            return {
                title: titleText,
                body: uniqueParagraphs.join('\\n\\n'),
                image: ogImage ? ogImage.getAttribute('content') : null,
                publishedAt: extractPublishedAt()
            };
        })();
        """
        guard let row = decodeJSONObject(await evaluateJSON(webView, script: script)),
              let title = row["title"] as? String,
              let body = row["body"] as? String,
              !body.isEmpty else {
            return nil
        }
        let publishedAt = (row["publishedAt"] as? String).flatMap(Self.parsePublishedAt)
        return Article(
            title: title,
            bodyText: body,
            imageURL: row["image"] as? String,
            sourceURL: url.absoluteString,
            publishedAt: publishedAt
        )
    }

    /// Publish-time strings arrive in whatever format the page's own
    /// templating happens to emit — full ISO 8601 with a timezone is the
    /// common case (covered by the two formatter option sets tried here), but
    /// a bare date with no time component (`2026-08-25`) shows up often
    /// enough from `<meta name="date">` tags to be worth a third, simpler
    /// fallback rather than losing the story's date entirely.
    private static func parsePublishedAt(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        let isoWithFractional = ISO8601DateFormatter()
        isoWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoWithFractional.date(from: trimmed) {
            return date
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: trimmed) {
            return date
        }
        let dateOnly = DateFormatter()
        dateOnly.dateFormat = "yyyy-MM-dd"
        dateOnly.timeZone = TimeZone(identifier: "UTC")
        return dateOnly.date(from: String(trimmed.prefix(10)))
    }

    // MARK: - Headless page loading

    private final class LoadWaiter: NSObject, WKNavigationDelegate {
        private let continuation: CheckedContinuation<Void, Never>
        private var didResume = false

        init(continuation: CheckedContinuation<Void, Never>) {
            self.continuation = continuation
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            finish()
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            guard let scheme = navigationAction.request.url?.scheme?.lowercased(),
                  ["http", "https", "about", "data", "file"].contains(scheme) else {
                // Article pages sometimes contain podcast or media links that
                // use a custom URL scheme. The headless extractor must never
                // hand those URLs to macOS and launch another app during a
                // refresh.
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            finish()
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            finish()
        }

        func timeoutIfNeeded() {
            finish()
        }

        private func finish() {
            guard !didResume else {
                return
            }
            didResume = true
            continuation.resume()
        }
    }

    /// A page that hangs (slow ads, a tracking script that never settles)
    /// shouldn't block the whole refresh — fall back to whatever loaded
    /// after a timeout rather than waiting forever.
    private func load(_ webView: WKWebView, url: URL, timeout: TimeInterval = 15) async {
        var waiter: LoadWaiter?
        await withCheckedContinuation { continuation in
            let w = LoadWaiter(continuation: continuation)
            waiter = w
            webView.navigationDelegate = w
            webView.load(URLRequest(url: url))
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                w.timeoutIfNeeded()
            }
        }
        _ = waiter
        await settle(webView)
    }

    /// `didFinish` fires when the document and its subresources are done, which
    /// on a client-rendered site is well before there's anything to extract:
    /// Reddit finishes navigation with an empty body and only then hydrates
    /// (and client-side redirects to its own `?rdt=` URL). Rather than paying a
    /// fixed delay on every page — there are dozens per refresh — this polls
    /// for content and returns the moment it appears, so a server-rendered page
    /// costs one script evaluation and only a shell actually waits.
    private func settle(_ webView: WKWebView, timeout: TimeInterval = 4) async {
        let deadline = Date().addingTimeInterval(timeout)
        let probe = "document.body ? document.body.innerText.length : 0"
        var previousLength = -1
        var unchangedPolls = 0
        while Date() < deadline {
            let length = await withCheckedContinuation { (continuation: CheckedContinuation<Int, Never>) in
                webView.evaluateJavaScript(probe) { value, _ in
                    continuation.resume(returning: (value as? Int) ?? 0)
                }
            }
            if length >= Self.settledTextLength {
                return
            }
            // Two polls in a row with no growth means the page is done
            // rendering whatever it's going to render — waiting out the rest
            // of the timeout wouldn't produce more text. Without this, a
            // page that's simply short (most of them: this only exists for
            // the handful of sites that hydrate client-side) paid the full
            // timeout on every single fetch.
            if length == previousLength {
                unchangedPolls += 1
                if unchangedPolls >= 2 {
                    return
                }
            } else {
                unchangedPolls = 0
            }
            previousLength = length
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    /// Enough rendered text to call a page loaded. Low enough that a genuinely
    /// short page isn't made to sit out the whole timeout, high enough to see
    /// past a shell carrying nothing but a nav bar.
    private static let settledTextLength = 400

    private func decodeJSONArray(_ data: Data?) -> [[String: Any]] {
        guard let data, let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return array
    }

    private func decodeJSONObject(_ data: Data?) -> [String: Any]? {
        guard let data else {
            return nil
        }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// Re-serializes the JS result into `Data` before crossing the
    /// continuation boundary — `Any` from `evaluateJavaScript`'s completion
    /// isn't Sendable, but `Data` is, so this sidesteps the data-race check
    /// entirely instead of suppressing it.
    ///
    /// Also guards with its own timeout, separate from the page-load one:
    /// `evaluateJavaScript`'s completion handler can simply never fire on
    /// some pages (a stuck JS context, a blocked script) — without this, one
    /// such page would hang its whole enrichment batch forever, since a
    /// `TaskGroup` batch only finishes once every task in it does.
    private func evaluateJSON(_ webView: WKWebView, script: String, timeout: TimeInterval = 8) async -> Data? {
        final class ResumeGuard {
            var didResume = false
        }
        let resumeGuard = ResumeGuard()
        return await withCheckedContinuation { continuation in
            func resumeOnce(_ value: Data?) {
                guard !resumeGuard.didResume else {
                    return
                }
                resumeGuard.didResume = true
                continuation.resume(returning: value)
            }
            webView.evaluateJavaScript(script) { result, _ in
                guard let result, JSONSerialization.isValidJSONObject(result) else {
                    resumeOnce(nil)
                    return
                }
                resumeOnce(try? JSONSerialization.data(withJSONObject: result))
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                resumeOnce(nil)
            }
        }
    }
}
