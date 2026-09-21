---
name: review-sweep
description: Reviews AND fixes. Runs the review agents over an area, merges what they find into a ranked queue in REVIEW_QUEUE.md, then implements every blocker and should-fix itself — build, full test run and a simulator screenshot behind each one, one commit per item — and re-runs the agents at the end to prove the findings are gone. A sweep that only reports has not finished. Use for "review the whole app and fix what's wrong", pre-release sweeps, or to resume a half-finished queue.
---

# Review sweep

Turns "look at everything and fix it" into a queue that survives a session ending —
and then **empties the queue**.

**This skill is not finished when the findings are written down.** Reporting is
Phase 3 of five. The deliverable is fixed code with the tests and screenshots
that prove it, and a queue whose blockers and should-fixes are all ticked or
struck through with a reason. If you stop after the review, you have done a
third of the job.

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
- **Anything with a custom gesture, a new sheet or push, an animation, a loading state, or a first-run/permission moment**: the platform-feel trio — `iphone-ux-review`, `ipad-ux-review`, `duo-ux-review`. One per screen size, and they are cheap to run together because each reads the same doctrine and then only its own device. Pair them with `ux-reviewer` rather than instead of it — they judge the act, it judges the consequence — but give them different files in the same wave.
- **Grid, layout, index, anything in a scroll path**: `perf-profiler`.
- **Anything touching PHAsset**: `photokit-guard`.
- **Any migration or new stored field**: `data-migration`.
- **Before a release, whole app**: add `copy-consistency` and `design-reviewer`.

Tell each agent the exact files and the device UDIDs it may use. Remind `device-layout` to check `df -h /System/Volumes/Data` first — a build is ~1GB.

Two agents in `.claude/agents/` are deliberately not dispatched here: `prior-art` belongs to Phase 4 (it proposes fixes, it does not find problems), and `lightroom-parity` is feature planning, not review — run it on its own when deciding what to build next.

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

## Phase 4 — fix, one at a time (the main phase)

Work top-down and **keep going until the blockers and should-fixes are gone**.
They are applied without asking; nits are batched and applied last in one
commit. Do not hand the queue back half-done because it is long — if the
session is running out, leave the queue ticked as far as it got and say exactly
where it stopped.

For each item:

1. Read the code around it. If the finding is wrong, mark it `~~struck~~` in the queue with the reason and move on — an agent being wrong is normal and must be recorded, not silently skipped.
2. **If the finding is clear but the fix is not, run `prior-art` on it first.** It answers "what should this look like instead" by reading how Photos, Lightroom, Halide, Darkroom, CapCut or Procreate solved the same thing, and comes back with numbers, the tier it lands in and what it costs. Use it when the item is about the *shape* of something — a control that is in the wrong place, an interaction with no obvious replacement, an empty state, a flow that needs restructuring — and batch every such item from the queue into one `prior-art` call rather than one per item. Skip it when the fix is mechanical (a missing accessibility label, a hardcoded constant that should be a token, an off-by-one frame).
3. Make the smallest change that fixes it.
4. `xcodebuild … build` and fix every error before continuing.
5. **UI change → install, launch, screenshot, look at it.** Both `#available` branches when the code has them (iPhone 17 / iOS 26 and iPhone 16 Pro / iOS 18.6), and the iPad when the change is about layout.
6. Update `spec.md` (and `DESIGN.md` if it is a rule) in the same step.
7. Tick the box. Commit per item, or per small group of related items, with the reasoning in the message.
8. Run the full test suite before the last commit of the batch.
9. Re-read the item in the queue and tick it only when the fix is *observed*, not when the code compiles.

Stop and ask only when: the fix needs a product decision, it would touch more than about six files, or two findings contradict each other. A `prior-art` proposal that changes what the feature *is* — not just how it is drawn — goes to "Needs a decision", not straight into the code.

## Phase 5 — close the loop, with proof

When the queue is empty of blockers and should-fixes:

- **Re-run the agents that reported them**, on the files that changed, and treat any finding that comes back as not fixed. This is the step that separates "I changed the code" from "the problem is gone".
- Run the full test suite once more, and screenshot each screen that was touched on every device the change claims to affect.
- Leave `REVIEW_QUEUE.md` in the repo with the closed items struck through and the "Needs a decision" section intact — it is the record of what was considered.
- Report: what was fixed, what was struck and why, what is waiting on a decision.

## Rules

- One fix per commit where it is possible to tell them apart; the message says what the agent saw, not just what changed.
- Never take an agent's word about runtime behaviour. If it says a control is unreachable, reach for it in the simulator first.
- Two agents disagreeing is a finding of its own — put it under "Needs a decision" rather than picking a side quietly.
- A sweep that fixes nothing is a fine outcome **only** when nothing was found; say which areas were swept clean.
- Never end a sweep with an open blocker. If one genuinely cannot be fixed here — it needs a product decision, or an API that does not exist — move it to "Needs a decision" with the reason, so the queue's blocker list is empty and the reason is on the record.
