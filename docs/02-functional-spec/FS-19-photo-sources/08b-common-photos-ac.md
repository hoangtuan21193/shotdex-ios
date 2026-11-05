# FS-19.08b — Gom ảnh chung: tiêu chí nghiệm thu

`FS-19.08b` · cho [08](08-common-photos.md) · AC-115…AC-143, AC-159…191, AC-193…226 · cập nhật 2026-11-05 (AC-131…143: hoàn tác, §6b; AC-159…173: chỉ ảnh mới + tự gom, §6c; AC-174…191: xem kết quả Scan rồi mới quyết + chạy nhanh hơn, §6d; AC-193…219: folder theo ngày, Organize, giữ thông tin file, §6e — 2026-11-05)

Dữ liệu thử: server cục bộ (impacket smbserver + WebDAV trên Mac, memory `server-upload-fs15`), ảnh phong cảnh không
có mặt người. Test domain chạy trên client giả của `ShotDexTests/BackupFakes.swift` và GRDB trong bộ nhớ.

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-115 | A có 3 file cỡ 1.000/2.000/3.000 byte, B có 2 file cỡ 2.000/4.000 | quét | đúng 1 cặp vào bước băm; 0 byte nội dung của 3 file còn lại được đọc (client giả đếm lệnh đọc) | ✅ `CommonPhotosMatcherTests.sizeFilterReadsNothingElse` |
| AC-116 | A `IMG_1.JPG` và B `2025-06-01 IMG_1.JPG` cùng byte | quét xong | 1 ảnh **Same** dù khác tên | ✅ `CommonPhotosMatcherTests.renamedFileMatches` |
| AC-117 | A, B có file cùng cỡ, cùng tên, khác 1 byte ở giữa | quét xong | ở **Likely** khi mới liệt kê; sau băm rơi khỏi danh sách; nút chạy đếm 0 | ✅ `CommonPhotosMatcherTests.sameSizeDifferentBytesDropped` (+ `headAndTailSamples`, `fullHashCatchesWhatSamplesMiss`) |
| AC-118 | A, B có ảnh cùng ngày chụp + giây lẻ + máy, khác cỡ | quét xong | không có trong Likely lẫn Same | ✅ `CommonPhotosMatcherTests.sameCaptureDifferentSizeIgnored` |
| AC-119 | 3 folder A, B, D; ảnh X ở cả ba, ảnh Y chỉ ở A và B | quét xong | Same = {X}; Y không có | ✅ `CommonPhotosMatcherTests.intersectionOfAllFolders` |
| AC-120 | A 20.000 file, B 20.000 file, 300 chung (danh sách giả) | chạy bước lọc cỡ + Likely | xong ≤ 1 s trên Mac M1; Likely ≥ 300 | ✅ `CommonPhotosMatcherTests.twentyThousandEachUnderOneSecond` (Debug, sim) |
| AC-121 | 5 ảnh Same, folder chung rỗng, Copy | chạy | 5 file ở đích, SHA đọc lại khớp; A, B không đổi; 5 hàng log Copied | ✅ `CommonPhotosRunnerTests.copyVerifiesReadBack` |
| AC-122 | như AC-121, client giả trả SHA đọc lại sai cho file thứ 3 | chạy | file part thứ 3 bị xoá, không có tên thật ở đích; log Failed "checksum mismatch"; 4 file kia Copied | ✅ `CommonPhotosRunnerTests.copyMismatchLeavesNothing` |
| AC-123 | 5 ảnh Same, Move, cùng share | chạy | A, B mất 5 file; đích có 5; lệnh đổi chỗ dùng 5 lần, 0 lần tải; log Moved | ✅ `CommonPhotosRunnerTests.moveRenamesThenDeletes` (+ e2e `CommonPhotosSMBTests.moveRenamesOnTheServer`) |
| AC-124 | Move, client giả từ chối đổi chỗ (khác share) | chạy | chép + kiểm SHA rồi mới xoá; thứ tự lệnh: tải → đẩy → đọc lại → xoá | ✅ `CommonPhotosRunnerTests.crossShareMoveCopiesFirst` |
| AC-125 | Move, bản ở B đổi cỡ sau Scan | chạy tới ảnh đó | bản B không bị xoá; log Failed "changed on server"; bản ở đích giữ | ✅ `CommonPhotosRunnerTests.changedSourceNotDeleted` (+ `changedWriteTimeNotDeleted`, `sameSizeEditOfTheFirstSourceIsNotMoved`, `destinationChangedWhilePaused`, `destinationThatIsASourceStopsTheRun`) |
| AC-126 | đích đã có `IMG_1.JPG` cùng SHA và `IMG_2.JPG` khác SHA | Copy `IMG_1`, `IMG_2` | `IMG_1` Skipped (already there); `IMG_2` thành `IMG_2 (2).JPG`; không file nào bị ghi đè | ✅ `CommonPhotosRunnerTests.nameClashRules` (+ `sameNameTwiceInOneRun`) |
| AC-127 | ảnh Same ở `A/2025/06/` và `B/x/` | Copy | file nằm thẳng ở đích (phẳng); `.xmp` cùng tên gốc đi theo | ✅ `CommonPhotosRunnerTests.flatDestinationWithSidecar` (+ `rawSidecarStaysWithTheRaw`, `sidecarRetriedOnResume`, `skippedPhotoGetsItsSidecar`, `sidecarNeverOverwrites`) |
| AC-128 | 10 ảnh, mất kết nối sau ảnh thứ 4 | Resume khi server về | chạy tiếp từ ảnh 5; 4 ảnh đầu không đọc lại; tổng log 10 hàng | ✅ `CommonPhotosRunnerTests.resumeAfterDisconnect` (Copy + Move; + `killedMidCopyResumes`, `finishingRunResumes`, `secondRunnerIsTurnedAway`) |
| AC-129 | lượt chạy xong 3 Copied, 1 Skipped | xong | đích có CSV `ShotDex Common Photos <ngày giờ>.csv`, 4 hàng + tiêu đề, cột Status/Name/From/To/SHA-256 | ✅ `CommonPhotosRunnerTests.writesCsvLog` (+ `csvResumesUnderItsName`, `csvIsSafeToOpen`, `finishingRunResumes`) |
| AC-130 | Mac, màn duyệt NAS cục bộ, ⌘-click 2 folder | chuột phải → Find Common Photos… → chọn đích → Scan → Copy | sheet và cửa sổ tiến độ khớp board `MAC_CommonPhotos` / `MAC_CommonPhotosRun` (lệch ≤ 2pt), sáng và tối | ⚠️ một phần — ảnh `Tools/mac-shot` sáng + tối ở `build/design/shots/T9a…T11b` so bằng mắt với render board; Copy/Move chạy thật từ app trên SMB ảo; luồng đi bằng launch arg DEBUG (máy không có quyền Accessibility để bấm), `design-board compare` chưa chạy được trên Mac (chưa có dump element) |
| AC-131 | lượt Copy xong: 5 Copied, 1 Skipped (đích có sẵn); A, B còn nguyên | Undo Copy → Undo | 5 file Copied bị xoá khỏi đích, file Skipped còn; A, B không đổi; 5 hàng Undone; CSV của lượt bị xoá | ✅ `CommonPhotosUndoTests.undoCopyRemovesOnlyCopied` (+ e2e `CommonPhotosSMBTests.undoCopyOnTheServer`); CSV của lượt: U5 |
| AC-132 | lượt Copy xong; người dùng đã xoá cả bản A lẫn B của ảnh thứ 2 | Undo Copy | bản ở đích của ảnh 2 còn; hàng "Not undone — no other copy"; 4 ảnh kia Undone; không lệnh xoá nào tới đường dẫn ảnh 2 | ✅ `CommonPhotosUndoTests.undoCopyKeepsTheLastCopy` (+ `undoCopyStopsWhenASourceIsTheSameFile`, `sourcesCheckedBySHAWhenTheWriteTimeMoved`) |
| AC-133 | lượt Copy xong; file ở đích của ảnh 3 bị sửa 1 byte | Undo Copy | file đó còn nguyên; "Not undone — changed in Shared" | ✅ `CommonPhotosUndoTests.undoCopyKeepsAnEditedCopy` (+ `foreignAsideIsPutBack`, `undoCopyErrorPutsTheCopyBack`, `lostRenameReplyPutsTheCopyBack`) |
| AC-134 | lượt Move xong, cùng share, 5 ảnh ở A và B | Undo Move | A, B có lại 5 ảnh cùng SHA; đích rỗng; bản A về bằng lệnh đổi chỗ (0 lần đẩy cho A), bản B đẩy lên rồi đọc lại SHA; 5 hàng Undone | ✅ `CommonPhotosUndoTests.undoMoveSameShare` (+ e2e `CommonPhotosSMBTests.undoMoveOnTheServer`, `refusedRenameBackIsWrittenInstead`, `whatWasThereStaysWhateverTheReason`) |
| AC-135 | lượt Move xong; đường dẫn cũ `B/IMG_2.JPG` đã có file khác byte | Undo Move | file ở B không bị ghi đè hay đổi tên; bản B của ảnh 2 "Not put back — name taken"; bản A về chỗ cũ; ảnh 2 không mất bản nào | ✅ `CommonPhotosUndoTests.undoMoveTakenPathIsSkipped` |
| AC-136 | lượt Move khác share (đã chép thay vì đổi chỗ), 3 ảnh | Undo Move, client giả từ chối đọc lại SHA ở bản A của ảnh 2 | ảnh 2: bản ở đích **còn**; part ở A bị xoá; ảnh 1 và 3: A, B có lại, đích không còn; thứ tự lệnh: tải đích → đẩy → đọc lại → đổi tên → (mọi bản xong) xoá đích | ✅ `CommonPhotosUndoTests.undoCrossShareMoveKeepsTheCopyUntilAllAreBack` (+ `editedPutBackCopyKeepsTheDestination`, `undoMoveOfAnEditedCopyDoesNothing`, `undoMoveResumesASetAsideDestination`) |
| AC-137 | lượt Move xong; ở mọi bước của hoàn tác, client giả ném lỗi (lần lượt từng lệnh) | Undo, rồi Resume | sau mỗi lần ném, mỗi ảnh còn ≥ 1 bản trên server có đúng SHA; Resume đi tới hết, kết quả như AC-134 | ✅ `CommonPhotosUndoTests.everyFailurePointKeepsACopy` (Move/Copy × cùng/khác share × có/không `.xmp`; rớt kết nối ở mọi lệnh ghi trước/sau khi server làm, và ở mọi lệnh đọc) (+ `undoMoveStopsWhenARestoredCopyIsTheDestination`) |
| AC-138 | lượt Move xong, ảnh có `.xmp`; lượt Copy xong, đích đã có sẵn `IMG_4.xmp` cùng byte | Undo cả hai | Move: `.xmp` về cạnh từng bản được trả; Copy: `.xmp` lượt đặt bị xoá, `IMG_4.xmp` có sẵn còn | ✅ Copy: `CommonPhotosUndoTests.undoCopySidecarRules` (+ `sharedSidecarGoesWithTheLastPhoto`, `lastSidecarStays`, `sidecarThatWillNotGoLeavesTheRowUndone`); Move: `undoMoveSidecarsGoBack` |
| AC-139 | lượt 10 ảnh Copied, chọn hàng 2, 5 trong bảng log | chuột phải → Undo Selected… | chỉ 2 ảnh đó Undone; 8 hàng kia Copied; CSV lượt còn, thêm `… Undo.csv` 2 hàng | ✅ lõi: `CommonPhotosUndoTests.undoSelectedTwoRows` (+ `lastUndoTakesTheCSVs`, `undoCSVSaysNotUndone`, `foreignFileUnderTheLogNameStays`); Mac: chuột phải **Undo Selected…** ở `MacCommonPhotosRunWindow` (chưa bấm tay — máy không có quyền Accessibility) |
| AC-140 | hoàn tác 10 ảnh, quit app sau ảnh 4 | mở lại → banner → Resume | chạy tiếp từ ảnh 5; 4 ảnh đầu không đọc lại; 10 hàng Undone | ✅ `CommonPhotosUndoTests.resumeUndoAfterQuit` (+ `undoneRowsReachTheRunOnResume`, `undoCopyResumesASetAsideCopy`, `undoMoveResumesASetAsideDestination`); banner Resume ở U8 |
| AC-141 | lượt Move xong đã chuyển lịch sử upload/Backup sang đích | Undo Move xong | lịch sử upload, download và sổ Backup trỏ lại đường dẫn cũ (`ServerFileHistory`) | ✅ `ServerFileHistoryTests.undoPutsEachRowBack` (+ `CommonPhotosUndoTests.afterUndoHearsTheCopiesWrittenBack`, `failedHistoryStepResumes`); Mac nối `afterUndo` → `restoreHistory(runId: undoOf)` + Rescan (`MacCommonPhotosRuns`) |
| AC-142 | DB có 20 lượt đã xong + 1 lượt dở | lượt thứ 21 xong | lượt xong cũ nhất cùng các hàng bị xoá khỏi DB; lượt dở còn; Activity liệt kê 20 lượt xong qua lần mở app sau | ✅ DB: `CommonPhotosStoreTests.keepsTwentyFinishedRuns` (+ `unfinishedUndoKeepsItsGroup`, `sameSecondRunsKeepTheirOrder`, `discardTakesItsUndoRuns`); Activity sau khi mở lại app: `build/design/shots/U8/activity-light|dark` |
| AC-143 | Mac, Activity có lượt đã xong | Show Log → Undo Copy… → Undo | hộp xác nhận (Cancel mặc định) và cửa sổ khớp board `MAC_CommonPhotosRun` / `MAC_Activity` sáng và tối; e2e trên SMB ảo: A, B, đích như AC-131/134 | ⚠️ một phần — chạy thật từ app trên SMB ảo (Copy rồi Undo, Shared trống lại, CSV đi theo); ảnh `build/design/shots/U8/` (confirm sáng/tối, undoing, undone, original-after-undo, activity sáng/tối) so bằng mắt với board v82; như AC-130: chưa bấm tay (không quyền Accessibility), chưa `design-board compare` (Mac chưa có dump element) |

Kiểm thêm khi `/verify`: folder chung nằm trong folder nguồn → sheet báo lỗi, nút chạy mờ; 1 folder → mục ẩn ở menu chuột phải; lịch
sử upload trỏ tới file bị dời được sửa đường dẫn (`ServerFileHistory`).

**`/verify` 2026-11-03:** AC-115…129 xanh — 148 test ở 16 suite (CommonPhotos*, ClickSelection, ServerFileHistory,
ServerSourceIndex/Toggle, BackupRunner, ServerUploadSession, PhotoDeletionGate, WebDAVRangeStart) trên sim iPhone Duo
27.1, gồm e2e trên SMB ảo (`CommonPhotosSMBTests`: quét, Copy, Move). Kiểm thêm: folder chung trong folder nguồn → sheet
báo lỗi (`build/design/shots/T10/light-error.png`), dưới 2 folder → mục ẩn (`CommonPhotosEntryTests`), lịch sử upload/backup
đi theo (`ServerFileHistoryTests.moveTakesTheBackupLedgerAlong`).
**Chưa chứng minh trọn:** AC-130 (xem dòng trên). `Tools/gate`: build xanh; toàn bộ test treo ở
`writesTheFormatAskedFor(type: heic)` trên Duo 27.1 và có 3 test đỏ của phần khác (`PerceptualHashStoreTests`,
`SettingsSearchTests`, `GridICloudFreeTests` — `PhotoGridCollectionView.swift` có chữ "icloud" từ `3f9f9c0c`), không do FS-19.08.

**`/verify` hoàn tác 2026-11-03:** AC-131…142 xanh. Bằng chứng là 179 test ở 13 suite (CommonPhotos*, ServerFileHistory,
BackupRunner, ServerUploadSession, ClickSelection) chạy trên sim iPhone Duo 27.1, kèm e2e trên SMB ảo
(`CommonPhotosSMBTests.undoCopyOnTheServer`, `undoMoveOnTheServer`). Copy rồi Undo cũng đã chạy thật từ app Mac trên SMB
ảo: Shared trống lại, CSV đi theo. Ảnh ở `build/design/shots/U8/`; board ở canvas Mac bản 82.
**Chưa chứng minh trọn:** AC-143 (cùng lý do với AC-130: không bấm tay được, không có element dump trên Mac). Chuỗi mới
chưa vào String Catalog (`Localizable.xcstrings` đang có sửa đổi của phiên khác). `Tools/gate` (cả bộ) không chạy trong
loop này, theo luật "cả bộ một lần mỗi intent".

## Chạy lại chỉ ảnh mới · tự gom (§6c)

Cùng dữ liệu thử như trên. "Bộ" = A + B → Shared trên một connection.

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-159 | A, B không phải nguồn, mỗi bên 1.000 file, 300 chung; quét một lần | quét lại cùng bộ, không file nào đổi | 0 lệnh đọc byte (client giả đếm `sha256`/`download`/đọc đầu file); kết quả 300 Same như lần đầu | ✅ `CommonPhotosIncrementalTests.rescanReadsNothing` (+ `changedFileIsReadAgain`, `moveDoesNotTrustTheCache`, `moveMidScanCannotRunOnTrust`); e2e SMB ảo `rescanOnTheServerReadsNothing` |
| AC-160 | lượt Copy xong 300 ảnh; sau đó thêm 3 ảnh cùng byte vào cả A và B | quét lại cùng bộ | danh sách đúng 3 ảnh mới; 300 ảnh cũ không hiện, không có lệnh nào tới đường dẫn của chúng ngoài liệt kê; nút **Copy 3** | ✅ `CommonPhotosIncrementalTests.onlyNewPhotos` (lượt quét Move, chỉ đọc file của 3 ảnh mới); e2e SMB ảo `rescanOnTheServerReadsNothing` (gom xong → quét lại 0 ảnh, 0 lần đọc) |
| AC-161 | như AC-160, thêm `X.JPG` chỉ vào A | quét lại | X không trong danh sách; lần quét sau khi B có X cùng byte thì X vào danh sách | ✅ `CommonPhotosIncrementalTests.newInOneFolderWaits` |
| AC-162 | ảnh `IMG_1.JPG` đã gom; sau đó ghi đè nội dung mới ở cả A và B (cỡ khác) | quét lại | IMG_1 được băm lại, là ảnh mới; Copy đặt `IMG_1 (2).JPG` ở Shared, bản cũ giữ nguyên | ✅ `CommonPhotosIncrementalTests.changedFileIsNew` (+ `everythingAndOtherDestination`, `destinationDuringTheScan`) |
| AC-163 | ảnh đã gom, người dùng xoá bản ở Shared; ảnh vẫn ở A và B | quét lại | ảnh vào lại danh sách và được chép lại; ảnh có bản ở Shared còn đúng đường dẫn + cỡ thì không bị đọc lại | ✅ `CommonPhotosIncrementalTests.goneFromSharedComesBack`, `replacedOrMissingDestination`; e2e SMB ảo `goneFromSharedOnTheServer` (chép thật, xoá một bản ở đích, quét lại ra đúng ảnh đó) |
| AC-164 | Activity có lượt xong (hay đã Stop) của bộ | **Run Again…** (hàng Activity hay cửa sổ log) | sheet mở đúng bộ (folder, đích, Copy/Move) và quét ngay; dòng "Last gathered … · N already gathered"; chỉ ảnh mới; không có gì mới → "Nothing new since …" + Scan Everything | ✅ `CommonPhotosJobTests.overRowsHaveNoBarAndCanBeRemoved` (nút Run Again), `CommonPhotosIncrementalTests.everythingIsOneScan`; ảnh Mac sáng + tối của hai trạng thái trên SMB ảo (`build/design/shots/G4/`), khớp board `MAC_CommonPhotos` tweak `state` |
| AC-165 | bộ Copy đã bật Keep gathering; 2 ảnh mới chung xuất hiện | lượt tự gom 15 phút, Mac cắm điện, Wi‑Fi | 2 ảnh được chép như §6 (SHA đọc lại khớp), có log + hoàn tác được, không ai mở app | ✅ `CommonPhotosGatherTests.copiesWithoutTheApp`, e2e SMB `passOnTheServer`; `MacCommonPhotosGatherer` (15 phút, helper + app), `CommonPhotosClaimsTests`; e2e app thật với SMB ảo: thêm ảnh chung → lượt tự gom chép, CSV `… auto.csv` (`build/design/shots/G9/`). Helper launchd thật chưa chạy (cần DB thật của người dùng) |
| AC-166 | bộ tự gom, không có ảnh mới | lượt tự gom | không thêm hàng Activity; "checked … ago" của bộ cập nhật; 0 lệnh đọc byte | ✅ `CommonPhotosGatherTests.nothingNewLeavesNoRun`; e2e SMB ảo `passOnTheServer` |
| AC-167 | bộ tự gom; Mac chạy pin (hay mạng tính tiền) | tới giờ lượt tự gom | không lệnh nào tới server; bộ ghi "Waiting to Charge" (hay "Waiting for Wi‑Fi") | ✅ `CommonPhotosGatherTests.waitsForPowerAndNetwork` |
| AC-168 | Backup đang chạy trên cùng connection | lượt tự gom tới giờ | lượt tự gom chờ khoá, Backup đi trước (thứ tự lệnh trên client giả) | ✅ `CommonPhotosGatherTests.backupGoesFirst` |
| AC-169 | bộ **Move** tự gom; 4 ảnh mới chung | lượt tự gom | 0 file bị dời hay xoá; một thông báo "4 photos are ready to move to “Shared”"; hàng Activity "Ready to move 4"; bấm **Move 4…** → hộp xác nhận → chạy như §6 | ✅ `CommonPhotosGatherTests.moveWaitsForTheUser`, `confirmNeedsTheListTheUserSaw`, `stopGatheringDropsTheReadyList`, `goneFromTheSourcesDropsTheList`, `switchingActionKeepsRunsApart`, e2e SMB `moveReadyOnTheServer`, `CommonPhotosJobTests.readyToMoveWaitsForTheUser`; ảnh Mac `build/design/shots/G7/` (sáng, tối, hộp hỏi). Thông báo macOS thật hiện ra khi helper gọi lượt tự gom: G9 |
| AC-170 | bộ tự gom; server ngắt giữa lượt Copy sau ảnh 1/3 | lượt tự gom | ảnh 1 xong, không xoá gì; bộ ghi "NAS Home isn't reachable"; lượt sau chép nốt ảnh 2, 3, không chép lại ảnh 1 | ✅ `CommonPhotosGatherTests.resumesNextPass`, `userPauseIsNotCarriedOn`, `earlierDayRunHoldsItsPhotos`, e2e SMB `resumesOnTheServer` (phiên SMB thật bị cắt sau ảnh 1). Lượt tự gom thật trong helper: G9 |
| AC-171 | folder `Vợ` bị xoá trên server | lượt tự gom | bộ dừng, hàng "“Vợ” isn't on NAS Home anymore · Stopped gathering"; không lượt nào chạy nữa cho tới khi bật lại | ✅ `CommonPhotosGatherTests.folderGoneStops`, `missingWhileListingNeedsProof`, `unconfirmedGoneIsUnreachable`; e2e SMB ảo `passOnTheServer` (xoá folder B thật → dừng) |
| AC-172 | bộ tự gom có 2 lượt đã gom | **Stop Gathering** | không lượt tự gom nào chạy nữa; log, CSV và hoàn tác của 2 lượt còn nguyên | ✅ `CommonPhotosGatherTests.stopGatheringKeepsTheRuns`, `stopDuringThePass`, `CommonPhotosWatchRowTests.stoppedByTheUserIsNotListed`; Activity › Gathering ⋯ › Stop Gathering… (ảnh `build/design/shots/G9/`) |
| AC-173 | bộ Copy tự gom; ngày 3/11 có 3 lượt tự gom, mỗi lượt 2 ảnh; ngày 4/11 một lượt 1 ảnh | xem Activity | đúng 2 hàng cho bộ: "Nov 3 · 6 copied" (một CSV 6 hàng) và "Nov 4 · 1 copied"; hoàn tác hàng Nov 3 trả đủ 6 | ✅ `CommonPhotosGatherTests.oneRunPerDay`, `busyDayWaits`, `stoppedDayStartsAnother`, `undoneStaysUndone` (hàng Activity: G9) |

## Xem kết quả Scan rồi mới quyết · chạy nhanh hơn (§6d)

Cùng dữ liệu thử. "Bộ" như §6c. Client giả đếm từng lệnh (`sha256`, `download`, `readRange`, `upload`, server copy) và
số byte qua mạng.

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-174 | A, B có 312 ứng viên cùng cỡ; 280 đã băm xong là Same, 32 đang băm | xem danh sách | đúng 280 hàng, hàng nào cũng Same; không chữ "Likely" ở hàng, đếm hay nhãn VoiceOver; đầu danh sách "Checking 32" | ✅ `CommonPhotosScanModelTests.onlySameRows` (Scan hỏng giữa chừng: hàng = đúng các ảnh Same, phần chưa tới là đếm "Not checked"); ảnh Mac sáng/tối `build/design/shots/R3/` |
| AC-175 | Copy; Shared có `IMG_0001.JPG` khác byte và `IMG_0002.JPG` cùng SHA với ảnh chung | Scan xong | hàng `IMG_0001` ghi `→ Shared/IMG_0001 (2).JPG`; hàng `IMG_0002` mờ, ghi `Already in Shared`, không đếm vào nút; đầu danh sách "… · 1 already in Shared" | ✅ `CommonPhotosScanModelTests.rowsCarryThePlan`, `runCountLeavesOutWhatIsThere`, `destinationChosenAfterTheScan`; `CommonPhotosDestinationPlanTests` (5); ảnh Mac `build/design/shots/R4/` (sáng/tối, Copy/Move) |
| AC-176 | Move; ảnh có 1 bản ở A, 2 bản ở B | Scan xong | hàng ghi `→ Shared/<tên>`, cột phải `Removes 3 copies`, tooltip liệt kê đủ 3 đường dẫn | ✅ `CommonPhotosScanModelTests.rowsCarryThePlan` (`copies`); ảnh Mac Move `build/design/shots/R4/move_*.png` (tooltip đủ đường dẫn chưa chụp) |
| AC-177 | Scan xong 3 ảnh Same (Copy), không file nào đổi | **Copy 3** | 0 lệnh `sha256` lên bản nguồn; 3 ảnh Copied; tên ở Shared đúng như hàng đã ghi | ✅ `CommonPhotosReviewTests.copyRunReadsNoSource`, `copyWithSidecarReadsNoSource` |
| AC-178 | Scan xong 3 ảnh Same (Move), không file nào đổi | **Move 3** | 0 lệnh `sha256` lên bản nguồn (chỉ kiểm cỡ + ngày sửa); 3 ảnh Moved | ✅ `CommonPhotosReviewTests.moveRunReadsNoSource` (không một lệnh `sha256` nào, kể cả bản đã dời) |
| AC-179 | Scan xong (Move); sau đó `Vợ/IMG_2.JPG` bị ghi đè nội dung mới | **Move N** | `IMG_2` Failed "changed on the server", không bản nào của nó bị xoá; ảnh khác vẫn Moved | ✅ `CommonPhotosReviewTests.changedAfterScanFails`, `firstCopyChangedAfterScanFails`; e2e SMB ảo `CommonPhotosSMBTests.changedAfterScanOnTheServer` |
| AC-180 | hàng ghi `→ Shared/IMG_0001 (2).JPG`; giữa Scan và chạy có người tạo `Shared/IMG_0001 (2).JPG` khác byte | **Copy** | ảnh nằm ở `IMG_0001 (3).JPG`; không file nào bị ghi đè; log và CSV ghi `(3)` | ✅ `CommonPhotosReviewTests.destinationChangedAfterScan` + `CommonPhotosScanModelTests.runNamesFromTheDestinationAsItIsThen` (hàng ghi `(2)`, chạy ra `(3)`) |
| AC-181 | hàng Same, cả hai bản đã index | chọn hàng, **Space** | cửa sổ Compare: hai khung, trái `Tuấn/…`, phải `Vợ/…`, mỗi khung tên, cỡ, ngày chụp, SHA 8 ký tự giống nhau; "Same bytes — SHA-256 matches"; ↓ sang hàng kế; Esc đóng | ✅ `CommonPhotosCompareTests.rowsAndSides`, `stepsThroughTheRows`, `followsTheList`; ảnh Mac `build/design/shots/R8/compare.png` (IMG_0003 hai bản đã index, cùng SHA), khớp board `MAC_CommonPhotosCompare` (canvas v104) |
| AC-182 | hàng Same 48 MB `DSC04388.ARW`, folder không phải nguồn | mở Compare | mỗi khung có thanh tiến độ, tải đủ 2 bản rồi hiện; sang hàng kế giữa chừng thì lượt tải bị huỷ; đóng Compare thì thư mục tạm trống | ✅ `CommonPhotosCompareLoaderTests.downloadsOnceThenCaches` (đọc theo khúc, kiểm SHA, lần sau từ cache), `cancelledLeavesNothing`, `changedIsNotKept`, `noRoomDownloadsNothing`, `sweepsLeftovers`; `CompareFileCacheTests.capsAndCleansUp` (2 GB, không bỏ file đang xem, đóng là trống); e2e SMB ảo `compareDownloadsOnTheServer`; ảnh Mac `build/design/shots/R9/downloaded.png` (bỏ qua index). Trạng thái đang tải chưa chụp được (file thử 50 KB) |
| AC-183 | Compare đang tải; server ngắt | — | khung ghi câu lỗi FS-15.01 §3 + **Try Again**; sheet giữ nguyên kết quả Scan, nút Copy vẫn bấm được | ✅ `CommonPhotosCompareLoaderTests.lostConnectionLeavesNothing` (lỗi tới Compare → câu FS-15.01 §3 + Try Again, không để lại phần file). Ảnh lỗi chưa chụp (không được tắt SMB ảo) |
| AC-184 | Scan đang chạy | mở Compare một hàng Same chưa index | khung ghi "Waiting for the scan…"; Scan không chậm hơn quá 5 % so với không mở Compare (đếm lệnh: lệnh Compare chỉ chạy khi Scan không có lệnh chờ) | ✅ `ConnectionLockTests.compareWaitsForEveryone` (Compare xếp sau lệnh Scan) + loader đọc từng khúc 4 MB, mỗi khúc một lệnh, nên Scan chen vào giữa các khúc. Chưa đo % chậm của Scan trên NAS thật |
| AC-185 | hàng Same là video 10 s ở cả hai bản | **Play** rồi tua tới 6 s | hai bên cùng chạy; sau tua, chênh thời điểm hai bên ≤ 1 khung hình; tiếng chỉ bên trái | ✅ `CommonPhotosVideoSyncTests.videoClockKeepsBothTogether` (ngưỡng kéo lại, tua, hết video); chạy thật trên SMB ảo: clip 8 s 30 fps có tiếng, `-ShotDexCommonPhotosComparePlay` tua 60 % rồi Play — 30 nhịp, chênh tối đa 1 ms (1 khung 33 ms), bên phải `muted`, dừng đúng ở 0:08 (`build/design/shots/R10/drift.log`, `paused.png`, `playing.png`). Compare luôn tối (tier D), không có bản sáng |
| AC-186 | 280 hàng Same | bỏ chọn 2 hàng | nút "Copy 278"; chạy xong 278 Copied, 2 hàng kia không có lệnh nào tới server | ✅ `CommonPhotosScanModelTests.runsOnlySelected` (bỏ 1/3: nút 2, chạy 2, không lệnh nào chạm ảnh bỏ ra), `runCountLeavesOutWhatIsThere`; ảnh Mac `build/design/shots/R5/` (sáng/tối, Copy/Move, 2 hàng bỏ chọn) |
| AC-187 | bộ đã bỏ ra 2 ảnh (AC-186) | quét lại / Run Again / lượt tự gom | 2 ảnh không ở Same, nằm trong **Left Out (2)**; lượt tự gom không chép chúng | ✅ `CommonPhotosLeftOutTests.leftOutStaysOut` (quét lại: không thành hàng, trong Left Out, chạy bỏ qua), `gatherPassSkipsIt` (lượt gom nền); ảnh Mac `build/design/shots/R6/again_*.png`, `open_*.png` |
| AC-188 | **Left Out (2)** | **Include** một ảnh rồi Scan | ảnh đó lại ở Same, được chọn; ảnh còn lại vẫn Left Out | ✅ `CommonPhotosLeftOutTests.includeBringsItBack` (Include 1/2: thành hàng chọn sẵn, lần quét sau vẫn vậy) |
| AC-189 | bộ có 2 ảnh bỏ ra | Clear Local Metadata Index; sau đó xoá bộ (Remove from List) | sau Clear: vẫn 2 ảnh Left Out; sau xoá bộ: bảng Ảnh bỏ ra không còn hàng nào của bộ | ✅ `CommonPhotosLeftOutTests.whatClearsIt` (Clear Index giữ; Remove from List xoá của bộ đó; xoá connection xoá hết) |
| AC-190 | bộ **Move** tự gom, ready 4 ảnh | trong cửa sổ log bỏ chọn 1 rồi **Move 3…** › xác nhận | hộp xác nhận nói 3; 3 ảnh Moved; ảnh thứ tư không bị đụng, nằm trong Left Out của bộ, lượt tự gom sau không đưa lại | ✅ `CommonPhotosGatherTests.readyLeavesOneOut` (bỏ 1/3: xác nhận theo tập đã thấy, hộp nói 2 thì 2 dời, ảnh bỏ ra còn ở cả hai folder và trong Left Out, lượt sau không đưa lại), `readyAllLeftOut`; ảnh Mac `build/design/shots/R7/` (sáng/tối) |
| AC-191 | Copy 1 GB phần chung trên WebDAV cục bộ (2 folder) | **Copy** | byte qua Mac ≤ 1.1 GB (`COPY` trên server + đọc lại SHA ở đích); hôm nay ≈ 3 GB. Server từ chối `COPY` (hay connection SMB/SFTP) → tải + đẩy như cũ, ảnh vẫn Copied, log ghi cách chép | ✅ e2e WebDAV cục bộ (wsgidav 127.0.0.1:8096, 20 file 50 MB = 1 GB chung) `CommonPhotosWebDAVTests.serverCopyMovesOneThird`: có `COPY` qua mạng **1.00×** (1 048 793 598 B, chỉ đọc lại SHA), đường dài **3.00×**; cả 20 Copied, không sót part. `CommonPhotosRunnerTests.serverCopyThenReadBack`, `serverCopyMismatchLeavesNothing`, `serverCopyOfAChangedSource`, `serverCopyReplyLostResumes`, `serverCopyOfAGoneSourceFailsOnePhoto`, `refusedCopyFallsBack`, `refusedCopyIsAskedOnce`, `serverCopyPassesTheLock`; `WebDAVFileClientTests.copyOnServer`; SMB ảo (`CommonPhotosSMBTests`) đi đường dài, vẫn Copied. Cách chép ghi ở log hệ thống (`commonPhotos`), chưa vào CSV |

## Folder theo ngày: kiểm nhanh, chạy lại (§6e)

Cùng dữ liệu thử; client giả đếm từng lệnh (`entries`, `readRange`, `sha256`, `download`, `upload`, đặt thông tin file).

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-193 | bộ chưa chạy, Action Copy | mở sheet; đổi Action sang Move | ô **Quick check** có, tắt; sang Move thì ô biến mất | ảnh Mac sheet Copy/Move sáng + tối; ⚠️ chưa có |
| AC-194 | Quick bật; A `2025/03/15/X.ARW` và B `2025/03/15/x.arw` cùng cỡ 48 MB, cùng byte | Scan | 1 hàng Same nhãn **Quick**; client giả đếm đúng 3 lệnh `readRange` 64 KB mỗi bản, 0 lệnh `sha256`/`download` khi Scan | ⚠️ chưa có (`CommonPhotosQuickCheckTests`) |
| AC-195 | Quick bật; (1) cùng đường dẫn + cỡ, khác 1 byte ở mẫu giữa; (2) A `2026/07/25/HAT00130.MOV`, B `2026/07/26/HAT00130.MOV` cùng byte | Scan | (1) rơi khỏi danh sách; (2) Same **không** nhãn Quick, băm SHA cả file như §5 | ⚠️ chưa có |
| AC-196 | 1 ảnh Same (quick) | **Copy 1** | Copied; SHA bản ở đích = SHA tính lúc tải bản folder đầu; bản ở B 0 lệnh đọc; CSV cột `Check` = `quick`; bảng SHA đã đọc không có hàng của bản ở B | ⚠️ chưa có |
| AC-197 | Scan xong với Quick bật | đổi Action sang Move | kết quả bị bỏ, nút thành **Scan**; Scan lại băm SHA cả file mọi ứng viên, không hàng nào nhãn Quick | ⚠️ chưa có |
| AC-198 | bộ đã chạy; cây `Năm/Tháng/Ngày` mỗi bên 1 năm, 12 tháng, 300 folder ngày; sau đó thêm 1 file vào `A/2025/03/15` (giờ sửa folder đổi) | Run Again (trong 24 giờ) | lệnh liệt kê = gốc + năm + 12 tháng mỗi bên + đúng 1 folder ngày; file mới vào kế hoạch; mọi file khác lấy từ danh sách đã lưu | ⚠️ chưa có (client giả đếm `entries`) |
| AC-199 | như AC-198; `A/2025/03/16` có folder con `edited/` (giờ sửa `16` không đổi) | Run Again | `16` và `16/edited` vẫn được liệt kê | ⚠️ chưa có |
| AC-200 | như AC-198 nhưng server không trả giờ sửa folder (WebDAV giả); hay lần liệt kê đủ gần nhất 25 giờ trước; hay bấm **Scan Everything** | quét | mọi folder được liệt kê (0 mục dùng danh sách đã lưu) | ⚠️ chưa có |
| AC-201 | bộ Tuan/Hue trên NAS người dùng (≈1 TB mỗi bên) | Scan lần đầu, Quick bật; rồi Run Again ngay sau | số đo ghi vào §6e: lần đầu ≤ 1,5 giờ (hôm nay ~5,5 giờ ước); Run Again liệt kê ≤ 1 phút | ⚠️ chưa có (đo trên NAS thật, chỉ Scan) |

## Xếp folder chung — Organize (§6e)

Cùng dữ liệu thử; client giả đếm từng lệnh (`entries`, `readRange`, `sha256`, `download`, `upload`, đặt thông tin file).

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-202 | bộ mới; ảnh `Tuấn/2025/03/15/X.ARW` = `Vợ/x/X.ARW` | Scan → Copy | sheet dòng Organize ghi `Same as Source`; kế hoạch `→ Shared/2025/03/15/X.ARW`; file nằm đúng đó | ⚠️ chưa có |
| AC-203 | bộ đã chạy trước 2026-11-05 (phẳng) | mở sheet bộ đó | Organize ghi `No Folders`; ảnh mới vẫn vào gốc Shared | ⚠️ chưa có |
| AC-204 | Organize Year › Month › Day, Videos Apart at the Top; ảnh EXIF 2025-10-12 14:03:27 `IMG_8812.HEIC`, video `IMG_8813.MOV` trong `Tuấn/2025/10/12` | Copy | `Shared/2025/Oct/2025.10.12/IMG_8812.HEIC`, `Shared/Videos/2025/Oct/2025.10.12/IMG_8813.MOV`; Preview ở trang Organize ghi đúng hai đường dẫn này | `BackupPathPlanner` tests dùng lại + ⚠️ chưa có |
| AC-205 | Year › Month › Day; video không đọc được ngày: (1) ở `Tuấn/2025/03/15/`; (2) ở `Tuấn/Trip/`, ngày sửa server 2024-08-01 | Copy | (1) `Shared/2025/Mar/2025.03.15/…`; (2) `Shared/2024/Aug/2024.08.01/…`; không lệnh `download` nào cho video | ⚠️ chưa có |
| AC-206 | File Names Date and Time; Shared đã có `2025/Oct/2025.10.12/2025-10-12 14.03.27.HEIC` khác byte | Copy ảnh chụp 2025-10-12 14:03:27 | ảnh thành `2025-10-12 14.03.27 (2).HEIC` trong đúng folder ngày; không ghi đè | ⚠️ chưa có |
| AC-207 | Same as Source; `Shared/2025/03/15/X.ARW` đã có cùng SHA; `Shared/X.ARW` cũng có cùng SHA | Scan | hàng `Already in Shared` (xét ở `2025/03/15`); nếu chỉ có `Shared/X.ARW` thì hàng ghi `→ Shared/2025/03/15/X.ARW` | ⚠️ chưa có |
| AC-208 | bộ đã gom 280 ảnh phẳng; đổi Organize sang Same as Source; thêm 3 ảnh mới ở cả hai bên | Run Again → Copy | dưới Organize: "Changing this affects new photos only. The 280 already gathered stay where they are."; 0 lệnh với 280 ảnh cũ; 3 ảnh mới vào folder con | ⚠️ chưa có |
| AC-209 | lượt Copy Same as Source tạo `Shared/2025/03/15/` (2 ảnh) và `Shared/2025/03/16/` (1 ảnh + `note.txt` của người dùng thêm sau) | **Undo Copy…** › Undo Copy | 3 ảnh xoá; `15/` bị xoá (rỗng), `16/` còn với `note.txt`; `2025/03` còn vì không rỗng | ⚠️ chưa có |
| AC-210 | bộ Copy tự gom, Organize Year › Month | lượt tự gom tìm 2 ảnh mới | 2 ảnh vào `Shared/<năm>/<tháng>/` | ⚠️ chưa có |

## Giữ thông tin file (§6e)

Cùng dữ liệu thử; client giả đếm từng lệnh (`entries`, `readRange`, `sha256`, `download`, `upload`, đặt thông tin file).

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-211 | SMB ảo; `Tuấn/IMG_1.JPG` ngày sửa = ngày tạo = 2020-01-02 03:04:05, cờ chỉ‑đọc, tag Finder; cùng byte ở Vợ | Copy | ở Shared: ngày sửa và ngày tạo 2020-01-02 03:04:05 (±2 s), cờ chỉ‑đọc; tag còn nếu `SMBClient` mở được luồng phụ, không thì log `tags not kept`; log `File info` = `kept` | e2e `CommonPhotosSMBTests` (impacket) — ⚠️ chưa có; đo 2026-11-05 hôm nay ra giờ chạy |
| AC-212 | bản ở Tuấn ngày sửa 2020-01-02, bản ở Vợ 2023-05-06, cùng byte | Copy | bản ở Shared mang 2020-01-02 (folder đầu) | ⚠️ chưa có |
| AC-213 | Move; server từ chối đổi chỗ (khác share, client giả); và Move đổi chỗ được | Move | cả hai đường: ảnh ở Shared mang ngày/cờ của bản folder đầu; `.xmp` mang ngày của sidecar nguồn | ⚠️ chưa có |
| AC-214 | WebDAV giả từ chối mọi cách đặt ngày | Scan → Copy | sheet dưới Action: "This server does not keep file dates: copies show the day they were copied." (từ lượt thứ hai trên connection đó); ảnh Copied; CSV `File info` = `dates not kept` | ⚠️ chưa có |
| AC-215 | server nhận lệnh đặt ngày nhưng liệt kê lại thấy lệch 1 giờ | Copy | ảnh Copied, log `dates not kept`; không Failed | ⚠️ chưa có |
| AC-216 | lượt Move đã xoá `Vợ/IMG_2.JPG` (ngày sửa 2021-07-08, chỉ‑đọc) | **Undo Move…** | `Vợ/IMG_2.JPG` trở lại cùng SHA, ngày sửa 2021-07-08, chỉ‑đọc | ⚠️ chưa có |
| AC-217 | lượt Copy cũ (trước §6e) 3 hàng Copied mang giờ chạy; 1 hàng bản ở Shared đã bị đổi cỡ | cửa sổ log › **Restore File Info…** | 2 file nhận ngày/cờ của bản folder đầu; 0 lệnh `upload`/`sha256`; hàng thứ ba ghi "changed in Shared", không đụng | ⚠️ chưa có |
| AC-218 | Shared có `IMG_3.JPG` Already there (ngày 2019) | Copy | `IMG_3.JPG` không bị đặt lại gì, ngày vẫn 2019 | ⚠️ chưa có |
| AC-219 | Server Upload (FS-15) một ảnh Photos chụp 2025-10-12 14:03:27; Backup (FS-22) một file nguồn folder ngày sửa 2022-02-02 | đẩy lên SMB ảo | ảnh Upload: ngày tạo = ngày sửa = 2025-10-12 14:03:27; file Backup mang 2022-02-02 | ⚠️ chưa có |

## Thêm sau review T1 (2026-11-05)

Challenger + review giao thức sau spike T1; ngữ cảnh ở plan §7.

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-220 | Server Upload một ảnh Photos chụp 2025-10-12 lên SMB ảo; On Server đã ghi bản đó | kiểm On Server (FS-19.07) sau khi file mang ngày chụp | bản trên server vẫn **same**, không `changed` — mọi chỗ ghi `modifiedAt` của bản trên server ghi ngày **sau** khi đặt thông tin | ⚠️ chưa có |
| AC-221 | bộ đã có danh sách folder đã lưu (trong 24 giờ); một ảnh ở A bị ghi đè tại chỗ cùng tên, folder không đổi giờ sửa | Scan với Action **Move** | mọi folder được liệt kê (0 mục từ danh sách đã lưu); ảnh bị ghi đè không thành Same theo SHA cũ | ⚠️ chưa có |
| AC-222 | lượt Copy đã đặt cờ chỉ‑đọc cho `Shared/2025/03/15/IMG_5.JPG` (nguồn chỉ‑đọc) | **Undo Copy…** | file được gỡ cờ rồi xoá; Undone, không `Not undone`; part hỏng của một ảnh chỉ‑đọc cũng dọn được | ⚠️ chưa có |
| AC-223 | 200 ảnh 5 MB, SMB ảo và WebDAV ảo, Copy | chạy với giữ thông tin và với client không hỗ trợ (đối chứng) | thời gian giữ thông tin ≤ 1,25 × đối chứng; số lệnh thêm mỗi ảnh ≤ 3 (đặt thông tin, đặt cờ nếu chỉ‑đọc, kiểm) | ⚠️ chưa có |
| AC-224 | Move, server từ chối đổi chỗ **và** không giữ được ngày (client giả) | Move | ảnh vẫn Moved (người dùng 2026-11-05); log `dates not kept`; ngày sửa/ngày tạo/cờ của mọi bản bị xoá đã nằm trong hàng log trước lệnh xoá; Undo Move trả đúng ngày đó | ⚠️ chưa có |
| AC-225 | Restore File Info… trên lượt 300 hàng | bấm **Stop** ở hàng 120 | dừng sau hàng đang làm; 120 hàng đã đặt giữ nguyên, phần còn lại không đụng; dòng phụ ghi số đã làm; chạy lại làm tiếp phần còn lại | ⚠️ chưa có |
| AC-226 | Same as Source; `Tuấn/2025/03/15/X.CR3` + `Tuấn/2025/03/16/X.JPG` (cùng tên gốc); folder nguồn `Trip. ` (chấm + cách cuối) | Copy | `X.CR3` → `Shared/2025/03/15/`, `X.JPG` → `Shared/2025/03/16/`; ảnh trong `Trip. ` vào folder tên đã sửa như Backup, không lỗi | ⚠️ chưa có |
