# pair-review-skill

A Claude Code (and other agent-skills-compatible) skill for interactive, unit-by-unit
paired code review, built on the [Diffwalk](https://github.com/minipai/diffwalk) CLI.

Instead of one agent writing a whole review up front, the agent and the operator
walk the diff together: one review unit at a time, the agent explains and raises
its own suspicions, then stops for the operator's take. Every unit ends in a joint
verdict; nothing gets posted to GitHub without an explicit yes on the exact text.

## Install

```sh
npx skills add shuke-personal/pair-review-skill --skill pair-review
```

Add `-g` to install globally. From a local checkout:

```sh
npx skills add ./skills/pair-review --skill pair-review
```

Start a new agent session after installing.

## Requirements

This skill needs a build of Diffwalk with two features not yet merged
upstream (Wrap toggle for long lines, visible `change-0NN` step ids) — see
`skills/pair-review/SKILL.md` §-1 for the one-time setup (clone
`shukebeta/diffwalk`, branch `local-both`, build with the pinned bun version).

Auto split-view and auto-scroll-to-anchor are scripted for Windows
(PowerShell) and Linux/X11 (`wmctrl` + `xdotool`). macOS has no script yet —
the skill still works, you just lose those two conveniences.
