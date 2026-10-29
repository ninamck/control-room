# Control Room

A macOS app that shows which of my AI agents (Claude, Cursor, Grok, Devin) are waiting on me, lets me answer the simple ones from the notch, and dispatches new work.

Personal project. One user, one Mac, nothing leaves the machine.

- `SPEC.md`: every product rule. Read this first.
- `CLAUDE.md`: how Claude Code should work in this repo.
- `START-HERE.md`: how I kick off and run build sessions.
- `DECISIONS.md`: product calls made after the spec was written.
- `reference/`: approved screen designs as HTML. Open in a browser.

## Status

Step 1 of 9 done: the ticket store and local server, driven from the command line. Build order is in SPEC.md section 9.

## Running it

Needs Xcode (already on Nina's Mac). In Terminal, from this folder:

```
./cr serve
```

Leave that window open. In a second Terminal window:

```
./cr add "Recipe variants: modifier group nav" --tool cursor --thread edify-web
./cr list
./cr later 3f2a1b
```

`./cr help` lists every command. The first run takes a minute to build.

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

Swift package, no outside dependencies. `Sources/ControlRoomCore` holds the ticket model, timing rules (`Rules.swift`), store and server; the app will host the same server from step 2. `swift test` runs the rules tests.
