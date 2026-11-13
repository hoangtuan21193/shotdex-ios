# Photos — Search (reverse-engineering notes)

Target: Photos 12 on macOS 27.2.1 and the dyld shared cache it runs on
(`/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_arm64e*`): `PhotoLibraryServices`
(`PLSearch*`, the indexer), the search index library (`PSI*`), `PhotosUICore` (`PXSearch*`, the UI) and PhotoKit
(`PHSearch*`). Static strings only — Objective-C selectors, class names, SQL literals. Nothing executed or
decompiled. Raw extracts in the session scratchpad: `search-strings.txt` (10,206 lines), `psi-sql.txt`,
`ui-strings.txt`, 2026-11-14.

## 1. The index is precomputed "groups", matched by an FTS5 prefix table

The SQL literals are in the binary verbatim:

| Evidence | Reading |
|---|---|
| `CREATE TABLE IF NOT EXISTS groups(category INT2, owning_groupid INT, content_string TEXT, normalized_string TEXT, lookup_identifier TEXT, score REAL, token_ranges_0 INT8, token_ranges_1 INT8, UNIQUE(…))` | Every searchable **value** (a camera model, a place, a scene, a year, an album title…) is one row — a *group* — with its category and a ranking score. Not one row per photo. |
| `CREATE TABLE IF NOT EXISTS ga(groupid INT, assetid INT, PRIMARY KEY(groupid, assetid))`, `gc(groupid, collectionid)` | Group → photos is a precomputed join table. A match never scans the photo table. |
| `CREATE VIRTUAL TABLE IF NOT EXISTS prefix USING fts5(content='groups', normalized_string, category UNINDEXED, tokenize = '%@')` + `trigger_groups_insert` / `trigger_groups_delete` | Typing searches an **FTS5 index over the group names only** (thousands of rows, not 55k photos), kept in step by triggers. |
| `-[PSITokenizer fts5StringFromString:useWildcard:leadingAnchored:orderInsensitive:]`, `normalizeString:`, `registerFTS5TokenizerForDatabase:` | Each typed word becomes an FTS5 **prefix** term (`can*`), anchored at word starts, word order ignored, text normalised (case, diacritics) the same way on both sides. |
| `SELECT DISTINCT assetid FROM ga WHERE groupid IN matchingIds` | Results = union of the matched groups' photo ids. |
| `-[PSIDatabase _inqNewGroupIdsMatchingFTSString:categories:textIsSearchable:]`, `groupsFromGroupIds:dateFilter:searchResultTypes:` | Query path: FTS → group ids → groups (with counts) → assets, optionally narrowed by a date filter. |
| `-[PSIDatabase _inqExecutePreparedStatement:withCancelableStatementBlock:]`, `_inSearchQueueAsync:` | All queries run on the index's own serial queue, prepared statements, **cancelable** mid-statement when the user types again. |
| `-[PSIGroupCache idOfGroupWithText:identifier:category:owningGroupId:]`, `-[PSIDatabase resetGroupsCache]` | Group lookups are cached in memory. |
| `PLSearchIndexingIncrementalUpdateEngine processJobObjectIDs:entity:library:completion:`, `pause`, `resumeWithLibrary:` | The index is updated **incrementally** per changed photo, in batches, pausable; a full rebuild engine exists separately. |
| `PXSearchSettings indexingBannerPercentageThreshold`, `_formatIndexingStatusAlertMessageForRemainingCount:isPaused:…` | While indexing is incomplete, search says so (banner with remaining count) instead of silently missing photos. |

## 2. Typing produces suggestions (tokens), not just a result grid

| Evidence | Reading |
|---|---|
| `PSISuggestionQuery`, `PSISuggestionRanker rankedSearchSuggestionsFromSuggestionCandidates:suggestionType:queryAssetCount:queryCollectionCount:suggestionLimit:suggestionQuery:` | Each keystroke asks for **suggestions**: matched groups, ranked, capped. |
| `_countBasedPriorityForSuggestion:queryAssetCount:…`, `_percentOverlapWithCompletionText:…minPercentOverlapForPrioritization:`, `suggestionScoreForIndexCategory:`, `_orderedSuggestionCategoryTypes` | Ranking = category order + how much of the name the typed text covers + how many photos the suggestion has. |
| `PHSearchSuggestionTypeCompletion`, `PHSearchQuerySuggestionPropertyAssetCount`, `…KeyAssetUUIDs`, `…QueryText` | A suggestion row shows its **photo count** and a **key photo** thumbnail. |
| `PXSearchToken initWithText:image:representedObject:`, `PXSearchActiveSearch initWithSearchText:searchTokens:libraryScope:`, `searchTokens`, `hasSearchText` | Picking a suggestion turns it into a **token** (chip with an image) in the field; the active search is *tokens + leftover free text*. Several tokens narrow (AND). |
| `PHSearchSuggestionCategoriesType…` (49 values): `CameraMakeAndModel`, `Raw`, `LivePhoto`, `Panorama`, `Portrait`, `LongExposure`, `Burst`, `Slomo`, `Timelapse`, `Screenshot`, `Selfie`, `Favorite`, `Edited`, `Filename`, `Flash`, `Album`, `Locations`, `Dates`, `Trip`, `People`, `Pet`, `Scene`, `OCRText`, `AssetRating`, `Video`… | Categories a suggestion can be. Camera make/model and capture kinds are first-class search categories. |
| `PLSearchIndexCategory…`: `Year`, `Month`, `Season`, `Holiday`, `PartOfDay`, `DayOfWeek`, `Country`, `Locality`, `POI`, `FileType`, `Keyword`, `Title`, `Description`, `CameraMakeAndModel`… plus `…Synonym` variants; `PSISynonym`, `PLSearchIndexCountrySynonymProvider` | Dates are indexed as words ("2024", "June", "summer", "evening", "weekend"); places at every level; synonyms map other words to the same group. |
| `PSIDateFilter initWithStartDateComponents:endDateComponents:`, `displayString` | A date phrase becomes a date-range filter token. |
| `PXSearchSettings enableAutoCorrect` | Misspellings are corrected. |

## 3. The empty field is not empty

| Evidence | Reading |
|---|---|
| `CREATE TABLE IF NOT EXISTS initial_suggestions (date_last_used REAL, first_group_id INT, second_group_id INT, template_key TEXT, …)`, `PSIInitialSuggestion dateLastUsed`, `PHSearchQuerySuggestionTypeInitial`, `PHSearchQuerySuggestionTypeRecent` | Before typing, search shows **initial suggestions** (built from templates over the library's own groups) and **recent searches**, ordered by last use. |
| `+[PHSearchQuerySuggestion initialSearchQuerySuggestionsForPhotoLibrary:suggestionLimit:minimumResultCountPerSuggestion:…]` | Initial suggestions skip anything with too few photos. |

## 4. Results arrive in batches, best first

| Evidence | Reading |
|---|---|
| `PXSearchSettings enableBatchedSearchResults`, `batchedSearchResultInitialBatchSize`, `batchedSearchResultSubsequentBatchSize` | The result grid fills with a small first batch, then the rest — first paint does not wait for the full set. |
| `shouldSplitResults`, `standardNumberOfTopAssetRows`, `maxNumberOfTopAssetRows`, `maxNumberOfTopAssetColumns`, `disableTopAssetCuration` | Results split into **Top** (a few curated rows) and **All**. |
| `-[PSIDatabase mostRecentSortedAssetIdsWithLimit:]`, `_inqAssetUUIDsForAssetIds:range:creationDateSorted:` | Asset ids are paged by range, newest first. |
| `PLSearchThumbnailMap thumbnailIdentifierForLookupIdentifier:` | Each group stores a ready thumbnail id, so a suggestion row needs no query to show its picture. |
| `PXSearchQueryMatchInfo …ocrTexts:…queryEmbeddings:` | Matching also uses on-device text recognition and embeddings (semantic). |

## 5. What this means for ShotDex (inference)

- Precompute search *values* (camera, lens, focal, ISO band, aperture, year/month, place, album, file type, capture
  kind, keyword) into a small group table with photo counts; match typing with an FTS5 prefix query over that table,
  not a `LIKE '%…%'` over every photo.
- Each keystroke shows ranked suggestions with count and key photo; choosing one makes a token; tokens AND together.
- Query on a background queue and cancel the previous query on the next keystroke.
- Empty field: recent searches + a few library-derived suggestions.
- Results: first batch paints immediately; optional Top rows.
- Keep the index incremental (rows change when the indexer rewrites a photo) and say when indexing is incomplete.

## Unknowns

- Batch sizes, ranking weights, Top-row counts (values live in defaults/code, not strings).
- The tokenizer's exact normalisation (name is a format argument, `'%@'`).
- iOS search UI layout: class names were Swift-mangled; layout taken from the iOS 26 Photos app as shipped, not
  from this extract.
