# FS-19.05 — Dữ liệu: cái gì lưu ở đâu

`FS-19.05` · `ShotDex/Data/Database/` · ràng buộc [BD-02](../../01-basic-design/BD-02-database-design.md) · cập nhật 2026-10-04

**Một câu:** một ảnh là một **id nội bộ** của ShotDex với nhiều bản sao ở nhiều nguồn — asset Photos, file, file NAS;
thứ người dùng nhập nằm ở sidecar và ở bảng riêng khoá theo id đó, **không bao giờ** ở dòng metadata mà lượt index ghi đè.

> Mọi quyết định schema dưới đây cần agent **`data-migration`** duyệt trước `/plan`. App chưa phát hành: không viết bước
> chuyển dữ liệu cũ, không cờ phiên bản (CLAUDE.md). Migration cũ giữ nguyên, chỉ thêm migration mới.

## 1. Nơi chứa

| Dữ liệu | Ở đâu | Đọc lại được? |
|---|---|---|
| File ảnh | thư mục / ổ / server của người dùng | — ShotDex **không ghi** |
| Sao, keyword, title, caption, favorite (ảnh file) | bảng **Dấu ảnh file** **và** sidecar `.xmp` | có, từ sidecar (khi công tắc bật) |
| Cờ Pick/Reject (mọi ảnh) | bảng **Cờ** dùng chung; ảnh file ghi thêm ra sidecar | ảnh file: có; ảnh Photos: không |
| Recipe (mọi ảnh) | database theo id ảnh; ảnh file ghi thêm vùng ShotDex của sidecar ([02 §8](02-identity-and-sidecars.md)) | ảnh file: có |
| Dấu chờ ghi sidecar (offline, chỉ đọc, xung đột, hết chỗ) | bảng riêng | **không** — dữ liệu người dùng |
| Quyền thư mục (bookmark security-scoped) | bảng nguồn | không — mất là phải Grant Access lại |
| Mật khẩu server | Keychain, như FS-15 | — |
| Thumbnail, preview | cache chung trên đĩa ([01b §5](01b-offline-access-and-cache.md)), không vào database | có, dựng lại từ file |

## 2. Bảng

| Bảng | Giữ gì | Loại |
|---|---|---|
| **Ảnh** | id nội bộ · hash nhanh · hash đầy đủ (có thể trống) · thuật toán hash · lúc tạo · **lúc thành mồ côi** (trống khi còn bản sao) | danh tính — không lượt index nào xoá |
| **Bản sao** | id ảnh · nguồn · loại (asset Photos / file / file server) · id PhotoKit **hoặc** đường dẫn tương đối · kích thước · ngày sửa · file ghép cặp · sidecar + dấu sidecar (ngày sửa + hash) · online · lần thấy cuối · hash nhanh · hash đầy đủ · lúc băm | kết quả quét; cột hash là kết quả đắt tiền |
| **Nguồn** | loại (Photos / thư mục / ổ / server) · tên · bookmark · id ổ · connection · thư mục con · ghép cặp · khi ổ rút (giữ / ẩn) · trạng thái · lần đọc cuối · điểm chạy tiếp | người dùng tạo |
| **Dấu ảnh file** | id ảnh · sao thật (kể cả khi Rejected) · keyword · title · caption · favorite · lúc đổi từng trường | dữ liệu người dùng |
| **Dấu chờ sidecar** | id ảnh · bản sao · lý do (offline / chỉ đọc / xung đột / hết chỗ) · lúc đặt | dữ liệu người dùng |
| **Ảnh ẩn** | id ảnh · bản sao NAS · lúc ẩn | dữ liệu người dùng |
| **Album ShotDex** · **thành viên album** | tên, thứ tự · id ảnh | dữ liệu người dùng |

- Lượt index chỉ cập nhật cột quét của **Bản sao**; hash của một bản sao chỉ xoá khi kích thước hoặc ngày sửa đổi.
- Dấu chờ chỉ ghi **bản sao nào** cần ghi, không ghi giá trị: lúc bản sao online lại, giá trị lấy từ Dấu ảnh file, Cờ,
  recipe hiện hành ([02 §7](02-identity-and-sidecars.md)).
- Gỡ dòng của ảnh **bị xoá thật** (Move/Hide trong ShotDex hết mọi bản) cùng lúc gỡ dòng metadata.
- Ảnh **mất bản sao cuối** (file chuyển đi, Remove Source, file bị xoá ngoài ShotDex): đặt **lúc thành mồ côi**, không gỡ
  gì. Bản sao quay lại có hash trùng → xoá dấu mồ côi. Dọn lúc mở app: mồ côi > **30 ngày** → gỡ dòng ở mọi bảng.
- Ổ offline không làm ảnh mồ côi — bản sao còn, chỉ online = không. Quyền `.limited` của Photos như BD-02 §3: không gỡ.

## 3. Id ảnh nội bộ

Hôm nay mọi bảng khoá theo **id do thư viện hệ thống cấp** (BD-02 §2). Từ FS-19 mọi bảng khoá theo **id nội bộ**; id
PhotoKit thành một bản sao.

- Hash đổi (app khác lưu đè điểm ảnh, [02 §2](02-identity-and-sidecars.md)) → id giữ, chỉ hash của bản sao đổi.
- Gộp hai ảnh khi hash đầy đủ trùng: giữ id cũ hơn, dời bản sao và dòng vệ tinh của id kia sang; hai bên cùng có một
  trường thì **giá trị đổi sau cùng thắng**.
- Bảng vệ tinh phải đổi khoá cùng lượt: dấu vân tay, nhóm trùng, Cờ, Sao chờ lên Photos, gương keyword, lịch sử
  upload/tải về và dấu "In Library" (FS-15, FS-17), payload widget (EX-02), smart album lưu id.
- Sao chờ lên Photos vẫn chỉ cho bản sao Photos ([FS-01.12 §4](../FS-01-library/12-rating-and-flags.md)). Ảnh có cả bản
  Photos và bản file: một sao chung; ghi lên Photos theo FS-01.12 và ra sidecar theo [02 §5](02-identity-and-sidecars.md).
- **Cờ** dùng chung bảng Cờ hiện có cho mọi ảnh. Ảnh file ghi thêm ra sidecar: Reject = sao −1, Pick = vùng ShotDex.
- Sao, keyword của ảnh file **luôn** ở bảng Dấu ảnh file, bất kể công tắc sidecar. *Vì* sidecar có thể offline, chỉ
  đọc hay bị tắt — bảng là chỗ duy nhất luôn đúng.

## 4. Album

- Album trong Collections có hai loại: **album Photos** (PhotoKit, như hôm nay, chỉ chứa ảnh có bản Photos) và **album
  ShotDex** (bảng mới) chứa ảnh mọi nguồn.
- New Album: thư viện chỉ có nguồn Photos → album Photos như hôm nay; có thêm nguồn khác → album ShotDex.
- Add to Album với album Photos và ảnh không có bản Photos: hàng album đó mờ, câu "Photos albums can only hold Photos
  Library items." Ảnh có bản Photos thì bản đó vào album Photos.
- Album ShotDex không đồng bộ iCloud; album Photos vẫn hiện và vẫn đồng bộ như hôm nay.

## 5. Luật giữ nguyên từ BD-02

- Lượt index ghi đè **cả dòng** metadata — nên không cột nào ở đó được giữ thứ chỉ người dùng biết.
- Tổng hợp (theo nguồn, theo máy, đếm một lần) làm **trong truy vấn**. "Đếm một lần" = đếm theo id ảnh, không theo bản sao.
- Mọi phép sắp kết thúc bằng id ảnh làm tiebreaker (NF-01 luật 7) — id nội bộ so được ổn định.
- Smart album: thêm trường điều kiện **Source** thì giải mã khoan dung như BD-02 §4; bỏ một nguồn không được biến album
  thành "mọi ảnh".
- Clear Local Metadata Index: xoá metadata và cột quét của bản sao rồi đọc lại; **giữ** bảng Ảnh, hash, nguồn,
  bookmark, Dấu ảnh file, Cờ, dấu chờ, ảnh ẩn, album, recipe. Câu "Your photos and files are not affected" đúng nhờ luật này.
