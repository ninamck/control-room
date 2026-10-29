# Control Room

A macOS app that shows which of my AI agents (Claude, Cursor, Grok, Devin) are waiting on me, lets me answer the simple ones from the notch, and dispatches new work.

Personal project. One user, one Mac, nothing leaves the machine.

- `SPEC.md`: every product rule. Read this first.
- `CLAUDE.md`: how Claude Code should work in this repo.
- `START-HERE.md`: how I kick off and run build sessions.
- `DECISIONS.md`: product calls made after the spec was written.
- `reference/`: approved screen designs as HTML. Open in a browser.

## Status

Step 2 of 9 done: the notch companion with its four faces, the drop-down panel, and quick-add. Tickets are manual only so far. Build order is in SPEC.md section 9.

## Running it

Needs Xcode (already on Nina's Mac). In Terminal, from this folder:

```
./build-app
```

That builds `build/Control Room.app` and opens it. After that you can open it from Finder like any app.

- The face sits in the notch on the MacBook screen. Hover over it or click it to open the panel.
- Control-Option-C opens and closes the panel from anywhere. Escape closes it.
- When the lid is closed, or you're working on another screen, the face also appears in the menu bar. Click it there.
- Quick-add: type "Grok · pricing research" and press Return. Paste a link and it becomes the ticket's Open link. If you don't name a tool, pick one from the squares that appear.

The app runs the local server, so `./cr` works whenever the app is open:

```
./cr add "Recipe variants: modifier group nav" --tool cursor --thread edify-web
./cr list
./cr later 3f2a1b
```

`./cr help` lists every command. `./cr serve` runs the server without the app; don't run both.

## Where things live

- Tickets: `~/Library/Application Support/Control Room/tickets.json`
- Settings and the server token: `config.local.json` in the same folder. Made on first run, never in the repo. `config.example.json` shows its shape.
- The server listens on 127.0.0.1:47821 only and refuses anything without the token.

## Adding a tool feed

A feed is anything that sends tickets to the local server. Every call carries the header `Authorization: Bearer <token from config.local.json>`.

- `POST /tickets` with JSON like `{"tool": "devin", "title": "PR #412: approve to merge", "thread": "transfer-requests", "last_message": "...", "deep_link": "https://...", "source": "automatic", "question_type": {"type": "yes_no"}}`. Only `tool` and `title` are required. New tickets wait on you unless `"state": "working"` is sent.
- `POST /tickets/{id}/{action}` where action is `later`, `park`, `done`, `still-running`, `needs-you`, `blocked` or `drop`.
- `GET /tickets` returns everything, with Later and midnight rules already applied.

## For Claude Code

Swift package, no outside dependencies.

- `Sources/ControlRoomCore`: ticket model, timing rules (`Rules.swift`), quick-add parsing, store and server.
- `Sources/ControlRoomApp`: the Mac app. `Companion.swift` places the notch window and menu bar fallback; `PanelView.swift` is the panel; `Face.swift` holds the four 8×8 faces.
- `Sources/cr`: the command line.
- `Resources/fonts`: Archivo (SIL Open Font License), packaged into the app by `build-app`.
- `swift test` runs the rules tests. `"build/Control Room.app/Contents/MacOS/ControlRoom" --snapshot <folder>` renders the panel and faces to PNGs to compare with `reference/`.
