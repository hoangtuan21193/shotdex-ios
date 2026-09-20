---
name: spec-sync
description: Diff the current code (or a given commit range) against spec.md and DESIGN.md and list every passage that is now wrong, missing or contradicted, with the replacement text. Enforces the CLAUDE.md rule that a behaviour or architecture change updates spec.md in the same turn. Arguments: [git range | file-or-folder | "all"].
---

# Spec sync

`spec.md` is the product spec and records measurements already taken; `DESIGN.md`
is the design-language source of truth. Both go stale one commit at a time. This
skill finds the drift and writes the fix, rather than leaving "update spec" as a
line in a todo.

## Scope

- No argument or a range like `HEAD~5..HEAD`: `git diff --stat <range>` for the
  files, then the sections below for each.
- A path: every spec passage that names a type, screen or behaviour in that path.
- `all`: full pass; expect an hour and use the section-by-section method.

## Method

1. **Extract claims.** For each spec section touched, list its checkable
   statements: a type name, a number (batch size 200, panel 246pt, first-paint
   slice), a behaviour ("resume via persisted cursor"), a tier assignment, a
   token name.
2. **Verify each against code.**
   - Type names: `grep -rn "struct X\|class X\|actor X\|enum X" ShotDex ShotDexKit`.
     Renamed or deleted = stale.
   - Numbers: find the constant. `spec.md` says 246, `EditorMetrics` says 252 =
     stale (code wins unless the number came from a design decision recorded in
     `DESIGN.md`, in which case the code is tech debt — say which).
   - Behaviours: read the function. Cancel/resume/incremental claims about
     `IndexPipeline` are the ones that drift most.
   - Tokens in `DESIGN.md`: `grep -rn "AppTheme\.\w*" ShotDex | sed ... | sort -u`
     versus the token table; a token used in code and absent from the table is
     an invented constant (also a `design-reviewer` finding); a token in the
     table unused anywhere is dead.
3. **Find the missing.** Features in `ShotDex/Features/*` with no spec section
   at all; migrations in `AppDatabase` newer than the schema description;
   memory files (`~/.claude/projects/.../memory/`) that record decisions the
   spec never absorbed (e.g. the export-compositor choice, the selection-overlay
   architecture).

## Output

For each finding:

```
spec.md §<heading> (line N)
  says:    <quote, one line>
  code:    <file:line, what it actually does>
  change:  <replacement sentence(s), ready to paste>  |  DELETE  |  ADD after §<heading>: <text>
```

Then apply the changes to `spec.md` / `DESIGN.md` unless the user asked for a
report only. Spec edits are prose: keep the existing voice, keep measurements
with their date, and do not delete a recorded measurement — mark it superseded
with the new one beside it.

## Rules

- Where code and `DESIGN.md` disagree, `DESIGN.md` wins and the code is debt:
  do not "fix" the design doc to match code without flagging it.
- Where code and `spec.md` disagree on behaviour, ask which was intended if the
  commit message does not say; a spec is not automatically wrong because code
  moved.
