# Lightroom Classic — Develop: how editing stays smooth (reverse-engineering notes)

Target: Adobe Lightroom Classic 15.6 on macOS 27.2.1,
`Adobe Lightroom Classic.app/Contents/PlugIns/Develop.lrmodule/Contents/Resources/*.lua` — 204 Lua 5.1 bytecode
files (`\x1bLuaQ`), the Develop module's UI and controller. Static strings only (function names, table keys,
log messages, localisation keys); nothing executed or decompiled. Raw extract in the session scratchpad:
`lr/develop-strings.txt` (74,248 lines), 2026-11-14.

Parameter parity (which sliders exist) is already covered by FS-03.11, FS-03.14, FS-03.15. This note is about the
**feel**: what Lightroom does so that dragging a slider never stutters.

## 1. Two qualities: a proxy while the finger moves, the final render on release

| Evidence (file: string) | Reading |
|---|---|
| `AgCameraRawControllerDirectImageProvider: isInteractive`, `makeProxyImage`, `proxyDimensions`, `_proxyImage` | While a control is being tracked, the loupe draws from a **smaller proxy image**. |
| `AgCameraRawController: kQualityEnums`, `lowQuality`, `isFinalQuality`; provider: `_renderedPreviewQuality`, `_renderedPreviewFidelity`, `_renderedPyramidLevel` | Each render carries a quality and a pyramid level; a low-quality pass during tracking, a final one afterwards. |
| `Skip schedule render for %s because tracking state %s`, `allowGPUAndCPURendersOnTrackingStop` | Expensive (final) renders are **not scheduled while tracking**; they are allowed when tracking stops. |
| `cancelDirtyRenders`, `cancelPendingOrRunningTask( %s )`, `All renders for %s because %s are discarded`, `DirectImageProviderRenderQueue`, `_external_currentRenderSequence` | One render queue per view, sequence-numbered; a new change **cancels** pending and running renders instead of queueing behind them. |
| `_renderedImageAreaInNormalizedCoords`, `_dirtyNormalizedRenderingArea`, `Skip schedule render for %s because not visible` | Only the **visible area** is rendered (zoomed in: just the viewport); hidden views are skipped. |
| `renderOptions.previewQualityLensBlur`, `usePreviewQualityToneMapMask`, `delayFillLightMaskUpdate` | Heavy stages (lens blur, tone-map masks) have a preview quality and are delayed. |

## 2. Histogram: one at a time, after the image

| Evidence | Reading |
|---|---|
| `_startRenderingHistograms.ABORT there is current histogram task`, `_startRenderingHistograms.START/FINISH`, `CameraRawControllerBuildHistogram` | The histogram is computed in its own task, never two at once, and skipped when one is running. |
| `tracking with option key`, `finished tracking with option key held`, `optionKeyPressed` | Holding Option while dragging Exposure/Whites/Blacks shows the **clipping** view for that control. |

## 3. History: one named step per change, a list, snapshots

| Evidence | Reading |
|---|---|
| `DevelopHistoryDataModel: historyForImage`, `AgUndo`, `undoManager`, `changeIdForUndoRedo`, `willUndoChange` | A per-image history list behind undo/redo. |
| `AgCameraRawHistoryStateNaming`: `^1 = ^2`, `Multiple Settings`, `Revert to`, `Snapshot`, `Preset`, `Camera Profile` | Each step has a **readable name** ("Exposure = +0.35"); several settings at once is "Multiple Settings". |
| `dontGenerateHistory`, `deleteLastHistoryStep` | Intermediate states (a drag in progress, a background op) do not become steps. |
| `kBrowserNouns_Snapshot`, `ApplySnapshot` | Named snapshots the user can go back to. |
| `DevelopSettingsFlushSequence: generateNextFlushSequenceForImageId …` | Settings writes are sequenced per image and flushed, not written per tick. |

## 4. Presets preview before they apply; resets are per control and per section

| Evidence | Reading |
|---|---|
| `DevelopLookBrowserDelegate: presetV2LoupePreviewDelay`, `makeRestartablePerformAfterDelayFunction`, `hoveringIndex`, `previewCurrentStyle`, `_lastPreviewIndex` | Hovering a preset shows it on the photo **after a short delay**, restarted as the pointer moves; leaving restores. |
| `DevelopPresetHelper: presetAmount`, `applyPresetToSettingsTable` | Presets apply with an **amount**. |
| `DevelopPanelsCommon: makeResetGroup`, `makeResetMouseDown`; `AgCameraRawController: getSectionResetValues`; `DevelopRightPanelSyncResetButtons: resetButtonText` | Double-click a slider label resets it; a section header resets its group; a Reset button resets all. |
| `_showingBeforeInLoupe`, `beforeAfterLR`, `beforeAfterTB`, `updateWithBeforeSettings for before-in-loupe` | Before/after in the loupe (toggle) and side-by-side (left/right, top/bottom). |

## 5. Caching

| Evidence | Reading |
|---|---|
| `AgLRUCache` (`max_size must be >= 1`) | Bounded LRU caches for renders/negatives. |
| `CameraRawControllerImageInitWorkerTaskManager`, `…OpenNegativeWorkerThreadMethods`, `cleaning up neg on worker thread` | Opening the raw ("negative") and tearing it down run on worker threads; the UI never waits on them. |

## 6. What this means for ShotDex (inference)

- While a control moves: render a **proxy** (≈ half the preview size, heavy stages off), on one serial render
  queue that **drops** stale requests; on release render the final quality once.
- Histogram / clipping: one computation at a time, off the main thread, after the frame.
- Undo: one **named** step per finished gesture; a History list; snapshots.
- Presets / looks: press-and-hold (iOS has no hover) previews on the photo; release-away cancels, tap applies;
  an Amount after applying.
- Reset: double-tap a control's label; a reset per group; Reset all.
- Persist the recipe on a debounce, never per tick.

## Unknowns

- Proxy size ratio, delays (preset preview, flush) — values are not in strings.
- The renderer's own threading inside `CameraRaw.lrtoolkit` (native).
