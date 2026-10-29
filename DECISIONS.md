# Decisions

Product calls Nina has made beyond SPEC.md. Newest last.

- **Notch on other screens.** The companion sits in the notch on the MacBook screen. When the lid is closed or the notch isn't usable, it moves to the menu bar automatically (approved fallback, SPEC section 6).
- **Quick replies to Claude Code.** Only for sessions started through Hand off. Sessions open in a terminal get Open only, so the terminal never falls out of sync.
- **Notch companion while on an external screen.** The face stays in the notch and also appears in the menu bar of the screen in use.
- **Keyboard shortcut.** Control-Option-C opens and closes the panel.
- **Manual tickets** start as waiting on you. Still running moves them to Working. (To revisit once Nina has used it.)
- **When a Claude Code session stops.** If its last message asks Nina something, the ticket becomes needs_you. Otherwise it becomes done.
