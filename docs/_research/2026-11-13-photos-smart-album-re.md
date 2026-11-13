# Photos (macOS) Smart Album — reverse-engineering notes

Target: `/System/Applications/Photos.app` 12.0 on macOS 27.2.1, plus `PhotosUICore.framework` resources.
Static evidence only (nib archives, string tables, Objective-C metadata strings). Nothing was executed.

REA evidence IDs (same MCP session, 2026-11-13):
- `ev_336bca59…` — `decode_interface_builder` full graph of Photos.app nibs (64 documents, truncated: EditorView,
  RowView, TextFieldView fell past the 64-document cap; those three were read with `strings`, see below).
- `ev_23e30e4b…` — its summary view.
- ComboBox and Date condition nib pages via `inspect_analysis_view` (outlets/actions quoted below).

## 1. Architecture (observed class names)

| Layer | Where | Classes / symbols |
|---|---|---|
| Model + query | `PhotosUICore` (shared with iOS) | `PXSmartAlbumCondition`, `PXSmartAlbumConditionType` (has `…Invalid`), `<PXSmartAlbumQuery>`, `PXSmartAlbumQueryDelegate`, `PXLabeledValue`, `PXLabeledValueFormatter` |
| Editor UI (Mac) | `Photos` binary | `IPXSmartAlbumEditorViewController` → N × `IPXSmartAlbumConditionRowViewController` → one `IPXSmartAlbumCondition*ViewController` per type |
| Factory | `Photos` binary | `Class _IPXSmartAlbumConditionViewControllerClassForConditionType(PXSmartAlbumConditionType)` |
| Storage | PhotoKit | `createSmartAlbumInCollectionList:photoLibrary:window:completionHandler:`, `editSmartAlbum:inWindow:completionHandler:`, `queryWithSmartAlbum:collectionList:photoLibrary:error:`, `creationRequestForSmartAlbumCopyFromSmartAlbum:` (duplicate) |

So: one condition **model** per row, the row picks a **value editor by type**, the editor owns an async **query**
object whose delegate pushes a result count back into the sheet.

## 2. Editor sheet (`IPXSmartAlbumEditorView.nib`)

Strings / outlets in the archive:
- `titleTextField` with label **"Smart Album Name:"** (default name `PXSmartAlbumDefaultName` = "Untitled Smart Album").
- `conjunctionPopUpButton` → `_conjunctionDidChange:`. Text: **"Match [all|any] of the following conditions:"**.
  A second variant **"Match the following condition:"** sits in `oneOrMoreTabView` — the any/all popup is **hidden when
  there is only one condition**.
- `queryScrollView` / `queryTileView` + `queryBoxHeightConstraint` — rows stack in a box that grows, then scrolls.
- `statusTextField` (`setStatusText:`) — live result count, `PXSmartAlbumResultsCountString` =
  **"%ld item(s) matched"**.
- `okButton` / `cancelButton` (`_okButtonPressed:` / `_cancelButtonPressed:`). Log strings:
  `"IPXSmartAlbums: Failed to edit smart album: cancelled by user"` — edits are a draft until OK.

## 3. Condition row (`IPXSmartAlbumConditionRowView.nib`, 650×33pt)

- `categoryPopup` (130pt) → `_conditionTypeDidChange:` — picks the **condition type**.
- `queryContentView` (454pt) — the type-specific editor is swapped in here.
- `removeButton` (**−**, `_removeButtonPressed:`) and `addButton` (**+**, `_addButtonPressed:`), 18pt each, at the
  row's trailing edge. Delegate: `addNewConditionAfterConditionRowViewController:` — **+ inserts a new row right after
  this one**, not at the end. `removeConditionForConditionRowViewController:`.
- Keyboard: `updateTabSequenceForConditionRowViewController:`, `nextKeyViewWithPreviousView:`.

## 4. Value editors (one nib per shape)

| Nib | Outlets / actions | Shape |
|---|---|---|
| `ConditionTextFieldView` | `comparatorPopUp`, `textField` | comparator + free text |
| `ConditionPopupView` | `comparatorPopUp`, `itemPopup` → `itemDidChange:` | comparator + pick one item |
| `ConditionComboBoxView` | `comparatorPopUp`, `tabView`, `oneExifComboBox`, `twoExifComboBox1/2` ("to") | comparator + value, or **range** with two values; combo box = type or pick a value **that exists in the library** (`values`, `supportsSecondValue`) |
| `ConditionDateView` | `comparatorPopUp`, `tabView` (4 tabs), `oneDatePicker`, `twoDatePicker1/2` ("to"), `numberOfUnitTextField` + `unitPopUp` (Days/Weeks/Months/Years) | the comparator **switches the value tab**: one date / range / "in the last N units" / none |
| `ConditionFlashView` | `flashFiredPopup` → `_flashFiredDidChange:` | did fire / did not fire |

Controller per type: Album, Aperture, CameraModel, DateCaptured/DateAdded (Date), Flash, FocalLength, ISO, Keyword,
LensModel, Person, Photo, Rating, ShutterSpeed, TextField (Text/Title/Caption/Filename).

## 5. Vocabulary (`PhotosUICore … PXSmartAlbumStrings.loctable`, en)

Condition types: Album · Date Captured · Date Added · Person/Pet · Keyword · Title · Caption · Filename · Text ·
Photo · Camera Model · Lens · Aperture · Shutter Speed · ISO · Focal Length · Flash · Rating.

Comparators: is · is not · includes · does not include · starts with · ends with · is empty · is not empty ·
is greater than / is less than (numerical) · is greater/less than or equal to · is before / is after (temporal) ·
is in the range · is in the last · is not in the last. Units: days · weeks · months · years.
Album/Keyword offer **Any**.

Photo type values: favorite · edited · hidden · RAW · referenced · tagged with GPS · video · Live Photo · burst ·
panorama · HDR · portrait · selfie · screenshot · screen recording · slo-mo · time-lapse · long exposure · animated ·
Cinematic · ProRes · Spatial · unable to upload to iCloud Photos.

Conjunction: all · any.

## 6. What this means (inference, not observed)

- Comparators are **typed by value kind** (text, numeric, temporal, set) — the same "is greater than" key exists in a
  `-Numerical` and a `-Temporal` flavour, so the list a row shows depends on its type.
- The count is computed by a query object with a delegate while the sheet is open → results update as the user edits,
  without saving. Exact debounce/threading: **unknown** (lives in the dyld shared cache, not decompiled).
- Saving is atomic on OK; Cancel discards. Duplicate is a copy creation request.

## Unknowns

- Query evaluation (SQL vs. in-memory), debounce interval, and how live album contents refresh after save.
- iOS 18+ smart-album editor (if any) — not inspected; only the Mac editor UI is evidenced here.
