# Watch

A macOS app for watching videos saved in Firefox's `tv` bookmark folder.

Create a `tv` folder in Firefox's Bookmarks Toolbar or Menu. Watch imports it
and its subfolders on launch and refresh, with the newest bookmarks first.
Firefox can stay open. No extension is required, and Watch never edits your
Firefox bookmarks.

- **YouTube:** click a title or thumbnail to play inline, including saved
  timestamps. Only one video plays at a time. Switching tabs or pages stops it.
- **Other:** all remaining bookmarks, including channel pages and search results.
- Use the open-original icon beside any title to open it in your browser.
- The trash icon removes an item locally. Removals survive refreshes and
  restarts. Use **Undo** or **Restore removed items** in Settings to bring them back.

Watch keeps its local library at
`~/Library/Application Support/Watch/bookmarkLibrary.json`, available even
when Firefox cannot be read. Duplicate YouTube links appear only once.

Watch opens straight into the feed, with no password or inactivity lock.
Its transparent window icon uses black lines in light mode and automatically
switches to white in dark mode while running in the Dock. Finder uses the
bundled black icon.

Watch does not fetch channel uploads or extract video from other sites.
Some YouTube videos block embedding or require sign-in. Use open-original
for these. Playback uses a separate session from Firefox.

## Build and run

Requires macOS 14 or later and Xcode.

```sh
./Scripts/build-app.sh
open .build/Watch.app
```

## Tests

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --disable-sandbox
```

Set `WATCH_VERIFY_FIREFOX=1` to also test a snapshot of your local `tv` folder.
The normal suite tests bookmark handling with temporary fixtures and checks
transparency in both icon colour variants.
