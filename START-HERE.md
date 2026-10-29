# Start here

Five steps to get this into Claude Code and building.

## 1. Make the repo

On github.com, create a new private repository called `control-room`. Tick "Add a README". Clone it to your Mac (GitHub Desktop is fine) or just make the folder.

## 2. Put these files in it

Copy everything in this handover folder into the repo folder, replacing the README:

- `SPEC.md`
- `CLAUDE.md`
- `README.md`
- `.gitignore`
- `reference/` (the seven HTML mockups)

Commit with the message "Spec and designs".

## 3. Open Claude Code in that folder

Terminal, then `cd` into the folder, then `claude`. Or open the folder in the Claude desktop app and start a Claude Code session there.

## 4. Paste this as your first message

> Read CLAUDE.md and SPEC.md fully, then open each file in reference/ and look at it. Then tell me in plain English, in under ten lines, what you're going to build first and how I'll see it running. Don't start coding until I say go. Build order is SPEC.md section 9.

## 5. Each session after that

Start with: "Read CLAUDE.md. We're on step N of SPEC.md section 9. Show me where we got to and what's next."

Say "go" when you agree. Say "show me" whenever you want to see it running. If it asks you a technical question, reply "you decide, tell me why in two sentences".

## When something goes wrong

Paste the error or describe what you saw. Say "fix it and tell me what happened in one sentence". You don't need to understand the fix.
