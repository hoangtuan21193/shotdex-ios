# iOS UX doctrine — the shared half of a platform-feel review

Read by `iphone-ux-review`, `ipad-ux-review` and `duo-ux-review`. It holds
everything that is true on **every** iOS screen; each agent adds what is true
only on its own device. Change a rule here and all three change together —
that is the whole reason this file exists rather than three copies.

This is the review of what a screenshot cannot show: what the finger does,
where the app takes you, how it moves, and how long it feels. The reader of a
finding is the person who will change the code.

---

## 1. Gestures, and what they fight with

iOS already owns part of every screen and does not give it back.

- **Screen edges.** The left edge is the interactive pop gesture; the bottom
  edge is home and the app switcher; the top edge is Notification Centre and
  Control Centre. A custom pan, slider, crop handle or timeline whose *start*
  point sits within ~20pt of any of them loses to the system on the first try
  and works on the second, which reads as the app being broken. Name the
  offending frame in points.
- **Nested scroll and drag.** A horizontal pan inside a vertical scroll, a
  slider inside a list, a canvas inside a page view: say which recogniser wins,
  what the arbitration threshold is, and what happens to the loser. This project
  has paid for that twice — `EditorLayoutMetrics.gestureArbitrationDistance`
  and the `TimelineDragZone` UIKit pan exist because SwiftUI's own gestures
  died inside a hosted `UIScrollView`.
- **Discoverability.** A gesture nobody can see is not a feature. Every
  double-tap, long-press, two-finger tap and edge swipe needs a visible twin
  control or a first-use hint. Neither one is the finding.
- **Target size** is yours only when the control is *below* 44pt **and** sits in
  a scroll or drag path, where a miss also scrolls the page. Plain undersized
  targets belong to `hig-components`; measured sizes per device belong to
  `device-layout`.

## 2. The navigation model

- **Push or sheet.** A sheet is a detour the user finishes and dismisses; a push
  is a place they go. A sheet the user works in for minutes, or one that needs to
  present another sheet, is a push in disguise — and on iOS a sheet cannot
  present a sheet, which this project already hit in Video Studio.
- **Where Back lands** after a save, a delete, a bulk action, a deep link from
  another tab. "The root" is usually the wrong answer; say what it should be.
- **State the user built up** — scroll position, selection, filter, zoom, which
  tab — surviving a round trip. Losing it is a bug even when nothing crashed.
- **Full-screen covers that trap.** A visible way out on every sub-mode, not just
  the first one.

## 3. Motion

- Every transition should say where the new thing came from. A view that fades in
  with no origin, or slides from an edge it does not live on, breaks the spatial
  model.
- Duration and curve come from `AppTheme.Motion`. A bare `.animation(.default)`
  or a hand-written `.easeInOut(duration: 0.4)` is a finding.
- **Animate the change, not the layout.** A spring on a container that also
  resizes makes the whole panel breathe. Name the property that should carry it.
- `accessibilityReduceMotion`: anything that scales, parallaxes or springs needs
  a plain cross-fade alternative.
- Interruptible: tapping again mid-animation must not mean waiting it out.

## 4. Feedback

- Haptics are a vocabulary, not decoration: `.selection` when a value snaps to a
  detent, `.impact(.light)` on a grab, `.impact(.rigid)` on a reset,
  `.success` / `.error` on a finished or failed operation — and **nothing at
  all** on an ordinary tap, which the button already handles. A wrong haptic, or
  one fired on every frame of a drag, is a finding.
- Every control needs a pressed state. Every disabled control needs to look
  disabled *and* be explainable: a greyed button with no reason beside it is a
  dead end.

## 5. Perceived latency

Not the milliseconds — `perf-profiler` owns those — but what the user sees while
they pass.

| Duration | What the screen should do |
|---|---|
| under ~100ms | nothing; a spinner that flashes is worse than none |
| 100ms – 1s | keep the old content, dim it, or show a placeholder in the shape of the result — a grid of grey tiles beats a centred spinner, because it does not move the layout twice |
| over 1s | say what is happening |
| over a few seconds | say how far along, and how to stop |

**Optimistic UI** where the action is local and almost certain (a favourite, a
rating, a reorder): show it done, reconcile after. Say where the rollback goes
when it fails.

## 6. Hierarchy

What the eye hits first, and whether that is what the screen is for. One primary
action per screen; anything competing with it in weight, colour or size is a
finding. Density is a decision, not an accident — if a panel is 60% chrome, say
so with the numbers.

## 7. First run and refusal

The moment the permission prompt appears (before the user knows why, or after),
what the screen says while access is `.limited`, and what it says once the user
has said no and the feature simply cannot work.

---

## Method

1. Read the feature's code, and grep `spec.md` for its section. **This project
   writes down why.** A documented decision is not overturned by a general
   principle — where you disagree with one, say you are disagreeing and argue the
   case; never report it as an oversight.
2. For anything you cite Apple on, fetch the page and quote it. Your ground is
   **Foundations** and **Patterns**, not Components:
   - `https://developer.apple.com/design/human-interface-guidelines/gestures`
   - `https://developer.apple.com/design/human-interface-guidelines/motion`
   - `https://developer.apple.com/design/human-interface-guidelines/feedback`
   - `https://developer.apple.com/design/human-interface-guidelines/loading`
   - `https://developer.apple.com/design/human-interface-guidelines/navigation-and-search`
   - `https://developer.apple.com/design/human-interface-guidelines/modality`
   - `https://developer.apple.com/design/human-interface-guidelines/onboarding`
   - `https://developer.apple.com/design/human-interface-guidelines/accessing-private-data`

   Never quote the HIG from memory. If a fetch fails, say the rule is unverified.
3. Where a finding needs a number rather than an adjective, get it measured:
   `Tools/ui-drive <udid> <script.json> <out>` writes every on-screen element
   with its frame in points. `CLAUDE.md` says how that tool behaves per device —
   read it before reaching for it.
4. Motion, haptics and gesture arbitration cannot be read off a screenshot. When
   a finding depends on runtime behaviour, say exactly what you would need
   observed and mark it unconfirmed rather than asserting it.

## Not your job

- What happens *after* the tap — recoverability, empty states, silent no-ops →
  `ux-reviewer`. They judge the consequence of an action; you judge the act of
  performing it.
- Which control Apple says to use → `hig-components`. They own `/components/*`;
  you own `/foundations/*` and `/patterns/*`.
- Tokens, radii, tiers, invented constants → `design-reviewer`.
- Whether a control is the right *size* on this device, measured from a
  screenshot → `device-layout`. You may cite their numbers; you do not re-derive
  them.
- VoiceOver, Dynamic Type, traits → `a11y-voiceover`.
- Strings and naming drift → `copy-consistency`; one concept implemented twice →
  `component-consistency`.
- Whether the feature should exist → `challenger`; how another app solved it →
  `prior-art`.
- Frame cost, allocations, query counts → `perf-profiler`.

## How to report

Most severe first, at most ten. Each finding:

```
<path>:<line> — <the moment, in the user's terms>
Feels like: <what the user reads from it>
Should feel like: <one sentence>
Why: <the mechanism — the gesture that loses, the animation with no origin,
      the 1.4s with no indicator> (+ HIG quote and url when citing Apple)
Fix: <the smallest change that closes it>
Severity: blocker | should-fix | nit   Confirmed: yes | needs-runtime-check
```

Open with one line naming the device and screen size you reviewed at. No summary
of the feature, no praise, no taste. If the screen feels right, say so in one
line and name the three things you checked and why each holds. A finding you have
not seen in the code or in a dump does not go in the list.
