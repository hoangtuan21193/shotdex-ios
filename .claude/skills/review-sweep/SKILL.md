---
name: review-sweep
description: Runs the review agents over an area of the app, merges what they find into one ranked queue in REVIEW_QUEUE.md, then works down the queue fixing items one at a time with a build, a test run and a screenshot behind each. Use for "review the whole app and fix what's wrong", for a pre-release sweep, or to resume a queue left half-finished.
---

# Review sweep

Turns "look at everything and fix it" into a queue that survives a session ending.

## Phase 1 — scope

Pick one, from the user's words:

| They said | Scope |
|---|---|
| "review the whole app" | every feature area, in the order below |
| "review the editor" / names a screen | that area only |
| "review my changes" | `git diff main...HEAD --name-only`, plus the screens those files draw |
| "continue" / "keep fixing" | skip to Phase 4 with the existing `REVIEW_QUEUE.md` |

Feature areas, in the order a whole-app sweep takes them (most-used first): Library grid and selection · Photo viewer · Collections and albums · Search · Editor · Compare and cull · Collage · Video Studio · Settings and onboarding · Statistics.

## Phase 2 — dispatch

Launch agents **in parallel, at most four at a time**, each with an explicit file list. Never send two agents the same files in the same wave — their findings collide and you will merge duplicates by hand.

Which agents for which area:

- **Any UI area**: `hig-components` (tier A/B only), `component-consistency`, `a11y-voiceover`.
- **Anything with a layout that is not a plain list**: `device-layout`. It builds and screenshots, so it is slow — give it its own wave.
- **New or reworked flows**: `ux-reviewer`, and `challenger` on the two or three biggest decisions.
- **Grid, layout, index, anything in a scroll path**: `perf-profiler`.
- **Anything touching PHAsset**: `photokit-guard`.
- **Any migration or new stored field**: `data-migration`.
- **Before a release, whole app**: add `copy-consistency` and `design-reviewer`.

Tell each agent the exact files and the device UDIDs it may use. Remind `device-layout` to check `df -h /System/Volumes/Data` first — a build is ~1GB.

## Phase 3 — merge into the queue

Write `REVIEW_QUEUE.md` at the repo root (append if it exists; never silently drop items already there).

Before writing, do the work that makes the queue usable:

1. **Dedupe.** Two agents reporting the same `file:line` is one item, with both sources named.
2. **Drop what `spec.md` already answers.** Grep it. A finding the project argued through and wrote down is closed with a one-line note, not queued.
3. **Rank.** `blocker` (data loss, unreachable control, unconfirmed destructive action, crash) → `should-fix` → `nit`.
4. **Split anything that is really a product decision** into a separate "Needs a decision" section. Renaming a feature, dropping a panel, adding a setting: those wait for the user.

Format:

```markdown
# Review queue — <date>

## Blockers
- [ ] `<path>:<line>` — <what is wrong> → <the fix> _(agent, agent)_

## Should fix
- [ ] …

## Nits
- [ ] …

## Needs a decision
- <question, with the options and what each costs>

## Closed by spec.md
- <finding> — spec §<section> already says <why>
```

Mirror the open items into the session's todo list so progress is visible while you work.

## Phase 4 — fix, one at a time

Work top-down. Blockers and should-fixes are applied without asking; nits are batched and applied last, in one commit.

For each item:

1. Read the code around it. If the finding is wrong, mark it `~~struck~~` in the queue with the reason and move on — an agent being wrong is normal and must be recorded, not silently skipped.
2. Make the smallest change that fixes it.
3. `xcodebuild … build` and fix every error before continuing.
4. **UI change → install, launch, screenshot, look at it.** Both `#available` branches when the code has them (iPhone 17 / iOS 26 and iPhone 16 Pro / iOS 18.6), and the iPad when the change is about layout.
5. Update `spec.md` (and `DESIGN.md` if it is a rule) in the same step.
6. Tick the box. Commit per item, or per small group of related items, with the reasoning in the message.
7. Run the full test suite before the last commit of the batch.

Stop and ask only when: the fix needs a product decision, it would touch more than about six files, or two findings contradict each other.

## Phase 5 — close the loop

When the queue is empty of blockers and should-fixes:

- Re-run the agent that reported the most items, on the files that changed, to confirm they are actually gone.
- Leave `REVIEW_QUEUE.md` in the repo with the closed items struck through and the "Needs a decision" section intact — it is the record of what was considered.
- Report: what was fixed, what was struck and why, what is waiting on a decision.

## Rules

- One fix per commit where it is possible to tell them apart; the message says what the agent saw, not just what changed.
- Never take an agent's word about runtime behaviour. If it says a control is unreachable, reach for it in the simulator first.
- Two agents disagreeing is a finding of its own — put it under "Needs a decision" rather than picking a side quietly.
- A sweep that fixes nothing is a fine outcome and should say which areas were swept clean.
