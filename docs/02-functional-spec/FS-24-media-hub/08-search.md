# FS-24.08 — Search chung: All · Photos · Movies · Music

`FS-24.08` · tier B · mã hiện có: `Features/Library/SearchSuggestionsScreen.swift` (capsule diễn giải), `Domain/Filtering/SearchParser.swift`
· board iPhone `PH_Search` · iPad `IP_Search` · Duo `DI_Search` / `DC_Search` · Mac `MAC_SearchAll`, `MAC_Search` · cập nhật 2026-10-15

**Một câu:** tab Search tìm mọi thứ trong app một lần; kết quả xếp theo loại; gõ kiểu nhiếp ảnh ("Sony 85mm") thì tự về
tìm ảnh với đủ sức mạnh của Search hôm nay.

## 1. Màn

- Ô tìm (placeholder `Photos, Movies and Music`) · dưới ô: scope **All · Photos · Movies · Music**, mặc định All, cao 32.
- Chưa gõ: **Recents** (chung mọi scope, tối đa 10, **Clear**) + câu gợi ý: "Searches Photos, Movies and Music together.
  Type a camera, lens or setting — “Sony 85mm”, “ISO 3200” — to search Photos."
- Gõ ở All: kết quả theo **nhóm**, mỗi nhóm tiêu đề + số + **See All**; nhóm rỗng không vẽ:
  - **Photos** — một hàng thumbnail (iPhone 4, iPad 8) theo đúng truy vấn Search ảnh hôm nay; See All = scope Photos.
  - **Movies** — tối đa 3 hàng: poster/khung · tên · `Clip · 41 min · NAS Home`; có chỗ đang xem thì `18:04`.
  - **Music** — tối đa 3 hàng trộn bài, album, nghệ sĩ: `Song · Phoebe Bridgers · Punisher`, `Album · …`, `Artist · 3 albums on NAS Home`.
- Thứ tự nhóm: Photos · Movies · Music (cố định, không xếp theo số kết quả — chỗ không nhảy khi gõ thêm chữ).
- Chạm: ảnh → Viewer; phim → trang chi tiết (FS-23.08); bài → phát, hàng đợi = các bài trong nhóm Music; album/nghệ sĩ → mở trong tab Music.
- Nhập scope Photos: màn Search ảnh hôm nay nguyên vẹn (gợi ý token, capsule, Advanced Search, Places).

## 2. Cú pháp ảnh

- Bộ phân tích truy vấn hôm nay nhận ra ít nhất một token máy ảnh (hãng, đời máy, lens, tiêu cự, ISO, khẩu, tốc,
  loại file) → scope **tự chuyển sang Photos**, capsule diễn giải giữ (`brand Sony · focal 85mm`), dòng kết quả
  `1,284 photos · Sony · 85mm`.
- Người dùng đã tự chọn scope trong lượt gõ này → không tự chuyển. Xoá hết chữ → về All (scope tự chuyển không dính).
- Từ thường (`kyoto`) không phải token máy ảnh → ở All.

## 3. Khớp

| Loại | Trường tìm |
|---|---|
| Ảnh | như Search hôm nay (FS-01.03: nơi chụp, album, keyword, caption, tên file, thông số) |
| Phim | tên hiện, tên file, năm, `S02E04`, tên bộ (luật FS-23.01 §4: mọi từ phải khớp, bỏ hoa-thường và dấu) |
| Nhạc | tên bài, nghệ sĩ, album artist, album, thể loại; cùng luật bỏ hoa-thường và dấu |

- Chạy hoàn toàn trên index trong máy: chế độ máy bay vẫn ra kết quả, kể cả bài/phim stream (mờ, như ở tab của nó).
- Kết quả cập nhật sau khi ngừng gõ 250 ms; thư viện 55.000 ảnh + 3.000 bài + 200 phim: kết quả All hiện ≤ 300 ms sau đó
  (NF-01). Truy vấn ảnh chạy riêng, nhóm Movies/Music không chờ nhóm Photos.
- Quyền ảnh chưa cấp: nhóm Photos thay bằng một dòng `Allow access to search your photos` + Open Settings; Movies, Music vẫn ra.

## 4. Search trong tab

- Movies có **Search Movies**, Music có **Search Music**: chỉ tìm trong tab đó, ở trên trang chủ của tab, không đi qua tab Search.
- Photos không có ô tìm riêng: giữ Filter and sort + Advanced Filter (Library) — tìm chữ là việc của tab Search.
- iPad/Mac: ô Search trên toolbar = Search chung; trong tab Movies/Music toolbar vẫn là ô chung, ô Search Movies/Music nằm
  đầu nội dung. Mac (`MAC_Search`): scope thêm theo nguồn như hôm nay.
