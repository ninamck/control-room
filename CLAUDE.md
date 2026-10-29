# Working on Control Room

Read `SPEC.md` before doing anything. It holds every product rule. The HTML files in `reference/` are the approved designs; open them in a browser and match them.

## Who you are working with

Nina is the product owner and the only user. She is not a developer and will not read or edit code by hand. She makes product decisions; you make every technical decision.

- Explain technical choices in two plain sentences, then proceed. Do not offer her a menu of stacks, libraries or patterns.
- When a product question in SPEC.md section 11 comes up, ask her one question at a time with your recommendation.
- Stop and show her something running after each step in SPEC.md section 9. Tell her exactly what to click to see it.
- If something in the spec can't be built as written, say so plainly, propose the closest thing, and wait for her yes.
- Never say "stakeholders", "end users", "leverage" or "robust". Write like a person.

## Rules that are easy to break

- Colour means state, never tool. Tools are black squares with an initial.
- Zero border radius everywhere. Solid offset shadows, no blur.
- Working agents never notify. Only needs_you and blocked do.
- Scheduled output never wakes the companion.
- The app never writes to Notion, Slack, email or calendar in v1.
- No secrets in the repo. Config lives in a gitignored local file with a committed example.
- Light mode only.

## Repo hygiene

- Commit after each working step with a one-line message a non-developer can read ("Notch panel shows waiting tickets").
- Keep README.md current: what it does, how to run it, how to add a tool feed.
- Don't add dependencies for things the platform already does.
