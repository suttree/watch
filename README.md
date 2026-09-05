# Watch

A macOS app for watching videos saved in Firefox's `tv` bookmark folder.

Watch syncs the folder when it opens and whenever you refresh. It reads a
temporary copy of Firefox's bookmark database and recent changes, so Firefox
can stay open. It never edits Firefox bookmarks.

The **Videos** tab contains direct YouTube video bookmarks with thumbnails.
Click a title or thumbnail to open YouTube's embedded player inside Watch.
Saved timestamps are preserved. Use **Mark watched** when you finish.
The **All** tab includes the other bookmarks, which open on their original
websites. The existing rating controls learn your preferences for Videos.

The folder can live in Firefox's Bookmarks Toolbar or Menu. Subfolders are
included. If several folders are called `tv`, Watch selects the one closest
to the toolbar or menu. It checks Firefox's default installed profile first.
Videos sort by bookmark date, newest first, before ratings and watched state
are applied. Duplicate YouTube links collapse to the most recently saved one.

Channel pages and search results remain ordinary bookmarks. Watch does not
fetch a channel's uploads or extract streams from other sites. YouTube can
restrict embedding, require sign-in, or remove a video. **Open original** is
available below the player for those cases. Playback uses Watch's own web
session, separate from Firefox.

Watch keeps ratings, watched state, and its password in
`~/Library/Application Support/Watch`. The previous website source list stays
on disk but is no longer used by the bookmark feed.

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
The normal suite uses a temporary fixture database.
