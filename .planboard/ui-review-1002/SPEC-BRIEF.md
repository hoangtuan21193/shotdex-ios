# /spec ui-review-1002 — brief for spec-writing agents

You write the **Design stage** (`/spec`) for intent `docs/_intents/2026-10-02-ui-review-1002.md` (accepted).
Repo: /Users/hoangtuan/Project/shotdex-ios. **Docs only — never edit `.swift`, never commit, never run git that changes state.**
Another agent is working in the same checkout: edit ONLY the files assigned to you.

## Read first
1. The intent (above) — problem groups, constraints, answered questions.
2. `.planboard/ui-review-1002/DECISIONS.md` — the chosen option + proposal for every item ID (Q*, D*, V*, S*, F*, H*, Z*, C*, P*). Chosen = final, do not re-argue. S3 is rejected.
3. `.planboard/ui-review-1002/review/merged.md` (item details, file:line evidence; planboard item ↔ M-ID mapping is in DECISIONS titles) and `review/challenge.md`.
4. `docs/README.md` §4 (doc-writing rules) and `docs/PROCESS.md` §6 (how to write AC). Hard rules from there:
   - Vietnamese prose, present tense, measured numbers (pt, px, %), bullets ≤ 2 lines, paragraphs ≤ 3 lines, ~120 lines per file (split into a part file `NNb-…md` if a file would grow far past that, and register the part in that FS folder's README only if the README is yours).
   - **No code in docs**: no function/property/modifier/enum names, no API syntax. File/type names only once in the doc's first line as a pointer. Framework names allowed when choosing it is the decision (e.g. "BGContinuedProcessingTask của BackgroundTasks" is OK in FS-15 because choosing it IS the decision).
   - No bug history; write the current rule. Keep a reason only if it prevents the next wrong fix, one line: *Vì …*.
5. Constraints to load before writing: `DESIGN.md` (read-only for you), `docs/04-non-functional-design/` (NF-01 perf, NF-02 memory, NF-03 privacy, NF-04 error states, NF-05 devices, NF-06 a11y), `docs/01-basic-design/BD-02-database-design.md` (user data needs own table; indexer rewrites photo_metadata rows).

## For each item assigned to you
- Update the rule text in the owning FS section so the doc describes the NEW behaviour (where a decision overturns an existing rule, rewrite that rule — e.g. FS-06.06 §8, FS-01.08 §6, FS-03.07 §5, FS-15 README "không chạy nền").
- Add acceptance criteria to that FS's AC table (continue its existing numbering and table format; if the FS has no AC table, add a section "Tiêu chí nghiệm thu"). Each AC: **Cho / Khi / Thì**, numeric inputs, exactly one action, observable result, last column = proof: an existing test name / `Tools/ui-drive` script that would prove it, or `⚠️ chưa có` (never empty). Tag each new AC with its planboard ID in the Cho cell or a trailing "(D1)" so /verify can trace it.
- Cover failure paths where relevant: no network, iCloud-only asset, `.limited` access, cancel midway, undo, out of memory, background/foreground.
- Device coverage: iPhone, iPad, Duo inner (951×669, regular width + compact height), Duo cover; iOS 26 and pre-26 where code branches.
- Banned words in AC: mượt, trực quan, hợp lý, đẹp, nhanh (without a number).
- Where the requirement hits a constraint (new colour/token not in DESIGN.md, new column in photo_metadata, height budget on 669pt, memory ceiling, a DESIGN.md rule that must change, a file you may not edit), write `⚠️ CẦN QUYẾT: <question> — phương án a / b, đề xuất <x>` inline. Do not decide it yourself.
- Board work: each changed screen has artboards on canvas "ShotDex App Screens" (`build/design/app/project/<PH_|IP_|DI_|DC_><Screen>.dc.html`, iPhone Library = `Main`). Name the boards affected in a line "Board: …" per section; don't edit boards.
- Check the Swift source for the CURRENT behaviour before writing (read-only) so rule text and AC match reality.

## Files you must NOT edit (dirty in another session's work)
`DESIGN.md`, `docs/02-functional-spec/FS-06-collections/01-tabs-tokens-and-album-management.md`, `FS-06-collections/02-places-map.md`, `FS-06-collections/03-*.md`, `FS-06-collections/09-album-filter-menu.md`, `FS-06-collections/README.md`, anything in `FS-03-photo-editor/` except `07-resize-and-compression.md`, `docs/_plans/*`, other intents.
If one of your items needs a change there, append it instead to `.planboard/ui-review-1002/spec-pending/<your-slug>.md` as: file · section · exact replacement text · item ID.

## Return
Only: list of files changed, number of new AC per file (with their AC numbers), every `⚠️ CẦN QUYẾT` line verbatim with its file, and any pending-ledger entries. Keep it compact.
