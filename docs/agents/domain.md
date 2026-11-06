# Domain Docs

How the engineering skills should consume and write this repo's domain documentation.

## Before exploring, read these

- **`GLOSSARY.md`** at the repo root.
- **`docs/adr/`**: read ADRs that touch the area you're about to work in. `docs/adr/README.md` lists them all.

If `GLOSSARY.md` doesn't exist, **proceed silently**. Don't flag its absence; don't suggest creating it upfront. The `/domain-modeling` skill (reached via `/grill-with-docs` and `/improve-codebase-architecture`) creates it lazily when terms actually get resolved.

## File structure

Single-context repo:

```
/
├── GLOSSARY.md
├── docs/adr/
│   ├── README.md                                  ← format rules and the ADR list
│   ├── 20261105_mobile_development_policy.md      ← ADR 0001
│   └── 20261106_device_backend_architecture.md    ← ADR 0003
├── mobile/
├── device/
└── backend/
```

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use the term as defined in `GLOSSARY.md`. Don't drift to synonyms the glossary explicitly avoids.

If the concept you need isn't in the glossary yet, that's a signal: either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/domain-modeling`).

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR 0003 (device and backend architecture), but worth reopening because…_

## Writing an ADR

This repo's ADR format replaces the one in the `domain-modeling` skill. When to offer an ADR stays as that skill says.

- **Format**: `docs/adr/README.md` defines the file name (`YYYYMMDD_<title>.md`), the Status values, and the sections (Nygard: Status, Context, Decision, Consequences with Pros and Cons). Copy the shape of the latest ADR.
- **Number**: the title is `# ADR <NNNN>: <title>`. Take the highest number in `docs/adr/` and add one.
- **List**: add a row to the table in `docs/adr/README.md`.
- **Language**: write the ADR in English first, translate it with `mise run translate`, fix the mistranslations against the English, then polish the Japanese with the `yomiyasu` skill. Commit only the Japanese.
- **Superseding part of an ADR**: leave the old ADR's Status as it is, and name the replaced decision in the new ADR's Context.
