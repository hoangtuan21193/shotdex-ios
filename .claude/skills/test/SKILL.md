---
name: test
description: Run ShotDex unit tests (all, one class, or one method) and print only the verdict and the failing assertions with file:line. Use after any Domain or Database change and before every commit. Arguments: [Class[/method]] e.g. "DatabaseTests" or "SearchParserTests/testISORange".
---

# Test

Tests live in `ShotDexTests/` and cover Domain and Database only, on in-memory
GRDB (`AppDatabase.makeEmpty()` / `AppDependencies.preview()`). There are no UI
tests in the `ShotDex` scheme; the UI driver is a separate scheme and is not run
here.

## Command

```bash
FILTER="${1:+-only-testing:ShotDexTests/$1}"
xcodebuild -project ShotDex.xcodeproj -scheme ShotDex \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath build/sim \
  -resultBundlePath build/test.xcresult \
  test $FILTER 2>&1 \
  | grep -E "error:|Test Case .* (failed|passed) \(|Executed [0-9]+ tests|TEST (SUCCEEDED|FAILED)|\*\* TEST" \
  | grep -vE "passed \(" \
  | sort -u
```

Remove `-resultBundlePath` before rerunning; xcodebuild refuses to overwrite an
existing bundle (`rm -rf build/test.xcresult`).

## Reading failures

A failing assertion prints as
`/path/File.swift:NN: error: -[ShotDexTests.Class method] : XCTAssertEqual failed: ("a") is not equal to ("b")`.
That line has everything: open the file at NN, read the test, decide whether the
test or the code is wrong. Do not change the expected value to match the output
without saying why the old expectation was wrong.

For a deeper look at one failure:

```bash
xcrun xcresulttool get test-results tests --path build/test.xcresult 2>/dev/null | head -80
```

## When to run what

| Change | Run |
|---|---|
| Domain type (normalizer, parser, geometry, layout math) | its test class, then everything |
| Database store / migration | `DatabaseTests` and every `*StoreTests`, then everything |
| Kit render math | the matching `*Tests` in the kit's coverage (film, colour, brush) |
| View-only change | nothing here; `/screens` instead |
| Before a commit | everything, no filter |

## Rules

- A test class name that does not exist yields `Executed 0 tests` and TEST
  SUCCEEDED. That is not a pass. Check with `ls ShotDexTests | grep -i <name>`.
- New Domain or Database type with no test file is a gap the `test-coverage`
  agent will flag; write the test in the same turn.
- Never delete or `XCTSkip` a failing test to get to green. Fix it or report it
  failing, with the assertion line quoted.
