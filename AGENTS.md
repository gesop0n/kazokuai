# kazokuai

A phone-style device at an elderly parent's home talks with them by voice through the Gemini Live API, and the family reads the call summaries in an app.

- `mobile/`: the family's Flutter app.
- `device/`: the Go program on the Raspberry Pi.
- `backend/`: the Go API on Cloud Run.

## Check

`mise run check` must pass before you hand off a commit. CI runs the same task.

## Writing

Issues, specs, PR bodies, commit messages, and ADRs are published in Japanese.

- **Specs, tickets, and PR bodies**: write them in English, translate with `mise run translate <en.md> <ja.md>`, then compare the Japanese with the English and fix every mistranslation. Polish specs and PR bodies with the `yomiyasu` skill; publish tickets without it.
- **English original**: end every spec and ticket with the English original in `<details><summary>英語の原文</summary>`, a blank line, the English, a blank line, and `</details>`.
- **Commit messages**: write them directly in Japanese.
- **ADRs**: follow "Writing an ADR" in `docs/agents/domain.md`.
- **plamo-translate unreachable**: stop and tell the person. They start the server on `localhost:30000`.

## Agent skills

### Issue tracker

GitHub Issues on `gesop0n/kazokuai`, with native sub-issues and blocking. See `docs/agents/issue-tracker.md`.

### Triage labels

The five default labels, each named after its role. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context, with this repo's own ADR format. See `docs/agents/domain.md`.
