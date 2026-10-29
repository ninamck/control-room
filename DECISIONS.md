# Decisions

Product calls Nina has made beyond SPEC.md. Newest last.

- **Notch on other screens.** The companion sits in the notch on the MacBook screen. When the lid is closed or the notch isn't usable, it moves to the menu bar automatically (approved fallback, SPEC section 6).
- **Quick replies to Claude Code.** Only for sessions started through Hand off. Sessions open in a terminal get Open only, so the terminal never falls out of sync.
- **When a Claude Code session stops.** If its last message asks Nina something, the ticket becomes needs_you. Otherwise it becomes done.
