---
name: pair-review
description: >
  Interactive paired code review built on the Diffwalk CLI, usually of a
  colleague's PR. The agent slices the diff into review units, opens the diff in
  the browser up front, then takes ONE unit at a time: explains what it does,
  raises its own suspicions from static reading, and STOPS for the operator's
  take. Each unit ends with a joint decision on whether to post a GitHub comment
  (draft shown and explicitly confirmed before posting — never posted
  unprompted), then the loop moves on. The agreed explanations accumulate into
  the walk's explanations.yaml, validated by `diffwalk check` at the end. Use
  when the operator asks for a pair review, 逐块 review, "walk me through the
  diff", or to review changes interactively block by block. Do not trigger for ordinary one-shot /code-review.
---

# Pair review (diffwalk, unit by unit)

A two-party, one-unit-at-a-time review of a Git change. The agent is the
explainer and first reviewer; the operator is the second reviewer. Every round
ends in a joint decision; nothing is posted to GitHub without an explicit yes on
the exact text. This is a dialogue skill — **never review more than one unit
before handing the floor back**.

**The agent's job here is to think and argue, not to produce.** Read the diff
statically, say what it does, name what looks wrong and why. Going heads-down on
a long investigation leaves the operator staring at an idle pane — so
investigate only when a suspicion actually needs proving (§2), say that you are
going, and come back with the answer.

**Usually this is someone else's PR.** The deliverable is PR comments; the
author's code is not ours to edit. Reviewing our own change is the exception —
apply the fix, but **do not commit it mid-review**, so later captures stay on
the same base (`git stash` it if it gets in the way of one). Commit it at the
end, after the tests and checks that change deserves.

## -1. Use the patched diffwalk build, not upstream's

Upstream `diffwalk` (npm/pnpm, as of v0.1.10) lacks two features
this skill relies on: a Wrap toggle for long lines, and visible `change-0NN`
ids next to each step permalink (otherwise it renders the generic text
"LINK", useless for naming a block out loud). Both are merged into
`github.com/shukebeta/diffwalk`, branch `local-both` (combines upstream PRs
minipai/diffwalk#47 and #48, both open/unmerged upstream as of this writing —
check their status before assuming this step is still needed).

One-time setup, any machine:

```sh
git clone https://github.com/shukebeta/diffwalk.git
cd diffwalk
git checkout local-both
npx --yes bun@1.4.1 install   # pin this exact version — see below
npx --yes bun@1.4.1 run build
```

**The bun version must match.** A mismatched bun (e.g. whatever `bun --version`
resolves to locally) silently tree-shakes the report page's web components:
`dist/` builds cleanly, unit tests pass, but every exported diff renders
unstyled — line numbers stacked above the code, no syntax colours, no Wrap
toggle. Always build with the version pinned in that repo's
`.github/workflows/ci.yml` (`bun-version: 1.4.1` there today); if `bun`
itself won't start (e.g. the CPU lacks AVX2), use the copy npx leaves behind
instead of the standalone `bun.exe`.

Then put it on `PATH`, in place of any upstream global install, from the clone:

```sh
npm uninstall -g diffwalk   # or: pnpm rm -g diffwalk
npm link
```

`npm link` creates a `diffwalk` command on `PATH` that points at the clone, so
every shell the agent spawns finds it and a rebuild takes effect without
reinstalling. Check `command -v diffwalk` resolves to it before starting.

Verify the build before trusting an export:
`grep -c 'wrap-form' <exported.html>` should be non-zero.

## 0. Resume before capturing

**Never `inspect` first.** A fresh `inspect` always creates a new walk, so an
unfinished review silently restarts from unit 1 with its agreed text stranded
in the old walk.

```sh
diffwalk walks                                        # existing walks, newest first
cat .diffwalk/<walkId>/capture.json | head -c 400     # source.from.commit / .kind
```

A walk is resumable when its capture still describes the change set under review
— `source.from.commit` matches the base you would capture against, and no new
commits or working-tree edits have landed since `capturedAt`. Then:

```sh
diffwalk use <walkId>
```

and read its `explanations.yaml`: every step whose text starts with
`*Not yet reviewed in this walk.*` is still pending. Report the position out
loud ("resuming walk <id>: 7 of 32 blocks agreed, next is change-010") and
continue the per-unit loop — do not re-explain settled units.

Capture anew (§1) only when no walk matches, or when the code moved on. If it
moved on, say so and carry the still-valid agreed texts over into the new walk
rather than discarding them.

## 1. Capture

Confirm the CLI exists: `command -v diffwalk`. If missing, say so and stop — do
not install or modify shell config without authorization. First use in a repo:
check `.diffwalk/` is ignored — an exported walkthrough is tens of MB and must
never be committed.

Capture the change set matching what the operator means (same semantics as
diffwalk itself):

```sh
diffwalk inspect                          # working tree vs HEAD (default)
diffwalk inspect --staged                 # index only
diffwalk inspect --base main              # working tree vs another base
diffwalk inspect <commit>                 # one commit vs its first parent
diffwalk inspect --from A --to B          # committed range
diffwalk inspect -- src/a.ts              # path-limited (working-tree captures only)
```

Then slice the diff into **review units** — this replaces diffwalk's "agent
authors the whole reading order" step:

```sh
diffwalk changes                          # list all change blocks
```

A change block is a hunk, not a unit of judgement. **One review unit = one
round = one step in `explanations.yaml`**, and it may hold several blocks: a
signature change and its call sites are read together or not at all, while one
dense block can be a unit on its own. Slicing is the agent's call — make it,
state it, don't hand the operator a menu. Group units into named sections in
dependency/logic order (not alphabetical, not file order) and state the plan as
"N blocks in M units, starting with <unit>"; the operator can reorder before
round 1.

Then write the whole agenda into `explanations.yaml` (one step per unit, each
holding the literal `*Not yet reviewed in this walk.*` plus a one-line hint) and
**export and open the walkthrough before round 1** (§3 has the commands). The
operator reads the diff in the browser while you talk; at this point the page
carries the diff alone, which is the point — assessments belong to the rounds,
not to a pre-written verdict that anchors both of you before the discussion.

## 2. Per-unit round

For the current unit:

1. **Read it**: `diffwalk change <id>` for each block in the unit — plus
   `diffwalk file <path> --before` / `--after` when surrounding code matters.
   Never open `capture.json`.
   **Name the unit the way the operator sees it**: `change-0NN` ids are anchors
   in the exported page, never visible labels, so a bare id leaves the operator
   guessing which hunk you mean. Lead with `<file>:<line>` and the changed line
   itself — the browser highlight below points at it, the id alone does not.
   **Scroll and highlight in the open browser** before explaining, so the
   operator is looking at exactly the lines you are about to talk about:
   ```sh
   node "<skill dir>/scripts/focus.mjs" change-0NN --at <path>:42-50,60 [--at <path2>:10:old]
   ```
   `<path>` and line numbers come from `diffwalk change <id>` (new side unless
   `:old`, for deleted lines); `change-0NN` is the unit's first block. The first
   `--at` is scrolled to centre; every `--at` is highlighted, and the previous
   highlight clears. Re-point it whenever the discussion moves to other lines
   within the unit. Add `--reload` after a re-export. It drives the browser
   over CDP, so the terminal keeps focus. Without the §3 browser, say the
   `<file>:<line>` out loud instead.
2. **Explain and assess** in one message:
   - What this unit does, in plain language, pointing at exact lines.
   - Why it is there (or that the purpose is unclear — say so).
   - The agent's own take: correctness, edge cases, risks, naming/style, simpler
     alternatives, questions worth asking the author.
   - Keep it to what static reading of the diff and its immediate context
     supports. Mark anything unproven as a suspicion, in one line, and say what
     would settle it.
3. **Hand over the floor.** End the message and wait for the operator's take.
   Do not pre-write the verdict, do not continue to the next unit.

**Investigate only to settle a suspicion, and settle it.** When one of you wants
it proven — grep the callers, read the UI that supplies the value, query the DB
— go and come back with file:line evidence, then state plainly whether the
suspicion is confirmed or dead. Never close a unit on "this might be a problem":
either it is, with evidence, or it is not, or it needs a decision the two of you
cannot make, which goes in `explanations.yaml` as a named open question.

After the operator responds:

4. **Converge on a verdict for this unit**: agree / disagree with
   reasoning / needs a follow-up. Record it in one line.
5. **Keep the walkthrough current**: replace that step's
   `*Not yet reviewed in this walk.*` with the *agreed* explanation (not the
   debate) in `.diffwalk/<walkId>/explanations.yaml`, keeping the generated
   `captureId`. The placeholder is the resume marker §0 reads, and it keeps
   `diffwalk check` green mid-review. A unit may be revisited later; edit in
   place then.
6. **GitHub comment decision** — ask jointly, default is *not* to post:
   - Nothing actionable → skip. Not every unit needs a comment.
   - Actionable → draft the comment: show its **exact text** and its target
     (PR number + file/line for an inline review comment, or issue # for an
     issue comment). Post **only after the operator confirms that exact
     draft**. Never post from a summary or paraphrase, and never post as a
     side effect of moving on.
7. Move to the next unit and repeat from step 1.

## 3. Export and open the walkthrough

A path alone is not delivery — the operator reads the diff in the browser:

```sh
diffwalk export html --output .diffwalk/<ticket>-walkthrough.html
# Windows: browser top half, terminal bottom half, walkthrough loaded
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill dir>/scripts/split-view.ps1" -Html .diffwalk/<ticket>-walkthrough.html
# Linux (X11 only — needs wmctrl + xdotool): same split, top/bottom
"<skill dir>/scripts/split-view.sh" .diffwalk/<ticket>-walkthrough.html
# macOS: no split script yet — open the same CDP browser by hand
open -na "Google Chrome" --args --remote-debugging-port=9333 --user-data-dir="$HOME/.cache/pair-review-browser" "file://$PWD/.diffwalk/<ticket>-walkthrough.html"
```

(Assumes the `diffwalk` from §-1 — the local-both build renders visible
`change-0NN` ids and a Wrap toggle natively, no post-processing needed.)

The scripts launch a dedicated Chrome / Chromium / Edge on its own profile with
CDP port 9333, which `focus.mjs` (§2) drives through `playwright-core`;
re-running one with another walkthrough reuses that window. If
`scripts/node_modules` is missing, run `npm i` in `scripts/` once. Without a
CDP browser (Firefox, no window manager), just open the file — you lose the
split and the highlight, not the skill. Prefer scripted opening over
`diffwalk view`, which holds a server in the
foreground. Export once before round 1 so the operator has the diff in front of
them; after that a re-export per agreed unit or a single one at the end are
equally fine — it lands at the same path and the operator just refreshes. The
page is a record of the process, not the point of it.

After the last unit:

```sh
diffwalk check        # every captured change explained, every patch still applies
```

Close out in one message: units reviewed, verdicts, comments posted (with
links), follow-ups left open, and the HTML path. If the review produced a fix of
our own, commit it now — tests and checks first — and say in the close-out that
the walk's capture predates that commit. Do not `publish` unless asked.

Stopping mid-review is normal — the walk plus its pending markers *is* the saved
state, so just say which unit is next and leave the walk current.

## GitHub comment mechanics

- Find the PR: `gh pr view --json number,url,headRefName`. If the change has no
  PR, ask where the comment should go (or skip) — do not guess a target.
- Inline PR comment (preferred when the block has coordinates):

  ```sh
  gh api repos/<owner>/<repo>/pulls/<number>/comments \
    -f commit_id=<head sha> -f path=<path> -F line=<n> -f body=<text>
  ```

  `line` is the line number in the file's NEW version for additions/context,
  or use `start_line`+`line` for multi-line spans; for pure deletions use
  `subject_type=FILE` or the OLD-side `line` semantics. Take path/line from
  the change block's captured coordinates.
- Issue comment: `gh issue comment <number> --body-file -` with the text on
  stdin.
- One comment per agreed point; quote the exact lines it refers to so the
  comment survives later pushes.

## Language

The walk is the operator's own reading material, so its prose follows
whatever language the operator speaks in the session. That covers the spoken
explanation each round, the agreed text in `explanations.yaml`, and therefore
the exported HTML.

Everything that leaves this pair and lands in front of the team stays English:
code, comments and XML docs, commit messages, the PR body, and GitHub comments.
Inside prose in another language, reproduce identifiers, file paths, error
strings and quoted code verbatim — never translate a symbol name.

## Tone

Each round is short. Explain, assess, stop. Disagreement is normal — the
operator's call wins on tie; if the two of you cannot converge on a unit's
verdict, record the disagreement in explanations.yaml as an open question and
move on rather than looping.
