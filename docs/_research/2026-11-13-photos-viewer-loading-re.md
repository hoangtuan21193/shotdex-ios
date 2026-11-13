# Photos — Library grid, one-up viewer, image loading (reverse-engineering notes)

Target: Photos.app 12 on macOS 27.2.1 and the dyld shared cache it runs on
(`/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_arm64e*`), which carries
`PhotosUI` private (`PU*`, the iOS-heritage one-up viewer and grid) and `PhotosUICore` (`PX*`). Static strings
only (Objective-C selectors, class names); nothing was executed, nothing decompiled. Raw extracts: scratchpad
`px-strings.txt` (5,303 lines) and `pu-strings.txt` (10,062 lines), 2026-11-13.

## 1. Chrome: tap to hide, tap to show

| Evidence | Reading |
|---|---|
| `-[PUBrowsingViewModel setChromeVisible:changeReason:context:]`, `isChromeVisible`, `lastChromeVisibilityChangeReason/Date` | The one-up browser keeps **one** chrome-visible flag in its view model, changed with a reason (user tap, zoom, play…). |
| `-[PUOneUpSettings allowChromeHiding]` | Hiding the chrome is a viewer feature (tap). |
| `-[PUOneUpSettings persistChromeVisibility]` | Hidden **stays hidden** while swiping to the next photo. |
| `-[PUOneUpSettings chromeAutoHideBehaviorOnZoom]`, `chromeAutoHideBehaviorOnPlayButton`, `chromeAutoHideDelay` | Zooming in and pressing Play hide it on their own; video re-hides after a delay. |
| `-[PUOneUpSettings chromeAnimationType]`, `chromeBackgroundAnimationType`, `chromeDefaultAnimationDuration` | Bars and **background** animate separately when chrome toggles. |
| `-[PUBlackOneUpInterfaceTheme photoBrowserChromeVisibleBackgroundColor]`, `-[PUFlatWhiteInterfaceTheme …]` | With chrome visible the background is the theme colour (white in the light theme); hidden = black. |
| `-[PUOneUpSettings hideFloatingInfoPanelWhenHidingChrome]`, `allowStatusBar` | The floating info panel and the status bar go with the chrome. |
| `-[PUOneUpSettings allowDoubleTapZoom]`, `doubleTapZoomFactor`, `doubleTapZoomAreaExcludesBars` | Double tap zooms; single tap waits for it to fail. |

## 2. Image loading in the viewer

| Evidence | Reading |
|---|---|
| `-[PXImageRequester opportunisticImage]`, `-[PXImageRequestOptions opportunisticDegradedImagesToReturn]`, `allowSecondaryDegradedImage`, `useAsyncForFastOpportunisticResult` | A low-res image paints first, then sharper ones replace it — up to two degraded steps; the fast first result can be delivered asynchronously so the swipe never waits. |
| `-[PUOneUpSettings retainProxyUntilZoom]` | The screen-sized proxy is **kept** until the user zooms; the full original is only fetched for zoom. |
| `-[PXGAssetImageCache cacheCGImage:orientation:isDegraded:forRequestID:retainPastCancellation:]` | Decoded `CGImage`s are cached by request, degraded ones marked, and kept past a cancelled request (swipe back is instant). |
| `+[PXMediaProvider(Preheating) preheatQueue]` | Preheating runs on its own queue. |

## 3. Grid

| Evidence | Reading |
|---|---|
| `-[PUPhotosGridViewController preheatAssets]`, `indexPathsForPreheatingInRect:`, `_maximumNumberOfRowsToPreheat`, `_previousPreheatRect`, `beginBatchPreheating`/`endBatchPreheating` | An explicit preheat **rect** ahead of the scroll, a capped number of rows, recomputed only when the offset moved enough, in batches. |
| `-[PUPhotosGridSettings flashDegradedImages]` | Debug switch: degraded thumbnails are a normal, expected first paint. |
| `PXGMetalTextureAtlas maxCapacityForThumbnailSize:pixelFormat:`, `PLManagedAsset(ThumbnailGeneration)` | The modern grid draws thumbnails from Metal texture atlases fed by pre-generated thumbnail tables in the library — not something a third-party app can reach. |
| `-[PXPhotosViewUIInteraction doubleTapGesture]` | Grid has its own double-tap. |

## 4. What this means for ShotDex (inference)

- Single tap must toggle one chrome flag; the flag survives paging; zoom and Play hide it; status bar follows.
- Keep the screen-sized image until zoom (ShotDex already does: zoom triggers `requestFullResolution`).
- Decode before display and keep decoded neighbours, so a swipe never decodes on the main thread.
- Preheat an explicit window, not only UIKit's prefetch callbacks.

## Unknowns
- Exact durations, preheat row counts and degraded-image counts (values live in code / defaults, not strings).
- The iOS app's open/close zoom transition class names did not appear under these patterns.
