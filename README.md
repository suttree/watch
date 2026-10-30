# Watch

A macOS app for watching videos saved in Firefox's `tv` bookmark folder.

Create a `tv` folder in Firefox's Bookmarks Toolbar or Menu. Watch imports it
and its subfolders on launch and refresh, with the newest bookmarks first.
Firefox can stay open. No extension is required, and Watch never edits your
Firefox bookmarks.

Each page shows up to 15 items. Watch saves playback position locally every
second and on pause, then resumes the same video when reopened. Until a video
has saved progress, its bookmark timestamp is used. Finished videos restart
from the beginning. Progress is not synced to Firefox or YouTube.

- **YouTube:** click a title or thumbnail to play inline, including saved
  timestamps. Only one video plays at a time. Switching tabs or pages stops it.
- **Sleep and Eat:** use the Sections menu below a video to add it to either
  or both sections. Untick a section to remove it there. Videos stay in All.
  Section choices survive refreshes and restarts.
- **Other:** all remaining bookmarks, including channel pages and search results.
- Use the open-original icon beside any title to open it in your browser.
- During playback, left/right arrows seek five seconds. Use the player's
  fullscreen button to expand the video and Esc to return. The CC button
  toggles captions when available.
- The trash icon removes an item locally. Removals survive refreshes and
  restarts. Removed items move out of All and Other into **Deleted**, as compact
  title rows with an **Undo** button. Saved favourites remain in Favourites.
  Use **Restore removed items** in
  Settings to restore them all. Firefox bookmarks stay intact.

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

## Local web app

Run Watch in your browser with:

```sh
./Scripts/run-web.sh
```

Open <http://127.0.0.1:8765> in your usual browser. Keep the terminal running;
press Control-C to stop the server. Requires Python 3 and Xcode. The launcher
builds the small Firefox importer using the existing WatchCore code.

The first launch reads the native Watch library, favourites, removed items and
Sleep/Eat sections. Web changes are saved separately in `Web/.local/library.json`.
The web app never writes the native library or Firefox bookmarks. Refresh Firefox
imports the current `tv` folder while preserving web favourites and sections.
Search, 15-item pages, favourites, sections, removal and restore work locally.
YouTube playback positions are saved every five seconds and on pause, separately
from the native app. Only one embed stays open at a time.

The server listens only on this computer. Use the exact address above, including
`127.0.0.1`. YouTube and Instagram embeds still contact their respective services.
A regular browser avoids the native app's separate WebKit session, but YouTube
can still reject embeds or require sign-in. The arrow beside a title opens the
original video. Opening the HTML file directly is not supported because embeds
need an HTTP page origin and the library needs the local server.

Run the server checks with:

```sh
python3 -m unittest discover -s Web -p 'test_*.py'
```
