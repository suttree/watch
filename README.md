# Watch

A macOS app for watching videos saved in Firefox's `tv` bookmark folder.

Watch syncs the folder when it opens and whenever you refresh. It reads a
temporary copy of Firefox's bookmark database and recent changes, so Firefox
can stay open. It never edits Firefox bookmarks.

The **YouTube** tab contains direct YouTube video bookmarks with thumbnails.
Click a title or thumbnail to play in that row. Saved timestamps are preserved.
Only one player is open at a time. Changing tabs or pages stops playback.
The **Other** tab contains the remaining bookmarks. An open-original icon
beside each title opens the bookmark in your browser. There are no rating
controls, video badges, or separate video pages.

The folder can live in Firefox's Bookmarks Toolbar or Menu. Subfolders are
included. If several folders are called `tv`, Watch selects the one closest
to the toolbar or menu. It checks Firefox's default installed profile first.
Both tabs sort by bookmark date, newest first. Duplicate YouTube links collapse
to the most recently saved one. Old ratings and watched state do not affect
which bookmarks appear or their order.

Channel pages and search results remain ordinary bookmarks. Watch does not
fetch a channel's uploads or extract streams from other sites. YouTube can
restrict embedding, require sign-in, or remove a video. **Open original** is
available beside each title for those cases. Playback uses Watch's own web
session, separate from Firefox.

Watch opens straight into the feed and has no password or inactivity lock.
Previous ratings, watched state, password verification, and website sources
stay in `~/Library/Application Support/Watch` but are not used by the feed.

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
