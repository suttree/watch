# Watch

A native macOS video queue for the web. Track the sites you care about, pull
their feeds, parse linked pages, and find the videos worth your time.

There's no server and no external API in the loop for the watching
experience itself — story extraction and full-article fetching both happen
through a headless `WKWebView` (the same engine as Safari), and the
Naive Bayes ranker trains entirely on-device from your ratings.

## Features

- **Tracked sources** — add any site's URL in Settings; Read pulls headline
  links from its front page on refresh.
- **Extraction that handles real-world markup** — headings with embedded
  kicker text, images/links sitting several DOM levels away from their
  headline, cookie-consent banners masquerading as content, link-aggregator
  sites with no heading markup at all (Hacker News/Pinboard/Bubbles-style),
  and the furniture those aggregators surround stories with — section labels,
  user chips, ad slots, comment counts, bare-domain attribution links —
  and Shadow DOM–rendered posts (Reddit's current UI). The headless webview
  runs with `crypto.subtle`, service workers, and plain workers all stubbed
  out — nothing being extracted needs them, and a worker's WebCrypto is the
  one thing a page-level override can't reach, which is what kept macOS
  asking for a Keychain key. It is given a real 1280×1600 viewport and
  Safari's full user-agent string,
  both of which turn out to be load-bearing: at zero size `innerText` returns
  nothing for unrendered elements and responsive stylesheets hide the main
  content, and WebKit's stock UA (which omits the `Version/… Safari/…`
  suffix) gets an empty shell back from Reddit. Pages that render client-side
  are polled for content after load rather than being read at `didFinish`,
  when a hydrating SPA still has an empty body.
- **A local article cache** — the last 100 fetched articles are cached to
  disk and reused on the next refresh instead of re-fetched, so refreshing
  the same sources repeatedly is fast.
- **Permalink pages** — full extracted article text, with a link back to
  the original. The header reads "Read · Article Title" — a middot between
  the wordmark and the story, rather than the two running together the way a
  plain system window title would. The body is taken from the narrowest container that actually
  holds the story rather than from every `<p>` on the page, and is cut at the
  first newsletter pitch, so articles end where the writing ends instead of
  trailing into a site's "more stories" teasers. Only the headline on a feed
  card is a link — the excerpt is there to be read in place.
- **Feed / All** — two tabs centered at the top of page 1. Feed is a queue:
  the stories whose bolt is lit — rated up, or predicted by the ranker — best
  first, with anything you've read dropped off the list entirely. All is
  everything pulled, newest first — by each story's own stated publish time
  where its page exposes one (`article:published_time`, a `<time datetime>`,
  or JSON-LD `datePublished`). A story without one sorts after every dated
  story rather than being compared against them by fetch time: fetch time is
  always "just now, this refresh," so weighing it against a real publish
  timestamp from hours or days ago meant any source that simply doesn't
  expose a date — a personal blog, a Pinboard bookmark, an aggregator —
  always won the sort regardless of how stale it actually was, crowding out
  properly-dated, genuinely fresh articles. Undated stories still keep a
  stable order among themselves — with read stories dimmed
  rather than hidden, so "what did I already see" stays answerable without a
  tab of its own. An empty Feed shows the horse from the lock and loading
  screens and "Alles klar" in a light-grey letterpress effect. Opening a
  story marks it read; `r` marks the selected card
  read without opening it, and toggles read/unread on a permalink. Until
  you've rated enough for the ranker to score anything, every bolt is lit and
  Feed matches All minus whatever's been read. Read state is a separate axis
  from rating on purpose — reading a story you liked shouldn't have to look
  like disliking it just to clear it off the queue.
- **One rating control** — a lightning bolt on each story, lit or unlit, and clicking
  flips it. Lit means the story belongs in your feed, either because you said
  so or because the ranker predicted it for you; unlit means it doesn't.
  Stories whose text failed to load get one too, since those are often exactly
  what you want to drop. Once you've rated enough
  in both directions, a Naive Bayes classifier (trained on title words,
  a bounded excerpt of article text, and named entities extracted on-device
  via Apple's NaturalLanguage framework) starts scoring stories, which is
  what Feed both filters and orders on. All stays in fetch order regardless.
- **Pagination** — 5 stories per page, with prev/next controls at both the
  top and bottom of the list.
- **A refresh that takes the whole window** — hitting refresh (or pulling
  down from the top of page 1) raises an illustrated loading screen with the
  live source/story counts and a progress bar, then drops you back on a
  settled page 1 when everything has been fetched and scored. A refresh
  empties and refills the feed a source at a time, so this covers a minute
  of churn that used to happen in front of you. "Skip to the feed" gets out
  early if a source is being slow.
- **Keyboard navigation** — vim-style keys throughout. On the feed: `j`/`k`
  move between cards, `h`/`l` page backwards and forwards, Space opens the
  selected card (as does Return), `x` flips its bolt, and `r` marks it read
  without opening it; pull down past the top of page 1 to refresh. On a
  permalink: `j`/`k` step to the next/previous story, `x` flips the bolt, `r`
  toggles read/unread, and Esc or Backspace jumps straight back to the feed. `⌘[`/`⌘]` do browser-style story
  back/forward anywhere.
- **Password lock screen** — the app is protected by a password you choose
  (AES-GCM, HKDF-derived key, no recovery if lost), with the same
  auto-lock-after-10-minutes behavior as Fork. No Keychain involved, so no
  surprise system authorization prompts from an unsigned dev build.
- **Themes** — 25 palettes carried over from the host app, along with its
  pattern vocabulary: stripes, gradients, packed circles, an irregular mesh,
  diamonds, waves, radial bursts, and scattered stars. The pattern paints the
  app icon, seeded so a theme's artwork is recognisably the same in both apps,
  and the window's title bar keeps it too wherever there's real pattern to
  keep — waves, diamonds, packed circles, a mesh. What doesn't survive the
  trip is a ramp of colour: diagonal bands read as one graphic at icon size
  and as a row of hard-edged blocks across a title bar, and a gradient becomes
  a smear, so those palettes get a single flat colour there instead — the
  palette's own signature tone, as authored, so Silver stays pale and Galaxy
  stays dark enough to carry its stars. Everything else is derived from the palette's colour ramp —
  paper, rules, ink — which is what keeps a table that long consistently
  readable; the title-bar ink is measured off the rendered colour so a dark
  one gets white lettering. Read is for reading, so the page itself stays
  pale whatever the theme: even Galaxy is a patterned header and a coloured
  icon over pale paper. Pick one in Settings → Themes, which previews every
  palette and its icon.

## Building

```bash
swift build
./Scripts/build-app.sh   # produces .build/Read.app
open .build/Read.app
```

Requires macOS 14+. This isn't an Xcode project — `build-app.sh` assembles
the `.app` bundle manually (there's no code signing, so expect a Gatekeeper
prompt on first launch).

## Credits

Icons by <a href='https://thenounproject.com/creator/AliceNoir/'>Alice Noir</a>

## Project layout

- `Sources/WatchCore` — pure Swift/Foundation: models, stores, the Naive
  Bayes ranker, entity extraction. No AppKit/WebKit, so it's plain and
  testable in isolation.
- `Sources/WatchApp` — the SwiftUI app: views, the headless-WebKit article
  fetcher, and the theming system.

## Known limitations

- No AI summarization — cards show a real excerpt (opening paragraphs of
  the actual article), not a generated summary. Considered and deliberately
  skipped for cost/latency reasons; see the ranker's docs if you want to
  revisit that.
- The ranker is title/excerpt/entity-based only — no image or full-article
  signal beyond the bounded excerpt.
- No sentiment analysis in the ranker (doesn't fit the bag-of-tokens model
  well, and tone doesn't reliably predict topical interest anyway).
- Extraction heuristics are just that — heuristics. New sites with unusual
  markup may need their own fix, the same way Guardian/404 Media/Ars
  Technica/Bubbles/Pinboard/Reddit each needed one along the way.
