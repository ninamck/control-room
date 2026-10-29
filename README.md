# Control Room

A macOS app that shows which of my AI agents (Claude, Cursor, Grok, Devin) are waiting on me, lets me answer the simple ones from the notch, and dispatches new work.

Personal project. One user, one Mac, nothing leaves the machine.

- `SPEC.md`: every product rule. Read this first.
- `CLAUDE.md`: how Claude Code should work in this repo.
- `START-HERE.md`: how I kick off and run build sessions.
- `DECISIONS.md`: product calls made after the spec was written.
- `reference/`: approved screen designs as HTML. Open in a browser.

## Status

Step 4 of 9 done: the notch companion, panel and quick-add (2), Cursor's agents and Claude Code sessions feeding in automatically (3), and the board window (4). Hand off and the Notion list are next, step 5. Build order is in SPEC.md section 9.

## Running it

Needs Xcode (already on Nina's Mac). In Terminal, from this folder:

```
./build-app
```

That builds `build/Control Room.app` and opens it. After that you can open it from Finder like any app.

- The face sits in the notch on the MacBook screen. Hover over it or click it to open the panel.
- Control-Option-C opens and closes the panel from anywhere. Escape closes it.
- When the lid is closed, or you're working on another screen, the face also appears in the menu bar. Click it there.
- The board: press OPEN BOARD at the bottom of the panel, or open Control Room again from Finder or Spotlight. Big counts on the left, cards for everything waiting on you, a grid of what's still working, and "see all" for what's done today. While it's open, Control Room shows in the Dock; close it and the companion carries on.
- Quick-add: type "Grok · pricing research" and press Return. Paste a link and it becomes the ticket's Open link. For Cursor, paste the project folder instead (drag the folder from Finder into the field): Open then brings that project's Cursor window to the front. Cursor tickets never open cursor.com. If you don't name a tool, pick one from the squares that appear.

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

## Cursor's agents

```
./cr install-cursor-hooks
```

Adds Control Room to Cursor's hooks (`~/.cursor/hooks.json`, plus `~/.cursor/hooks/control-room.sh`). From then on every Cursor agent chat becomes a ticket on its own: Working while it runs, Waiting on you when it asks a question (including the Questions prompt), Done when it finishes, Blocked if it errors. Open brings up that project's Cursor window. Other hooks in that file are kept. `./cr remove-cursor-hooks` takes it out again.

Each ticket shows the chat's name from Cursor ("Predictive ordering UI sweep"), your latest message as its title, and, while it's working, what it's doing right now. Chat names are read from Cursor's database, read-only and names only (`CursorChatNames.swift`); if that ever fails, the chat's first message is used instead.

The hook answers Cursor immediately and sends the event in the background, so it never slows an agent down. If Control Room is closed, events wait in `queue/cursor` and are applied when it opens. The last 300 events (names only, no message text) are in `feed-events.log` next to the tickets.

## Claude Code sessions

```
./cr install-claude-hooks
```

Run this yourself in Terminal: it adds Control Room to Claude Code's own settings (`~/.claude/settings.json`, plus `~/.claude/hooks/control-room.sh`), which Claude Code won't edit for itself. Every Claude Code session then becomes a ticket, wherever it runs (the Claude desktop app, Cursor's terminal, Terminal): Working while it runs with what it's doing, Waiting on you when it finishes a reply, asks a question, wants permission or presents a plan, and Done when you mark it or close the session. The session's title from Claude Code names it. Open goes back to the app the session runs in. The hook prints nothing, so it never adds anything to your conversations. `./cr remove-claude-hooks` takes it out again. New sessions pick it up straight away; sessions already open may need restarting.

## Adding a tool feed

A feed is anything that sends tickets to the local server. Every call carries the header `Authorization: Bearer <token from config.local.json>`.

- `POST /tickets` with JSON like `{"tool": "devin", "title": "PR #412: approve to merge", "thread": "transfer-requests", "last_message": "...", "deep_link": "https://...", "source": "automatic", "question_type": {"type": "yes_no"}}`. Only `tool` and `title` are required. New tickets wait on you unless `"state": "working"` is sent.
- `POST /tickets/{id}/{action}` where action is `later`, `park`, `done`, `still-running`, `needs-you`, `blocked` or `drop`.
- `GET /tickets` returns everything, with Later and midnight rules already applied.
- `POST /feeds/cursor` and `POST /feeds/claude-code` take each tool's hook events as they are. `CursorFeed.swift` and `ClaudeCodeFeed.swift` map them to ticket states, with shared wording rules in `FeedText.swift`; a new feed should follow the same shape and add its queue folder to `EventQueue.swift`.

## For Claude Code

Swift package, no outside dependencies.

- `Sources/ControlRoomCore`: ticket model, timing rules (`Rules.swift`), quick-add parsing, store and server.
- `Sources/ControlRoomApp`: the Mac app. `Companion.swift` places the notch window and menu bar fallback; `PanelView.swift` is the panel; `Face.swift` holds the four 8×8 faces.
- `Sources/cr`: the command line.
- `Resources/fonts`: Archivo (SIL Open Font License), packaged into the app by `build-app`.
- `swift test` runs the rules tests. `"build/Control Room.app/Contents/MacOS/ControlRoom" --snapshot <folder>` renders the panel and faces to PNGs to compare with `reference/`.
