# FS-01.03c — Search kiểu Photos: gợi ý, viên lọc, kết quả tại chỗ, chỉ mục

`FS-01.03c` · `Data/Database/SearchIndexStore.swift` · `SearchIndexQueries` · `Domain/Search/` ·
`Features/Library/SearchSuggestionsScreen.swift` · `ShotDexMac/MacRootWindow.swift` · test `SearchIndexTests` ·
`SearchSuggestionRankerTests` · `SearchCalendarRuleTests` · cập nhật 2026-11-14

Intent [2026-11-14-search-like-photos](../../_intents/2026-11-14-search-like-photos.md) · bằng chứng
[Photos search RE](../../_research/2026-11-14-photos-search-re.md) · quyết định `.planboard/search-photos/DECISIONS.md`.

**Thay** [03 §5–§7](03-search.md#5-màn-tìm-kiếm) (chồng capsule, đường áp nhảy tab). Giữ nguyên 03 §1–§4, §8, §9 và
[03b](03b-time-of-day-and-acceptance.md) (chip mời, dòng "Try:", Recents màn rộng).

## 1. Chỉ mục giá trị (A1)

Như bảng `groups`/`ga`/`prefix` của Photos: mỗi **giá trị tìm được** là một dòng tính sẵn, kèm số ảnh và ảnh đại
diện; gõ chữ khớp trên các dòng này, không quét ảnh.

| Loại (category) | Giá trị | Điều kiện sinh ra |
|---|---|---|
| Camera Brand | `Canon` | `cameraBrand is Canon` |
| Camera | `Canon EOS R6` | `cameraBody is …` |
| Lens | `RF 85mm F1.2 L USM` | `lens is …` |
| Focal Length | `85mm` (làm tròn mm) | `focalLength = 85` |
| Aperture | `f/1.8` | `aperture = 1.8` |
| ISO | `ISO 3200` | `iso = 3200` |
| Place | mỗi tên trong địa chỉ đã geocode (`Fukuoka`, `Japan`…) | `place contains …` |
| Year | `2024` | `dateTaken` trong năm |
| Month | `June 2024` | `dateTaken inMonth` |
| Month of Year | `June` | `monthOfYear is 6` (mới, §5) |
| Season | `Summer` | `season is summer` (mới) |
| Day of Week | `Weekend`, `Saturday`… | `dayOfWeek is …` (mới) |
| File Type | `RAW`, `HEIC`… | `fileType is …` |
| Photo Kind | `Live Photo`, `Panorama`… (`PhotoKind`) | `photoKind is …` |
| Sensor Format | `Full Frame`… | `sensorFormat is …` |
| Keyword | `sunset` (iOS 27) | `keyword hasKeyword …` |

- Bảng `search_group` (loại, tên, tên chuẩn hoá, số ảnh, ảnh đại diện = ảnh mới nhất) + `search_group_asset`
  (nhóm → ảnh) + FTS5 `search_group_fts` trên tên chuẩn hoá (không hoa thường, không dấu, tiền tố).
- **Dữ liệu suy ra**: dựng lại toàn bộ từ `photo_metadata`, bảng place, keyword mirror; không chứa chữ người gõ.
  Dựng **nền**, sau mỗi lô indexer / lượt geocode / đồng bộ keyword, gom lại (một lần dựng đang chạy thì lần sau
  đợi nó xong). 55.000 ảnh: dựng lại ≤ 3 s trên sim.
- Nhóm 0 ảnh không tồn tại. Album không có trong chỉ mục: không có điều kiện album để lọc lưới.

## 2. Gõ chữ: dòng gợi ý (D1)

- Mỗi từ gõ là một **tiền tố** khớp đầu một từ trong tên (`can` → `Canon`, `85` → `85mm`, `fuku` → `Fukuoka`),
  mọi từ phải khớp (AND), không phân biệt hoa thường và dấu (`da lat` → `Đà Lạt`).
- Mỗi gợi ý một dòng: ảnh đại diện 40pt bo 8, tên với phần đã gõ **đậm**, loại bên dưới (màu phụ), số ảnh bên phải
  (`1,204`, định dạng số theo máy).
- Xếp: tên **bắt đầu** bằng chữ gõ trước khớp giữa tên; rồi loại theo thứ tự Camera · Lens · Place · Year/Month ·
  Focal Length · Aperture · ISO · Photo Kind · File Type · còn lại; rồi nhiều ảnh trước. Tối đa **8 dòng**.
- **Viên "đọc hiểu"** (03 §6) thành dòng đầu tiên, icon `text.magnifyingglass`, khi bộ phân tích hiểu câu ra
  **≥ 2 điều kiện** hoặc một điều kiện so sánh (`f > 1.2`, `ISO over 3200`, `before 2020`) mà không nhóm nào là nó.
  Chạm = thành viên lọc chứa đúng các điều kiện đó.

## 3. Chọn gợi ý: viên lọc (D3)

- Chọn một dòng → nó thành **viên** trong ô tìm (`.searchable(text:tokens:)`, iOS 16+, nên iOS 17 và 26 như nhau),
  chữ đã gõ được xoá.
- Có viên rồi gõ tiếp: gợi ý và số ảnh **chỉ tính trong ảnh khớp mọi viên**; nhóm không còn ảnh nào thì không hiện.
- Nhiều viên = phải khớp tất cả. Xoá lùi khi ô trống gỡ viên cuối (hành vi của hệ thống).
- Câu tìm = điều kiện của các viên + điều kiện bộ phân tích đọc từ chữ còn lại (không model) → một
  `SmartAlbumQuery` (All). Save as Smart Album / Advanced lưu đúng câu đó.

## 4. Kết quả ngay trong Search (D2)

- Ô có viên hoặc chữ → dưới gợi ý là mục **Photos** (`Photos · 412`) và lưới ảnh khớp, vẽ **0,15 s sau phím cuối**;
  gõ tiếp huỷ lần cũ (A2). Lưới cùng cỡ ô với Library ở thiết bị đó; chạm ảnh mở viewer tại chỗ (phóng từ ô).
- 300 ảnh đầu vẽ ngay, phần còn lại nạp sau (A5).
- Nút **Open in Library** ở dòng tiêu đề mục Photos: áp câu tìm vào Library (thanh điều kiện, lọc, sắp xếp như cũ)
  và chuyển sang tab Library — đường áp cũ (03 §7), giờ là một lựa chọn chứ không bắt buộc.
- **Phím Search**: ẩn bàn phím, giữ kết quả, ghi Recents. Bộ phân tích không chắc và có model (03 §4) → hỏi model
  **lúc này** (không bao giờ khi đang gõ), có câu trả lời thì thay kết quả và hiện dòng "Read by …" như cũ.
- Recents ghi khi: bấm Search, Open in Library, hoặc mở một ảnh kết quả. Ghi tên các viên + chữ, cách nhau dấu cách.
- 0 ảnh: trạng thái rỗng `No Results` + `Try a different search.` (`ContentUnavailableView.search`).
- iPad / Duo / Mac: lưới kết quả chiếm phần còn lại của màn; gợi ý ≤ 5 dòng khi có kết quả.

## 5. Ô trống (D4) và ngày tháng (D5)

- Ô trống: **Recents** (thẻ như cũ, 03b §5) rồi **In Your Library**: 2 Camera, 2 Lens, 2 Place, năm mới nhất — dòng
  như §2, theo số ảnh. Chạm = viên. Thư viện chưa có gì: dòng "Try: …" (03b §4).
- Hiểu thêm (bộ phân tích và chỉ mục):

| Gõ | Điều kiện |
|---|---|
| `2024` (4 chữ số 1990–năm nay) | năm (đã có: `năm 2023`, `trước 2020`) |
| `june` · `jun` · `tháng 6` · `thg 6` | tháng trong năm bất kỳ → `monthOfYear` |
| `june 2024` · `tháng 6 2024` · `tháng 6/2024` | tháng cụ thể → `dateTaken inMonth` |
| `spring/mùa xuân` · `summer/mùa hè` · `autumn/fall/mùa thu` · `winter/mùa đông` | `season` |
| `monday … sunday` · `thứ 2 … chủ nhật` · `weekend/cuối tuần` · `weekday/ngày thường` | `dayOfWeek` |
| `today/hôm nay` · `this week/tuần này` | `dateTaken` khoảng (thêm cạnh `hôm qua`, `tháng trước` đã có) |

- **Mùa theo bán cầu nơi chụp**: vĩ độ < 0 → lệch 6 tháng (summer = 12–2); không toạ độ → bán cầu Bắc.
  Bắc: xuân 3–5, hè 6–8, thu 9–11, đông 12–2.
- Tháng, mùa, thứ tính theo **giờ của máy** lúc tìm (ngày chụp lưu UTC). Biết trước: ảnh chụp ở múi giờ xa có thể
  lệch ngày.
- Ba trường mới `monthOfYear`, `season`, `dayOfWeek` có trong bộ dựng Smart Album (loại choice).

## 6. Gõ sai (D6)

- Chỉ khi gợi ý **và** kết quả đều 0: tìm tên nhóm gần nhất với cả câu gõ (Damerau–Levenshtein ≤ 2, tên ≥ 5 chữ,
  không hoa thường/dấu) → một dòng `Did you mean “Fujifilm”?` kèm số ảnh. Chạm = viên. Không bao giờ tự sửa.

## 7. Tốc độ (A2–A7)

- Gợi ý, đếm, kết quả chạy trên **reader pool**, ngoài luồng chính; mỗi phím huỷ lần trước (Task cancel → GRDB
  interrupt).
- Từ vựng bộ phân tích dựng **một lần** mỗi khi catalog đổi (không mỗi phím).
- Recents: số ảnh + ảnh bìa của mọi câu trong **một** lượt nền; ảnh bìa lấy `PHAsset` ngoài luồng chính.
- Chữ tự do (`anyText`: máy, ống kính, tên file) khớp qua FTS5 trigram `photo_text_fts` (v66, external content,
  trigger chỉ chạy khi chữ thật sự đổi) khi từ ≥ 3 ký tự — chứa, không hoa thường; ngắn hơn thì `LIKE` như cũ.
  Caption và keyword vẫn `LIKE` trên bảng nhỏ của chúng. Kết quả giống hệt cách cũ (người dùng chọn 2026-11-14:
  "làm cái nào cho trải nghiệm nhanh").
- Đang index (`IndexPipeline` chưa xong): dòng đầu màn `Reading 1,234 photos — results may be incomplete.`

## 8. Mac (D7)

Ô tìm ở thanh công cụ: danh sách gợi ý (`.searchSuggestions`) dùng chung chỉ mục và xếp hạng, có số ảnh; chọn =
viên (`.searchable(text:tokens:)`); lưới cửa sổ hiện kết quả ngay như §4. Thanh phạm vi giữ nguyên.

## 9. Tiêu chí nghiệm thu

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | thư viện 3 ảnh Canon EOS R6, 2 ảnh Canon RF 85mm, 1 ảnh ở Cannes | dựng chỉ mục | nhóm Camera `Canon EOS R6` số 3, Lens số 2, Place `Cannes` số 1, Brand `Canon` số 5; ảnh đại diện = ảnh mới nhất | ✅ `SearchIndexTests.buildsGroupsWithCounts` |
| AC-2 | như AC-1 | gõ `can` | gợi ý gồm Canon, Canon EOS R6, Canon RF 85mm, Cannes; dòng tên bắt đầu bằng `can` trước | ✅ `SearchIndexTests.prefixMatchesWordStarts`, `rankerPutsNameStartsFirst` |
| AC-3 | nơi `Đà Lạt` | gõ `da lat` | gợi ý `Đà Lạt` | ✅ `SearchIndexTests.diacriticInsensitive` |
| AC-4 | ảnh đổi máy (indexer ghi lại dòng) | chỉ mục cập nhật | số ảnh của hai nhóm cũ/mới đổi theo; nhóm về 0 thì mất | ✅ `SearchIndexTests.refreshFollowsMetadata` |
| AC-5 | viên `Sony A7 IV` (4 ảnh, 2 ISO 3200) | gõ `iso` | gợi ý `ISO 3200` số **2** (trong viên), không nhóm ISO nào ngoài 4 ảnh đó | ✅ `SearchIndexTests.countsWithinTokens` |
| AC-6 | gõ `f > 1.2` | xem gợi ý | dòng đầu là dòng đọc hiểu `f > 1.2`; chạm thành viên, lưới khớp | ⚠️ `SearchSuggestionRankerTests.interpretationRowFirst` + ui-drive |
| AC-7 | iPhone 26.5, gõ `85` | 0,15 s | dòng gợi ý có hình, tên đậm phần gõ, loại, số; dưới là `Photos · N` và lưới | ✅ iPhone 26.5 `search-photos-iphone` s2 (gõ `iso`: 3 dòng + `Photos · 49` + lưới), 2026-11-14 |
| AC-8 | như AC-7 | chọn gợi ý `85mm` | viên `85mm` trong ô, chữ xoá, lưới N ảnh | ✅ iPhone 26.5 s3 (viên `ISO 200`, lưới 18) |
| AC-9 | viên `85mm` | bấm Open in Library | tab Library, thanh điều kiện có `85mm`, lưới N ảnh, sắp xếp/lọc dùng được | ✅ iPhone 26.5 s4 (Library, chip `ISO 200`, 18 ảnh) |
| AC-10 | kết quả trong Search | chạm một ảnh | viewer mở tại chỗ, đóng về Search, viên còn | ✅ iPhone 26.5 `search-viewer-iphone` t3 → t4 (viewer mở trong tab Search, đóng về Search, kết quả còn) |
| AC-11 | gõ nhanh `canon` từng phím | — | chỉ lần cuối cập nhật lưới; không truy vấn nào chạy trên luồng chính | ⚠️ `SearchEngineTests.cancelsStale` |
| AC-12 | ô trống, thư viện có ảnh | mở Search | Recents (nếu có) rồi `In Your Library` ≤ 7 dòng có số | ✅ iPhone 26.5 s1 sáng + t1 tối (Recents + In Your Library) |
| AC-13 | ảnh 2024-06-10 (Thứ Hai) ở Hà Nội và 2024-01-10 ở Sydney | gõ `summer` | khớp cả hai (Sydney tháng 1 là hè) | ✅ `SearchIndexTests.seasonByHemisphere` |
| AC-14 | như AC-13 | gõ `june`, `tháng 6 2024`, `monday`, `cuối tuần` | 1 · 1 · 1 · 0 ảnh | ✅ `SearchIndexTests.calendarFields`, `parserCalendarWords` |
| AC-15 | Smart Album builder | thêm điều kiện | có Month of Year, Season, Day of Week | ✅ `SearchIndexTests.calendarFields` |
| AC-16 | 3.120 ảnh Fujifilm | gõ `fujiflim` | 0 gợi ý, 0 ảnh, dòng `Did you mean “Fujifilm”?` số 3,120 | ✅ `SearchIndexTests.didYouMeanOnlyForNearNames` (chưa chụp màn) |
| AC-17 | gõ `leica` (có ảnh Leica) | — | không có dòng Did you mean | ✅ `SearchIndexTests.didYouMeanOnlyForNearNames` |
| AC-18 | 8 Recents | mở Search | một lượt nền cho cả 8; `fetchAssets` không chạy trên luồng chính | ⚠️ `SearchRecentsModelTests` |
| AC-19 | `anyText contains "mg_12"` trên 55k dòng | tìm | kết quả giống hệt LIKE cũ (cùng tập id) | ✅ `SearchIndexPerformanceTests.freeTextIndexMatchesLike` (cùng tập id, theo đổi tên/xoá, integrity-check) + `indexAtLibrarySize` (cùng 1.111 ảnh như LIKE); 55k: trigram 0,4–2 ms, quét LIKE 16–20 ms |
| AC-20 | indexer đang chạy, còn 1.234 ảnh | mở Search | dòng `Reading 1,234 photos — results may be incomplete.` | ⚠️ screenshot |
| AC-21 | mọi đường cũ: `ISO 3200 85mm`, Advanced, Save as Smart Album, `keyword:sunset`, chip mời, AI khi bấm Search | dùng | như trước | ⚠️ test hiện có xanh + ui-drive |
| AC-22 | iOS 17/18.6 (sheet) | gõ, chọn viên | như iOS 26 | ⚠️ sim 18.6 (chưa có runtime trên máy) |
| AC-23 | iPad 26.5 ngang, Duo inner | gõ `canon` | gợi ý ≤ 5 dòng + lưới kết quả cùng màn | ✅ iPad 13" 26.5 ngang (sim-shot): 8 dòng trái + `Photos · 330` + lưới; Duo inner 27.1 (sim-shot): 4 dòng trái + `Photos · 6` — cùng màn, 2026-11-14 |
| AC-24 | Mac | gõ `can` ở ô thanh công cụ | danh sách gợi ý có số; chọn thành viên; lưới cửa sổ lọc ngay | ✅ Mac `mac-search-photos` (demo): gõ `il` → `In Your Library · ILCE-7M4 · Camera · 85`, lưới 85 of 226 |
| AC-25 | 55k dòng (sim) | gõ một tiền tố | gợi ý ≤ 50 ms; dựng lại chỉ mục ≤ 3 s | ✅ `SearchIndexPerformanceTests.indexAtLibrarySize` sim: dựng 2,5 s, gợi ý ≤ 10 ms (lọc + xếp sơ bộ trong SQL, 60 dòng), đếm trong viên ≤ 60 ms |
