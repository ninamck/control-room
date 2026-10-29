# Control Room

A macOS app that shows Nina which of her AI agents are waiting on her, lets her answer the cheap ones without opening the tool, and dispatches new work. One app, two surfaces: a notch companion and a board window. Personal tool, one user, one Mac, no accounts, no cloud.

Owner: Nina McKenna. Written 29 Oct 2026.

## Contents

1. Why this exists and the one rule
2. Scope for v1 and what is out
3. The ticket model
4. States, transitions and timing rules
5. Feeds: how each tool gets tickets in
6. Surfaces and flows
7. Style rules
8. Accessibility
9. Build order
10. Decisions left to engineering
11. Open questions for Nina

---

## 1. Why this exists and the one rule

Nina runs four to ten AI agents at once across Claude (claude.ai and Claude Code), Cursor, Grok and sometimes Devin. Each lives in its own window with its own chats. She loses time checking windows that don't need checking, and misses the ones that do.

Every element in this app must answer one of two questions:

- What is waiting on me?
- Should I start something now?

If a feature answers neither, it doesn't go in. This rule is why Slack, email and a Notion board are out (section 2).

Silence is the default. Agents that are working are never surfaced as notifications. Only things that need a human wake the companion.

## 2. Scope for v1 and what is out

In:

- Ticket store and local server
- Notch companion with four face states and a drop-down panel
- Board window
- Manual ticket add
- Claude Code feed (automatic)
- Devin feed (automatic, polled) and Devin quick replies
- Hand off flow (dispatch work to Claude Code or Devin; open-with-brief for Cursor and Grok)
- Quiet mode
- End of day screen
- Scheduled tasks watch list
- Reader pane for scheduled output
- Next hard stop line from calendar (Google Calendar or macOS Calendar, engineering's choice)
- Ready-to-delegate list from Notion (read-only, one filter)

Out, deliberately:

- Slack and email. Humans waiting on Nina are a different kind of item and would swamp agents. Revisit after two weeks of use.
- A full Notion tracker. Only the "ready to delegate" filtered view.
- Any scheduler UI. Schedules are edited in Claude or Grok. This app only watches.
- Full chat transcripts in the app. Tickets carry the last message and a deep link, nothing more.
- Reading Cursor's internal chat database. Undocumented and breaks on updates. Cursor is manual.
- Dark mode. Light only.
- Rounded corners. See section 7.

## 3. The ticket model

One object type: Ticket.

| Field | Meaning |
|---|---|
| id | internal |
| tool | claude-code, claude-ai, cursor, grok, devin |
| source | automatic (hook or API) or manual (Nina typed it) |
| kind | interactive or scheduled |
| title | agent's first line or what Nina typed |
| thread | project, repo or chat name |
| last_message | last agent message, trimmed to two lines for display, full text kept for the reader pane |
| question_type | none, yes_no, choice (with the options), free |
| deep_link | URL or command that opens the chat or session |
| state | working, needs_you, blocked, done, later, parked |
| state_since | when it entered the current state |
| later_count | how many times Later was pressed |
| schedule | for scheduled tickets: cadence and expected time |

Tools are identity, never colour. A tool is a black square with its initial (A Claude, C Cursor, D Devin, G Grok).

## 4. States, transitions and timing rules

States: working, needs_you, blocked, done, later, parked.

Colour always means state:

- Pink: needs_you under 15 minutes
- Coral: needs_you at 15 minutes or more, or blocked
- Sky: working
- Mint: done
- Paper (no colour): later, parked, scheduled upcoming

Rules:

- working never notifies. It shows as a count and a compact row.
- needs_you turns coral at 15 minutes. One threshold for all tools in v1. Per-tool thresholds are an open question (section 11).
- blocked (agent errored, hook reported failure, API returned an error) is coral and sits above done. Never auto-cleared.
- Later hides the ticket for 30 minutes, then it returns to needs_you with its original state_since (the clock doesn't reset). later_count increments.
- Parked hides a ticket indefinitely. Parked tickets appear on the End of day screen.
- done expires at midnight local time. The Done count resets each day.
- Manual tickets have no automatic state changes. Nina moves them with Done or Still running.
- Scheduled tickets: when a run lands it becomes needs_you with question_type none and action Read. Scheduled output never wakes the companion; it counts in the pink number and sits on the board but the face stays asleep.
- A scheduled run that has not landed 30 minutes after its expected time is marked missed (coral) on the watch list.
- At End of day, tickets with later_count of 3 or more, or parked for more than one day, appear in the coral "Put off and never came back" block. Keep gives them one more day. Drop deletes them. Hand off opens the hand off flow with the title as the brief.
- Tickets left in needs_you at End of day with "Tomorrow 9am" go quiet overnight and wake the companion at 09:00.

Quiet mode:

- Durations 25, 50 or 90 minutes, extendable by 25 or 50, ended early by Wake.
- While quiet, the companion face stays asleep regardless of state. No colour change, no animation.
- On wake, the face shows the current state and the panel header shows the count.

## 5. Feeds: how each tool gets tickets in

All feeds write to one local server that owns the ticket store. Bound to localhost only, with a token the app generates on first run. Nothing leaves the machine.

Claude Code (automatic):

- Claude Code supports hooks. Use the Notification hook (fires when Claude Code needs input or permission) and the Stop hook (fires when it finishes). Each posts to the local server with the session id, working directory, and the last assistant message.
- Working: a session is open and has not fired Notification since its last user turn. Engineering decides how to detect session start (a SessionStart hook if available, or a Stop hook with the transcript path).
- Deep link: resume the session in the terminal, or open the transcript.
- Quick replies: Claude Code can be resumed with a message from the command line, so yes_no and choice replies are allowed.

Devin (automatic):

- Devin has a REST API. Poll sessions at an interval engineering chooses. Map Devin's session status to working, needs_you (status indicates waiting on user or a message addressed to Nina), blocked, done.
- Devin's API accepts a message into a session, so quick replies are allowed.
- Deep link: Devin's session URL.

Claude.ai (manual plus scheduled):

- No feed for personal chats. Nina adds a ticket from the notch panel with a title and pastes the chat URL.
- Scheduled tasks: v1 is manual. The watch list holds the expected time and Nina marks the result read. v2: read the completion email to flip the ticket to landed automatically.
- Quick replies: not available. Open only.

Cursor (manual):

- Nina adds a ticket. Deep link opens Cursor.
- Hand off: opens Cursor with the brief on the clipboard.

Grok (manual):

- Same as Cursor.

Calendar:

- Read only. The app needs one fact: time until the next event marked busy, and its title. Shown as "NEXT HARD STOP · 23 MIN · Pret weekly".

Notion:

- Read only. One database view, filtered to items tagged "agent" (Nina will confirm the exact database and property). Shows title and a one-line meta. Clicking an item fills the Hand off brief. Nothing writes back to Notion in v1.

## 6. Surfaces and flows

### Notch companion

Lives at the top centre of the screen in the notch housing. If engineering judges a true notch window too fragile (multiple displays, menu bar auto-hide), a menu bar extra is acceptable; Nina has approved that fallback. The companion is an 8 by 8 pixel face, yellow, drawn crisp with no anti-aliasing.

Face states:

- Asleep: nothing waiting, or quiet mode. Eyes closed, flat mouth.
- Needs you: at least one needs_you ticket. Eyes open, brows raised.
- Expanded: panel open. Eyes open, mouth open.
- Past 15 minutes: any needs_you ticket is coral. Face turns coral, brows down.

Collapsed, the notch shows only the face. No text.

Hover or click opens the panel:

- Black header: face, "N WAITING ON YOU", oldest wait. In quiet mode the header reads "QUIET UNTIL hh:mm" with +25, +50 and Wake.
- Rows: one per needs_you ticket, oldest first. Each row: time block (pink or coral), tool badge, thread, title, and the actions allowed for that ticket (section 6, Quick replies).
- Below the rows: Working and Done counts side by side.
- Footer: quick-add field (type a title, pick a tool, paste a link) and Hand off.
- Everything in the panel is reachable by keyboard.

### Board window

A normal window. Left column: three stacked colour blocks with big numerals: Waiting on you (pink), Working (sky), Done today (mint). In the morning before 09:30, Done today is replaced by Next scheduled (paper) showing the next run time and name.

Main area:

- Needs a decision: full cards for each needs_you ticket. Time block, tool badge, thread, title, last message (two lines), Open and Later.
- Still working: compact rows, two columns, title and tool plus elapsed. Not clickable beyond Open. No notifications.
- Landed while you were away: when scheduled tickets are present, they appear as cards above Needs a decision with the run time instead of a wait time and Read as the action.
- On a schedule: a watch list, time, name, cadence, status (In N min, Running, Needs you, Unread, Missed), last result. Read only. Copy: "Edit schedules in the tool. This only watches."

Header: wordmark, date and time, Next hard stop block, Add.

### Hand off

Reached from the board header, the notch footer, or End of day.

- Brief: multi-line text. Enter sends, Shift+Enter for a new line.
- Tool: four squares, chosen one is black.
- Where: dropdown of known projects, repos and chats, last used first.
- Helper copy: "Claude and Devin start on their own. Cursor and Grok open with the brief copied."
- Go: for Claude Code, start a session in the chosen directory with the brief. For Devin, create a session via API. For Cursor or Grok, copy the brief and open the app. In all cases a working ticket is created.
- Right column: Ready to delegate from Notion. Clicking an item fills the brief and remembers which Notion item it came from (so v2 can mark it done there).

### Quick replies

Shown on a ticket only when both are true:

- The tool accepts messages (Claude Code, Devin).
- question_type is yes_no or choice.

yes_no shows two buttons, the affirmative in mint. choice shows one button per option, numbered. Every row keeps Open as the fallback. Manual tickets show Done (mint) and Still running instead. Free-text replies are never offered; that's what Open is for.

If a quick reply fails to send, the ticket turns blocked with the error as its last message. No toast, no log.

### End of day

Opens on demand and once automatically at a time Nina sets (default 18:00). Headline states the numbers in words: "Nine finished. Two still want you."

Three blocks:

- Done (mint): list of what finished today, tool per row.
- Still waiting (pink): each ticket with Open and Tomorrow 9am. Only those two options.
- Put off and never came back (coral): tickets with later_count of 3 or more, or parked over a day. Keep, Drop, or Hand off (for tickets that were never started).

Close the day: applies Tomorrow 9am to anything untouched in Still waiting, clears Done, and puts the companion to sleep until 09:00.

### Reader pane

Opens from Read on a scheduled ticket. Shows the full last message in the app's type, no chat chrome. One action: Done. Used only for scheduled output, never for interactive tickets.

## 7. Style rules

Taken from the style sheet artboard. Reference HTML for every screen is in the `reference/` folder of this handover; open the files in a browser.

Colour:

| Name | Hex | Use |
|---|---|---|
| Paper | #F6F3EC | ground |
| Ink | #111111 | all text, lines, shadows |
| Pink | #F8A9C9 | needs you |
| Coral | #E8604F | past 15 min, blocked, missed |
| Sky | #A9C4F2 | working |
| Mint | #BFE3C4 | done, affirmative buttons |
| Yellow | #F8C94A | the companion, Hand off accent |
| Lavender | #CFC9EC | Notion panel header, optional desktop tint |
| Body grey | #4A4640 | secondary text on white or paper only |

Type: Archivo (Google Fonts), four weights.

- Numerals: Black 900, 96 to 160px, letter-spacing -4%.
- Ticket titles: Bold 700, 22px.
- Labels: Black 900, 12px, all caps, letter-spacing +12%.
- Body: Regular 400, 13.5px.

Shape:

- Corner radius 0 everywhere, including inputs and the companion.
- Lines are 1px ink.
- Shadows are solid ink offsets with no blur and no transparency: 3px on buttons, 6px on cards, 8px on the notch panel.
- Background grid: 40px lines in #E8E3D8 on paper. Decorative only; drop it if it reads as noise at real size.

Never: gradients, blur, rounded corners, emoji, dark mode, monospace type.

## 8. Accessibility

- WCAG AA throughout. Body grey #4A4640 is 8.7:1 on white. Ink on every colour block is above 7:1.
- Colours that must be told apart (pink vs coral) also differ in lightness, and the time block always carries the number, so colour is never the only signal.
- Real controls: button, a, input with label. No click handlers on divs.
- Everything in the notch panel and board is keyboard reachable in reading order.
- Respect reduced motion. The companion's state changes are instant swaps, not animations, by default.
- Icon-only controls carry aria-labels.

## 9. Build order

Each step is usable on its own. Stop and show Nina after each.

1. Local server and ticket store. Manual add via a command. Prove the model.
2. Notch (or menu bar) companion: four faces, panel, quick-add. Manual tickets only.
3. Claude Code hooks posting to the server. First automatic feed.
4. Board window with the three blocks and the ticket cards.
5. Hand off for Claude Code and manual tools. Notion list.
6. Devin feed and quick replies.
7. Quiet mode and End of day.
8. Scheduled watch list and reader pane.
9. Calendar line.

## 10. Decisions Claude Code makes

Nina is building this herself with Claude Code and is not a developer. Claude Code owns every technical decision below. It should pick, explain the choice in two sentences of plain English, and move on. It should not present Nina with technical options to choose between.

- Stack. Constraints only: macOS, light mode, local only, no accounts, no cloud, one user. Prefer whatever Claude Code can keep iterating on most reliably over many sessions, with the fewest moving parts to install.
- Notch window vs menu bar extra. Nina prefers the notch and has approved the menu bar as a fallback if the notch proves fragile. Try the notch first.
- How the local server authenticates hook calls, how it persists tickets, and how the app reads Claude Code's session state.
- Polling interval for Devin.
- Calendar source.
- How deep links open each tool.
- Repo layout, build tooling, how the app is launched at login.

Secrets: the Devin API key, Notion token, calendar credentials and the local server token are never committed. They live in a local config file that is in `.gitignore` from the first commit, with an example file committed in its place.

## 11. Decisions Nina makes

Claude Code should ask Nina these when it reaches the relevant step, one at a time, in plain language, with a recommendation:

- Should Hand off remember a default tool per project?
- Should the 15 minute threshold be per tool? Devin PRs can wait longer than a Cursor question.
- Should Drop at End of day delete the ticket or untag it in Notion?
- Should scheduled output expire if unread by a set time?
- Which Notion database and property mark something "ready to delegate"?
- End of day default time (18:00 proposed).
