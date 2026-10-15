# FS-24.03 — Tab Photos: Library | Collections

`FS-24.03` · tier B (Library, Collections) · mã hiện có: `Features/Library/`, `Features/Albums/`, `Features/Sources/SourcesGroup.swift`,
`Features/Library/PhotoFilterMenu.swift` · board iPhone `Main`, `PH_Collections`, `PH_Statistics` · iPad `Main`, `IP_Collections` ·
Duo `Main`, `DC_Library`, `DI_Collections`, `DC_Collections`, `DI_Statistics`, `DC_Statistics` · Mac `Main`, `MAC_Collections`,
`MAC_Statistics`, `MAC_FilterPopover` · cập nhật 2026-10-16

**Một câu:** Photos giữ nguyên độ sâu của phần ảnh hôm nay — lọc EXIF, chọn, editor, album, thống kê — chỉ gom hai tab
Library và Collections thành hai đoạn của một tab, và mang ảnh + video tự quay (như app Photos).

## 1. Đầu tab

- Dưới tiêu đề lớn: segmented **Library | Collections** cao 32 (DESIGN §6), giữ đoạn đã chọn khi đổi tab và khi mở lại app.
- Library: leading ⚙; trailing **Filter and sort** rồi **Select** (capsule riêng, DESIGN §10.6) — như hôm nay.
- Collections: leading ⚙; trailing **+** = New Album · New Smart Album · Customize (FS-06.01 §2).
- Chế độ chọn ảnh: tab bar, segmented và mini player ẩn; nav bar giữ như FS-01.06.

## 2. Library

- Không đổi gì ngoài menu Filter and sort (board `Main` tweak menu, `MAC_FilterPopover`): nhóm Filter thêm hai hàng có chấm
  NEW cam nhỏ tới lần mở đầu:
  - **Source ›** — menu con: All Sources (mặc định) · từng nguồn có ảnh (Photos, 2026 Japan, T7, NAS Home, EOS_DIGITAL);
    chọn một nguồn = lưới chỉ còn ảnh có bản sao ở nguồn đó (FS-19.05). Một nguồn duy nhất thì hàng mờ.
  - **Kept on iPhone** — bật/tắt: chỉ ảnh đã Keep ([09](09-keep-on-device.md)).
- Menu Filter dùng chung với Albums và Duplicates (FS-06.09): hai hàng mới hiện ở cả ba chỗ — *một menu, một nội dung.*
- Hai hàng mới là điều kiện lọc như mọi điều kiện khác: hiện trong thanh điều kiện, Clear Filters xoá được.
- **Chốt 2026-10-16 (D8):** Source và Kept dùng được **cả** trong bộ lọc tạm lẫn làm **luật Smart Album**: rule builder
  (FS-06.08 §2, dùng chung với Advanced Search và điều kiện biểu đồ Statistics) thêm hai trường —
  - **Source** (loại *chọn*): `is` · `is not` một nguồn có ảnh (Photos, thư mục, ổ, server — FS-19); khớp ảnh **có bản sao**
    ở nguồn đó, cùng truy vấn với Source › của menu Filter. Không *is missing* (mọi ảnh có ít nhất một nguồn).
  - **Kept on iPhone** (loại *dải* như Favorite): `Kept` / `Not Kept`; khớp theo bảng thứ đã Keep ([12 §2](12-data.md)), tính
    sống — Keep thêm ảnh thì album có thêm ở lần mở kế; gỡ Keep thì rời album.
  - Điều kiện lưu bằng **id bền** của nguồn, không bằng tên: đổi tên nguồn không làm hỏng album. Nguồn đã gỡ: điều kiện còn,
    chip ghi `NAS Home (removed)`, khớp 0 ảnh; album vẫn mở (giải mã khoan dung FS-06.08 §1).

## 3. Collections

Thứ tự mặc định (board `PH_Collections`): hero **On This Day** · **Pinned** · **Smart Albums** · **My Albums** · **Shared
Albums** · **Media Types** · **Utilities** · **Sources**. People and Pets, Network: tắt sẵn, bật lại trong Customize ([02 §2](02-what-moves.md)).

**Utilities** — lưới 2 cột (iPhone, Duo ngoài), 4 cột (iPad, Duo trong) ô cao **44** bo 12 (board; iPad board vẽ 40 — phải lên 44, DESIGN §6; **Mac** giữ cỡ Mac theo MAC_STYLE, không có tối thiểu chạm 44 — board `MAC_Collections`): icon + tên 15, **không số đếm**
(VoiceOver vẫn đọc số). Thứ tự: **Statistics** · Backup · Duplicates · Places · Trips · Collages · Video Projects · Local
Network · Cloud · Hidden · Unable to Upload · **On Server** · **On This iPhone**. Hidden, Unable to Upload, On Server chỉ khi có
mục (như hôm nay). Ô mới (Statistics, On Server, On This iPhone) có chấm NEW 7pt màu accent ở mép phải ô tới lần chạm đầu.

- **Chốt 2026-10-16 (A7):** DESIGN §13 đã sửa theo board: nhóm **Utilities** và **Sources** của cả ba tab là lưới ô (icon + tên;
  Sources thêm số ở mép phải) — ô cao 44 bo 12 như board, chấm NEW 7pt accent; luật "hàng một dòng có số + chevron"
  vẫn áp cho Media Types và Creations.

- **Chốt 2026-10-16 (D9):** ô **Statistics** như mọi ô Utilities — cao 44, icon + tên, **không** con số tóm tắt, không dòng
  phụ (kể cả lúc index chưa xong hay chưa cấp quyền); lưới đều. Chỗ để Statistics không chìm là vị trí **ô đầu** + chấm NEW
  tới lần chạm đầu; ghim vào Pinned như mọi ô (dưới). VoiceOver: `Statistics`.
- Statistics mở bằng push trong tab Photos (tab Photos vẫn sáng); màn giữ nguyên FS-07; ⚙ thành **‹ Photos**.
- Ô Utilities ghim được vào Pinned như hôm nay (FS-06.01 §6), kể cả Statistics.

**Sources** — nhóm cuối, lưới 2 cột (iPad 6 ô một hàng) ô 44 như Utilities: icon + tên + **số ảnh** ở mép phải, 13 phụ mono-digit
(`1,102`; board). VoiceOver đọc `NAS Home, 1,102 photos`.
- Nguồn offline: mờ 0,42 + nhãn `Offline` (`T7 · Offline`); thẻ nhớ đang cắm có ảnh mới: dòng phụ `214 new` + chạm mở màn
  nhập FS-20 (người dùng 15/10).
- Ô cuối **Add Source…** mở thẳng sheet Add a Source (FS-19). Chân nhóm: "Photos stay where they are. Nothing is copied or
  moved. Rename, re-index or remove a source in Settings › Sources & Backup."
- Chạm một nguồn = lưới Library lọc theo nguồn đó (cùng điều kiện Source ›), không mở Settings.

## 4. Video tự quay và video tải về

- Video tự quay ở Photos (Media Types › Videos), như app Photos (intent câu 10).
- Photos không tự gợi ý gì; gợi ý chuyển video ở tab Movies ([04 §3](04-movies-tab.md)).

## 5. Trạng thái

| Trạng thái | Photos › Library | Photos › Collections |
|---|---|---|
| chưa cấp quyền ảnh | như FS-09 (giải thích + Open Settings); tab Movies, Music, Search (phần phim, nhạc) vẫn dùng được | hero, album ẩn; Utilities và Sources vẫn hiện (Backup, Local Network, Cloud không cần quyền ảnh) |
| `.limited` | banner Manage (NF-04) | Statistics ghi "based on N photos you shared" (FS-07.01b §5) |
| không nguồn nào ngoài Photos | không đổi | Sources chỉ có ô Photos + Add Source… |
