---
name: new-screen
description: Scaffold a new ShotDex feature screen the way the codebase expects — a Features/<Name>/ folder with an @Observable <Name>Model, a <Name>Screen view, DESIGN.md tokens, the iOS 26 / pre-26 chrome spacer branch, environment injection from AppDependencies, and a test file stub. Arguments: <Name> [tier A|B|C|D] [one-line purpose].
---

# New screen

A screen here is a folder under `ShotDex/Features/<Name>/` with a `*Model`
(`@Observable`, owns query state) and views. State is injected via SwiftUI
environment from the composition root `ShotDex/App/AppDependencies.swift`. Read
`DESIGN.md` first — it decides the tier, which decides chrome, glass, radii and
margins.

## Before writing

1. `DESIGN.md` → which tier the screen is. Tier D (editor-like, full-bleed,
   dark glass) has different margins and its own button style
   (memory: `tierD-glass-button-sync`).
2. Look at the closest existing screen and copy its structure, not its code:
   `Statistics` for a data screen, `Library` for a grid, `Compare` for tier D.
3. Decide what the model needs from `AppDependencies` (queries, store,
   `PhotoLibraryService`) and whether it needs a new `*Queries`/`*Store` type
   (read-only → `Queries`; reads and writes → `Store`; never `DAO`/`Repository`).

## Files

`ShotDex/Features/<Name>/<Name>Model.swift`

```swift
import Foundation
import Observation

@Observable
@MainActor
final class <Name>Model {
    private let queries: <Dependency>Queries

    private(set) var isLoading = false
    private(set) var items: [<Item>] = []

    init(queries: <Dependency>Queries) {
        self.queries = queries
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        // Query on the database queue; the queries type is Sendable.
        items = (try? await queries.<fetch>()) ?? []
    }
}
```

`ShotDex/Features/<Name>/<Name>Screen.swift`

```swift
import SwiftUI

struct <Name>Screen: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var model: <Name>Model?

    var body: some View {
        content
            .navigationTitle(String(localized: "<Title>"))
            .task {
                if model == nil { model = <Name>Model(queries: dependencies.<queries>) }
                await model?.load()
            }
    }

    @ViewBuilder
    private var content: some View {
        if let model {
            ScrollView {
                LazyVStack(spacing: AppTheme.Spacing.medium) {
                    // rows
                }
                .padding(.horizontal, AppTheme.Spacing.screenMargin)
                if #unavailable(iOS 26.0) {
                    Color.clear.frame(height: AppTheme.Chrome.floatingTabBarInset)
                }
            }
        } else {
            ProgressView()
        }
    }
}
```

Use the real token names from `DESIGN.md`/`AppTheme`; the ones above are
placeholders to be replaced, never new constants.

`ShotDexTests/<Name>ModelTests.swift` — only if the model has logic beyond
"call query, store result"; otherwise test the `*Queries` type in
`DatabaseTests` style with `AppDatabase.makeEmpty()`.

## Wire-up

- Route: add to `RootTabView` (a new tab is a product decision — ask) or push from
  an existing screen via `AppNavigation`.
- Dependency: add the `*Queries`/`*Store` to `AppDependencies` and to
  `AppDependencies.preview()`.
- Strings: every user-visible string via `String(localized:)`; the key lands in
  `Localizable.xcstrings` on the next build.
- Spec: add a section to `spec.md` describing the screen (same turn).

## Naming

No Flutter vocabulary (`Widget`, `Scaffold`, `Chip`, `Route`, `Controller`).
Bools read as assertions (`showsHistogram`), latches use `has*`, no `set*`
methods, no abbreviations.

## Finish

`/build`, then `/screens <Name>` on iPhone 26 + 18.6 and, for tier D or any
grid, iPad 13" and the Duo. Run `design-reviewer` and `hig-components` on the
new folder before reporting.
