# Decisions

Product calls Nina has made beyond SPEC.md. Newest last.

- **Notch on other screens.** The companion sits in the notch on the MacBook screen. When the lid is closed or the notch isn't usable, it moves to the menu bar automatically (approved fallback, SPEC section 6).
- **Quick replies to Claude Code.** Only for sessions started through Hand off. Sessions open in a terminal get Open only, so the terminal never falls out of sync.
- **Notch companion while on an external screen.** The face stays in the notch and also appears in the menu bar of the screen in use.
- **Keyboard shortcut.** Control-Option-C opens and closes the panel.
- **Cursor is automatic, not manual** (changes SPEC section 5). Cursor's documented agent hooks report prompts, replies, questions and stops, so each Cursor agent chat becomes its own ticket. Open focuses the project's Cursor window; Cursor has no link to a single chat. Quick replies stay off for Cursor.
- **Cursor chat names** (changes SPEC section 2). Tickets show the chat's own name from Cursor ("Predictive ordering UI sweep") above Nina's latest message. The name is read from Cursor's database: read-only, one lookup by chat id, names only. If a Cursor update breaks that, tickets fall back to a name made from the chat's first message. Chat contents still come only from the hooks and the transcript file Cursor's hooks point to.
- **Cursor ticket titles** follow Nina's latest message, including words typed after a pasted page element.
- **Working rows show live activity** ("Running npm test · 12s ago"), ticking every second only while the panel is open.
- **A finished reply is Nina's turn** (replaces the earlier rule of done unless it ends on a question). When a Cursor agent finishes, its ticket waits on her, showing the start of the reply, until she presses Done. Prompting the chat again sends it back to Working. Stopping it herself counts as done; an error is blocked.
- **Panel animation.** The panel grows out of the notch and shrinks back into it. Instant when Reduce Motion is on.
- **Manual tickets** start as waiting on you. Still running moves them to Working. (To revisit once Nina has used it.)
- **When a Claude Code session stops.** Same as Cursor: a finished reply waits on Nina until she marks it Done.
- **Hand off to Claude starts Claude Code in Terminal** in the chosen project, with the brief as its first message. Needs Anthropic's Claude Code installer run once; the desktop app's own copy can't be started from outside. The session id is set up front so its ticket is the hand-off ticket.
- **Hand off to Cursor** copies the brief and opens the project. When Nina pastes and sends it, the Cursor feed takes over that same ticket.
- **Ready to delegate** is Brain → Task Tracker, tasks with a new Agent checkbox ticked and Status not Done or Cancelled. Read-only; the Notion token lives in config.local.json, set with `cr set-notion-token`.
- **Hand off remembers a default tool per project**: choosing a project switches to the tool last handed off there.
