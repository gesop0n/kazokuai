---
name: run-tickets
description: Hand the ready tickets of a spec to implementers and a reviewer in herdr panes, and open one PR per ticket.
disable-model-invocation: true
---

# Run tickets

You are the **conductor** of ADR 0004 (`docs/adr/20261107_development_process.md`). You hand ready tickets to implementer agents, have Codex review the work, and open one PR per ticket. The person merges every PR; you never merge.

The argument is the spec's issue number. Read `docs/agents/issue-tracker.md` for every `gh` operation.

Each ticket `<N>` gets a **work folder**, `${XDG_CACHE_HOME:-$HOME/.cache}/kazokuai/tickets/<N>/`, outside the repository. Every file passed between agents lives there.

## Guardrails

- Never answer an approval, trust, or question dialog for another agent. Notify the person and wait until the agent is idle again.
- Only the person's messages to you are their answers. The input box of an idle Claude Code may show a predicted reply in grey: leave it unsent.
- Keep the person's focus where it is: pass `--no-focus` to every `herdr` command that accepts it.
- Close only the workspaces this skill opened. They carry the label `#<N>`.
- After a wait times out or stalls, inspect the agent with `herdr agent get` and `herdr agent read --source recent-unwrapped --lines 120` before you send anything. Never resend a prompt blindly.
- To notify the person: `herdr notification show "<title>" --body "<what you need>" --sound request`.

## 1. Check the ground

- `HERDR_ENV` is `1`.
- plamo-translate answers: `curl -s -o /dev/null -w '%{http_code}' -X POST http://localhost:30000/mcp` prints anything but `000`. Otherwise stop and tell the person.
- You are in the main checkout (`git gtr go 1`) on `main`, and `git pull` is done.

Done when all three hold. If the main checkout has no `.env` with `GEMINI_API_KEY`, also tell the person: the voice tests need it, and `git gtr new` copies it into each worktree.

## 2. Clean up

- `git gtr clean --merged --yes` removes the worktrees whose PRs are merged.
- `herdr workspace list` shows the workspaces you opened earlier. Close each one whose ticket is closed with `herdr workspace close <id>`.

Done when no worktree or `#<N>` workspace belongs to a closed ticket.

## 3. Pick the frontier

The **frontier** is every open sub-issue of the spec labelled `ready-for-agent` with no open blockers and no `ticket/<N>-*` branch yet (`git gtr list`).

- **First run**: if no PR from a `ticket/` branch has ever been merged, pick one ticket and give it to Claude Code.

  ```bash
  gh pr list --state merged --limit 100 --json headRefName,mergedAt \
    --jq '[.[] | select(.headRefName | startswith("ticket/"))] | sort_by(.mergedAt) | last'
  ```

- **Later runs**: pick up to two tickets, one for Claude Code and one for Grok. If only one is ready, give it to the kind that did not implement the last merged ticket. The kind is in its branch name.

Tell the person the plan in one line (`#12 → Claude Code, #13 → Grok`) and go on.

Done when every picked ticket has an implementer kind, `claude` or `grok`.

## 4. Implement

For each picked ticket, in parallel:

1. Write the ticket to `<work>/ticket.md` and the spec to `<work>/spec.md`, each as its title, body, and comments from `gh issue view`. The implementers do not use `gh`.
2. Create and open the worktree:

   ```bash
   git gtr new ticket/<N>-<kind> --yes        # the hooks run mise trust and codegraph init, and .env is copied
   wt=$(git gtr go ticket/<N>-<kind>)          # not "path": in zsh, path is PATH
   herdr worktree open --path "$wt" --no-focus --label "#<N>"
   ```

   The pane is `.result.root_pane.pane_id`, and the workspace is `.result.workspace.workspace_id`.
3. Start the implementer with rules that block `git push` and `gh`:

   ```bash
   herdr agent start t<N>-impl --kind claude --pane <pane> -- --disallowedTools "Bash(git push:*)" "Bash(gh:*)"
   herdr agent start t<N>-impl --kind grok --pane <pane> -- --deny "Bash(git push*)" --deny "Bash(gh *)"
   ```

   `agent_not_ready` usually means a trust dialog: notify the person, then `herdr agent wait t<N>-impl`.
4. Prompt it without `--wait`:

   > /implement `<work>/ticket.md`. The parent spec is `<work>/spec.md`. Skip the final code-review step: another agent reviews your work. Run `mise run check` before you finish, and commit to the current branch with a Japanese commit message. Do not push. If you need a test that talks through the Mac's microphone or speaker, stop and say so: the person runs those tests, one at a time.

5. `herdr agent wait t<N>-impl`. On `blocked`, or when it asks for a voice test, notify the person and wait again.

Done when the implementer is done, `git -C "$wt" log main..HEAD` lists commits, `git -C "$wt" status --short` is empty, and `mise run check` passes in `$wt`. When any of these fails, send the failure to the implementer and wait again. After two failed rounds, notify the person.

## 5. Review

Codex is the only reviewer (ADR 0006, `docs/adr/20261107_single_reviewer.md`). It reviews every ticket, whoever implemented it, on both axes of the code-review skill. Split a pane off the implementer's pane, start Codex there, and prompt it:

```bash
herdr pane split <pane> --direction down --cwd "$wt" --no-focus   # new pane: .result.pane.pane_id
herdr agent start t<N>-codex --kind codex --pane <new-pane>
```

> Use the code-review skill (`$code-review`). The fixed point is `main`. The spec is `<work>/ticket.md`, and its parent spec is `<work>/spec.md`, comments included. Do not edit any file in the repository. Write your findings as Markdown to `<work>/review-codex-1.md`, then reply with only that path.

Done when Codex has written its file.

## 6. Fix once

When the review holds findings:

1. Prompt the implementer: "Address every finding in `<work>/review-codex-1.md`. Fix it, or write one line in `<work>/replies.md` saying why not. Commit. Do not push." Include answers you already hold, such as the person's decisions.
2. When it is done and the step 4 checks pass again, ask Codex to review again against `main`, read `<work>/replies.md`, and write what remains to `<work>/review-codex-2.md`.

The remaining findings go into the PR body for the person to judge. There is no third round.

Done when Codex has written its second file, or the first review held no findings.

## 7. Open the PR

1. Write the PR body in English in the shape of the `pr` skill, in `<work>/pr_en.md`. Add `Closes #<N>`, the implementer, the reviewer, and a section listing the remaining findings.
2. Turn it into Japanese as `AGENTS.md` says for PR bodies: `mise run translate`, mistranslations fixed against the English, then the `yomiyasu` skill.
3. Push and open the PR. The title is the ticket's title.

   ```bash
   git -C "$wt" push -u origin ticket/<N>-<kind>
   gh pr create --base main --head ticket/<N>-<kind> --title "<ticket title>" --body-file <work>/pr_ja.md
   gh pr checks <pr> --watch
   ```

4. When CI goes red, send the failure to the implementer, check its fix as in step 4, and push again.
5. Notify the person with the PR URL.

Done when the PR is open, CI is green, and the person has the URL.

## 8. Report

Give the person one message: each ticket with its PR URL, CI state, and number of remaining findings. Tell them that merging may unblock more tickets, and that they run `/run-tickets <spec>` again after merging. When every sub-issue of the spec is closed, tell them they can close the spec.
