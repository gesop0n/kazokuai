# kazokuai

A phone-style device at an elderly parent's home talks with them by voice through the Gemini Live API, and the family reads the call summaries in an app.

- `mobile/`: the family's Flutter app.
- `device/`: the Go program on the Raspberry Pi.
- `backend/`: the Go API on Cloud Run.

## Check

`mise run check` must pass before you hand off a commit. CI runs the same task.

## Writing

Write issues, specs, PR bodies, commit messages, and ADRs in Japanese.

- **PR bodies and specs**: polish the Japanese with the `yomiyasu` skill before you publish them.
- **ADRs**: follow "Writing an ADR" in `docs/agents/domain.md`.

## Agent skills

### Issue tracker

GitHub Issues on `gesop0n/kazokuai`, with native sub-issues and blocking. See `docs/agents/issue-tracker.md`.

### Triage labels

The five default labels, each named after its role. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context, with this repo's own ADR format. See `docs/agents/domain.md`.
