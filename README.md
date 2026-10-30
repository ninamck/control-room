# Control Room

A macOS app that shows which of my AI agents (Claude, Cursor, Grok, Devin) are waiting on me, lets me answer the simple ones from the notch, and dispatches new work.

Personal project. One user, one Mac, nothing leaves the machine.

- `SPEC.md`: every product rule. Read this first.
- `CLAUDE.md`: how Claude Code should work in this repo.
- `START-HERE.md`: how I kick off and run build sessions.
- `DECISIONS.md`: product calls made after the spec was written.
- `reference/`: approved screen designs as HTML. Open in a browser.

## Status

All nine steps done: ticket store and server (1), companion, panel and quick-add (2), Cursor and Claude Code feeds (3), the board (4), Hand off with Notion (5), Devin and quick replies (6), quiet mode and End of day (7), scheduled tasks (8), and the next hard stop from the calendar (9). Build order is in SPEC.md section 9.

## Running it

Needs Xcode (already on Nina's Mac). In Terminal, from this folder:

```
./build-app
```

That builds Control Room, installs it in your Applications folder (~/Applications), and opens it. It starts by itself when you log in (switch that off in System Settings → General → Login Items). Open it any time from Spotlight.

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

## Calendar

The board and Hand off show NEXT HARD STOP · 23 MIN · Pret weekly: the next busy event today from your Google calendar (the meetings Notion Calendar shows). The panel shows it too when it's within the hour. To connect it, copy the "Secret address in iCal format" from Google Calendar's settings for your calendar, then run `./cr set-calendar-link` and paste it.

## Scheduled tasks

On the board, under ON A SCHEDULE, choose "+ watch one" and add each scheduled task you run in Claude or Grok: name, tool, time, how often, and optionally the link where its results show up. At that time its result lands under "Landed while you were away" with Open, Read it, and Didn't run. It counts in your pink number but never wakes the face. An unread result goes when the next run lands. Before 09:30 the board shows the next scheduled run in place of Done. Results with text open in the reader pane.

## Quiet and End of day

- **Quiet:** press QUIET in the panel's black header and pick 25, 50 or 90 minutes. The face sleeps whatever is waiting; the header shows QUIET UNTIL with +25, +50 and WAKE.
- **End of day** opens by itself at 18:30 (or from END OF DAY on the board): what finished, what still wants you (Open or Tomorrow 9am), and what you keep putting off (Keep, Drop, or Hand off). Close the day puts everything still waiting to sleep until 9am, clears Done, and quiets the companion until 9.

## Hand off

Press **+ HAND OFF** in the panel's footer or **HAND OFF** on the board. Write a brief, pick a tool and a project, press Go (or Enter):

- **Claude** opens Terminal in the project and starts Claude Code with the brief. Needs Claude Code installed once: `curl -fsSL https://claude.ai/install.sh | bash`.
- **Cursor** copies the brief and opens the project in Cursor. Paste and send; the ticket follows that chat.
- **Grok** copies the brief and opens grok.com.
- **Devin** starts a new Devin session with the brief.

Each becomes a Working ticket. Choosing a project switches to the tool you last used there.

**Ready to delegate** lists Task Tracker tasks with the Agent box ticked (not Done or Cancelled). Click one to fill the brief. To connect it: make a Notion integration at notion.so/profile/integrations, run `./cr set-notion-token` and paste its token, then in Task Tracker choose ••• → Connections and add it. Read-only.

## Devin

```
./cr set-devin-token
```

Make a personal access token in Devin (Settings → Devin API → Personal access tokens) and paste it. Control Room checks it with Devin, then looks at your own sessions every 30 seconds.

## Quick replies

When Devin, or a Claude session started from Hand off, finishes on a yes/no or pick-one question, its row in the panel shows answer buttons. Devin gets the answer through its API; Claude gets it typed into its Terminal window (macOS asks once to let Control Room control Terminal). If it can't be sent, the ticket turns Blocked with the reason.

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

## Claude app and Grok Bot chats

Both apps keep their chats on this Mac, and Control Room reads them every 10 seconds (read only; neither format is documented, so an app update can stop a feed until it's adjusted). Claude app task sessions show as working, replied or waiting for permission; scheduled runs land as quiet cards with their text and never wake the face. Grok Bot chats with an unread reply wait on you, and reading the reply in Grok Bot clears them. `./cr chats` shows what Control Room sees, without the chat text.

Plain Claude chats (no folder or tools) live only on Anthropic's servers, so Control Room reads the Claude window itself through macOS Accessibility (System Settings → Privacy & Security → Accessibility → Control Room). Every 4 seconds it looks for the "Stop response" button and the chat's name. A chat it sees replying shows as working; when the reply finishes it waits on you, unless Claude was in front on that chat, and opening the chat clears it. It can only see the chat open in the window: move to another chat mid-reply and the ticket says so. It reads the window's buttons and headings, never the conversation itself, beyond the first line of the latest reply and question.

To see how the window is laid out after a Claude update, create an empty file called `claude-window-probe` in `~/Library/Application Support/Control Room/`; within a few seconds Control Room writes `claude-window-probe.txt` beside it (buttons and headings only).

## Adding a tool feed

A feed is anything that sends tickets to the local server. Every call carries the header `Authorization: Bearer <token from config.local.json>`.

- `POST /tickets` with JSON like `{"tool": "devin", "title": "PR #412: approve to merge", "thread": "transfer-requests", "last_message": "...", "deep_link": "https://...", "source": "automatic", "question_type": {"type": "yes_no"}}`. Only `tool` and `title` are required. New tickets wait on you unless `"state": "working"` is sent.
- `POST /tickets/{id}/{action}` where action is `later`, `park`, `done`, `still-running`, `needs-you`, `blocked` or `drop`.
- `GET /tickets` returns everything, with Later and midnight rules already applied.
- `POST /feeds/cursor` and `POST /feeds/claude-code` take each tool's hook events as they are. `CursorFeed.swift` and `ClaudeCodeFeed.swift` map them to ticket states, with shared wording rules in `FeedText.swift`; a new feed should follow the same shape and add its queue folder to `EventQueue.swift`.

## For Claude Code

Swift package, no outside dependencies.

- `Sources/ControlRoomCore`: ticket model, timing rules (`Rules.swift`), quick-add parsing, store and server.
- `Sources/ControlRoomApp`: the Mac app. `Companion.swift` places the notch window and menu bar fallback; `PanelView.swift` is the panel; `Face.swift` draws the companion's faces from the geometry in `companion/faces/` (see `companion/SPEC-companion.md`); the app icon is `icon/ControlRoom.icns`.
- `Sources/cr`: the command line.
- `Resources/fonts`: Archivo (SIL Open Font License), packaged into the app by `build-app`.
- `swift test` runs the rules tests. `"build/Control Room.app/Contents/MacOS/ControlRoom" --snapshot <folder>` renders the panel and faces to PNGs to compare with `reference/`.
