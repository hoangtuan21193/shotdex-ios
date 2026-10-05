# FS-19.05 — Dữ liệu: cái gì lưu ở đâu

`FS-19.05` · `ShotDex/Data/Database/` · ràng buộc [BD-02](../../01-basic-design/BD-02-database-design.md) · cập nhật 2026-10-04
(sau review `data-migration`)

**Một câu:** một ảnh là một **id** với nhiều bản sao ở nhiều nguồn — asset Photos, file, file NAS; thứ người dùng nhập
nằm ở sidecar và ở bảng riêng khoá theo id đó, **không bao giờ** ở dòng metadata mà lượt index ghi đè.

> App chưa phát hành: không cờ phiên bản (CLAUDE.md). Migration cũ giữ nguyên, chỉ thêm migration mới.

## 1. Id ảnh

- Ảnh Photos đang có **giữ chuỗi id do thư viện hệ thống cấp** làm id. Ảnh mới từ file/NAS nhận **UUID**.
- *Vì* giữ id cũ thì không phải viết lại bảng vệ tinh, cài đặt đã lưu hay payload widget.
- Migration chỉ **tạo** bảng Ảnh, Bản sao, Nguồn, và điền Ảnh + Bản sao từ **hợp mọi id ảnh** có trong mọi bảng — kể cả
  ảnh chưa index dưới quyền `.limited`.
- Bảng metadata chính giữ **một dòng mỗi ảnh**, điền từ **bản sao chính** (bản đầu thứ tự mở, [02 §3](02-identity-and-sidecars.md)).
  Không thêm cột nguồn hay cột ẩn vào nó.

## 2. Nơi chứa

| Dữ liệu | Ở đâu | Đọc lại được? |
|---|---|---|
| File ảnh | thư mục / ổ / server của người dùng | — ShotDex **không ghi** |
| Sao, favorite, keyword, title, caption của ảnh file (và ảnh có cả bản Photos lẫn file) | bảng **Dấu ảnh** **và** sidecar `.xmp`; sang Photos qua đường chờ ghi | có, từ sidecar khi công tắc bật |
| Cờ Pick/Reject (mọi ảnh) | bảng **Cờ** dùng chung; ảnh file ghi thêm ra sidecar | ảnh file: có |
| Recipe (mọi ảnh) | bảng **Recipe** theo id, có lúc đổi; ảnh file ghi thêm vùng ShotDex của sidecar | ảnh file: có |
| Quyền thư mục (bookmark security-scoped) | bảng Nguồn | không — mất là phải Grant Access lại |
| Mật khẩu server | Keychain, như FS-15 | — |
| Thumbnail, preview | cache chung trên đĩa ([01b §5](01b-offline-access-and-cache.md)) | có, dựng lại từ file |

- **Chủ dữ liệu:** ảnh có cả bản Photos lẫn bản file thì bảng ShotDex giữ sao, favorite, keyword; Photos nhận giá trị
  qua đường chờ ghi như [FS-01.12 §5](../FS-01-library/12-rating-and-flags.md).

## 3. Bảng

| Bảng | Giữ gì | Loại |
|---|---|---|
| **Ảnh** | id · lúc tạo · **lúc thành mồ côi** (trống khi còn bản sao) | danh tính; mọi lượt dọn neo vào đây |
| **Bản sao** | id bền · id ảnh · nguồn · loại · id PhotoKit **hoặc** đường dẫn tương đối chuẩn hoá · kích thước · ngày sửa · file ghép cặp · dấu sidecar · online · **ẩn** · lần thấy cuối | kết quả quét |
| **Hash** | bản sao · thuật toán + phiên bản · hash nhanh · hash đầy đủ (có thể trống) · lúc băm | kết quả quét đắt tiền |
| **Nguồn** | loại · tên · bookmark · id ổ · connection · thư mục con (`all`/`top`) · ghép cặp · khi ổ rút · trạng thái · điểm chạy tiếp (thư mục; lượt đọc thư mục không cần — mỗi file ghi riêng một transaction, đọc lại bỏ qua file đã có theo đường dẫn + kích thước + ngày sửa) | người dùng tạo |
| **Dấu ảnh** | id ảnh · sao thật · favorite · title · caption · lúc đổi **từng trường**; keyword một dòng mỗi (ảnh, keyword) | dữ liệu người dùng |
| **Recipe** | id ảnh · recipe · lúc đổi | dữ liệu người dùng |
| **Dấu chờ sidecar** | id ảnh · bản sao · lý do · lúc đặt | dữ liệu người dùng |
| **Album ShotDex** · thành viên | tên, thứ tự · id ảnh | dữ liệu người dùng |
| **Bí danh** | id thua → id thắng | sau mỗi lần gộp |

- **Bản sao** có id bền, duy nhất theo (nguồn, đường dẫn tương đối chuẩn NFC + gấp hoa-thường). Lượt index **cập nhật
  tại chỗ** theo khoá đó, không xoá-rồi-chèn; không khoá ngoại xoá dây chuyền. Đổi tên/chuyển chỗ giữ id bản sao.
- **Hash** riêng bảng, một dòng mỗi bản sao: hash đầy đủ và hash nhanh đều có chỉ mục **thường** — hai bản sao cùng
  nội dung mang cùng hash đầy đủ; luật gộp (§4) giữ **một id ảnh cho mỗi hash đầy đủ**.
- **Duplicates** khoá theo (độ chặt, nguồn, id ảnh); trạng thái lượt quét trùng cũng tách theo nguồn.
- **Ẩn** là cột của bản sao. Ảnh **ẩn khi và chỉ khi mọi bản sao của nó ẩn**.
- Chỉ mục: bản sao theo (nguồn, id ảnh) · bản sao theo (id ảnh, online) · ảnh theo lúc mồ côi (chỉ dòng có giá trị).

## 4. Gộp và tách

- **Gộp** (hash đầy đủ trùng): một transaction; giữ id cũ hơn; dời bản sao sang id thắng; ghi bí danh id thua → id thắng.
- Luật từng bảng khi hai id cùng có dữ liệu:

| Loại | Trường | Luật |
|---|---|---|
| Một giá trị | sao, cờ, favorite, title, caption, recipe | **đổi sau cùng thắng**, so lúc đổi của từng trường |
| Tập hợp | keyword, album, bản sao ẩn | **hợp lại** |
| Dấu chờ sidecar | — | trỏ sang id thắng |

- Mọi chỗ còn giữ id thua (widget, cài đặt đã lưu, smart album lưu id) đi qua bảng bí danh để tìm ảnh.
- **Tách**: một bản sao bị ghi đè bằng ảnh khác trong khi bản sao khác vẫn giữ ảnh cũ → bản bị đổi nhận **id mới**, mang
  **bản chép** dữ liệu người dùng của ảnh cũ. Ảnh chỉ có một bản sao thì không tách ([02 §2](02-identity-and-sidecars.md)).

## 5. Mồ côi và dọn

- File biến mất: dòng bản sao **ở lại** (lần thấy cuối cũ) cùng hash của nó, tới khi dọn — hash đó là thứ nối file quay lại.
- Ảnh mất bản sao cuối → đặt lúc thành mồ côi, không gỡ gì. Bản sao quay lại có hash trùng → xoá dấu mồ côi.
- Dọn lúc mở app: mồ côi > **30 ngày** → gỡ dòng ở mọi bảng dữ liệu người dùng, **trừ** lịch sử upload, lịch sử tải
  về và lịch sử nhập thẻ — chúng sống lâu hơn ảnh như BD-02 nói.
- Ổ offline không làm ảnh mồ côi. Quyền `.limited` như BD-02 §3: không gỡ. Mọi lượt dọn neo vào bảng Ảnh, không vào
  bảng metadata.

## 6. Album, lọc, widget

- Album Collections: **album Photos** (như hôm nay, chỉ ảnh có bản Photos) và **album ShotDex** chứa ảnh mọi nguồn.
  New Album: chỉ có nguồn Photos → album Photos; có nguồn khác → album ShotDex. Ảnh chỉ-file: hàng album Photos mờ,
  câu "Photos albums can only hold Photos Library items."
- Lọc keyword đọc **cả hai** bảng: gương keyword Photos và keyword ở Dấu ảnh.
- Widget cần **bộ nạp ảnh file** (thumbnail từ cache chung); id thua đi qua bí danh.

## 7. Luật giữ nguyên từ BD-02

- Lượt index ghi đè **cả dòng** metadata — không cột nào ở đó giữ thứ chỉ người dùng biết.
- Tổng hợp làm **trong truy vấn**. "Đếm một lần" = đếm theo id ảnh; chọn một nguồn = ảnh có bản sao ở nguồn đó.
- Mọi phép sắp kết thúc bằng id ảnh làm tiebreaker (NF-01 luật 7).
- Smart album thêm điều kiện **Source**: giải mã khoan dung như BD-02 §4; bỏ một nguồn không biến album thành "mọi ảnh".
- Clear Local Metadata Index: xoá metadata, đọc lại; **giữ** Ảnh, Bản sao (id, cột ẩn), Hash, Nguồn, Dấu ảnh, Cờ, Recipe, dấu
  chờ, album, bí danh.

## 8. Test phải có

1. Migration ra đúng hình bảng; Ảnh + Bản sao điền đủ từ hợp id của mọi bảng, kể cả ảnh `.limited` chưa index.
2. Dữ liệu người dùng còn nguyên sau index lại và sau Clear Local Metadata Index.
3. Gộp có va chạm ở **mọi** bảng vệ tinh: trường một giá trị theo lúc đổi, keyword/album/ẩn hợp lại, dấu chờ trỏ đúng.
4. Dọn ở 29 và 31 ngày: 29 còn đủ; 31 gỡ hết trừ lịch sử upload, tải về, nhập thẻ.
5. Đổi tên và chuyển chỗ trong nguồn giữ id bản sao.
6. Ảnh hai bản sao: một dòng trong lưới, đếm một lần ở All, đếm một lần ở **mỗi** nguồn.
7. Ảnh có bản sao ở hai nguồn nằm được trong nhóm trùng của **cả hai** nguồn.
