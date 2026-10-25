# FS-22.05 — Không chép trùng giữa các máy

`FS-22.05` · board `PH_Backup` (1/6, trạng thái `Checking <connection>`) · `PH_BackupRunning` (6/6, dòng **Already on <connection>**) ·
`PH_BackupNew` (2/6, chú thích dưới Folder) · đề xuất `ShotDex/Domain/Backup/BackupContentIndex.swift`,
`BackupShared/BackupIndexFile.swift` · cập nhật 2026-10-13

**Một câu:** hai máy (hoặc nhiều hơn) backup vào cùng một folder trên NAS thì một ảnh đã có ở bất kỳ đâu trong folder đó
— do máy nào chép, hay có sẵn từ trước — không bị chép lần nữa; so bằng **nội dung** (SHA-256), không bằng tên.

Nguồn: người dùng 2026-10-12 ("máy của vợ tôi cũng backup lên cùng thư mục ở NAS … có thể phát hiện và skip ảnh trùng
không … ảnh trùng nhưng ở khác thư mục … cái này quan trọng tôi không muốn trùng"); chọn: *giống hệt, mọi thư mục* ·
*quét file có sẵn trên NAS một lần lúc tạo job* · *phạm vi là folder đích của job*.

## 1. Trùng là gì

- **Trùng** = cùng SHA-256 với một file đang nằm trong folder đích của job (mọi tầng con), bất kể tên, đường dẫn, máy nào
  chép, hay file có sẵn từ trước khi dùng ShotDex.
- Không trùng: cùng ảnh nhưng đã bị nén lại (gửi qua Messages, Zalo, AirDrop đổi định dạng) — byte khác. *Vì so bằng hình
  dễ bỏ nhầm ảnh chụp liên tiếp; Backup không được mất ảnh.* Những ảnh đó vẫn được chép.
- Phạm vi chỉ là folder đích **của job này**. Hai máy muốn không trùng nhau thì chọn **cùng một folder** (Organize xếp
  theo ngày nên ảnh của hai người vẫn nằm đúng chỗ). Chú thích dưới dòng Folder ở 2/6: *"Photos already in this folder —
  from another iPhone or copied earlier — are skipped."*
- Luôn bật, không có công tắc. *Vì không ai muốn bản trùng; tắt đi chỉ tốn chỗ NAS.*

## 2. Sổ chung trên NAS

- Mỗi máy ghi những gì nó biết (file nó chép, file nó đã băm) vào folder ẩn **`.shotdex/backup-index/`** nằm ngay trong
  folder đích. Mỗi máy chỉ ghi file của chính nó, theo đoạn: `<mã máy>-<số thứ tự>.jsonl`, một đoạn mới mỗi lượt chạy có
  thay đổi; không máy nào sửa file của máy khác. *Vì SMB/WebDAV không có khoá ghi; hai máy cùng ghi một file sẽ mất dòng.*
- Một dòng = một file ở đích: đường dẫn tương đối, cỡ, ngày sửa ở đích, SHA-256, máy ghi, lúc ghi.
- Đầu mỗi lượt: đọc các đoạn chưa đọc (theo tên), gộp vào bản sao cục bộ (03 §1, bảng **Nội dung ở đích**). Đọc lại toàn
  bộ khi bản sao cục bộ mất (cài lại app, đổi máy).
- Mã máy: một UUID tạo lần đầu, lưu trong Keychain của app — cài lại app trên cùng máy vẫn giữ.
- Tên đoạn: `<mã máy>-000001.jsonl`, số kế = số lớn nhất của máy đó đang có trong folder + 1 (cài lại vẫn đếm tiếp).
  Ghi qua file part rồi đọc lại SHA-256 rồi đổi tên, nên máy khác không bao giờ đọc nửa đoạn.
- Ghi lúc nào: cuối lượt khi còn kết nối (xong, hoặc dừng vì Wi‑Fi/sạc/chỗ trống). Pause hay mất mạng thì những gì đã biết
  nằm chờ trong database, lượt sau ghi — kể cả lượt không có ảnh mới (khi đó nối NAS chỉ để ghi đoạn đó).
- Đọc sổ chung chỉ ở lượt có file cần chép, sau khi liệt kê cây (§3).
- Dòng sổ chỉ gắn SHA cho file đã liệt kê khi cỡ khớp (và ngày sửa khớp, khi cả hai biết); file chưa liệt kê thì nhận là
  có, nhưng vẫn hỏi lại NAS trước khi tính là trùng (§4 bước 3).
- Folder `.shotdex` ẩn với Backup: không liệt kê, không băm, không tính vào "found".
- Lỗi đọc sổ chung (file hỏng, dòng lạ): bỏ dòng đó, không dừng job. Lỗi ghi: thử lại lượt sau; file vẫn được chép.

## 3. File có sẵn trên NAS (không do ShotDex chép)

- **Lúc tạo job** (và khi đổi folder đích): liệt kê cả cây folder đích một lần — chỉ **tên + cỡ + ngày sửa**, không đọc
  nội dung. Trạng thái 1/6: `Checking NAS Home · 12,408 files` (tên connection, đếm lên), chưa chép file nào trong lúc này.
- **Không băm cả NAS.** Một file ở NAS chỉ được đọc để băm khi có một file sắp chép có **cùng cỡ** với nó mà nó chưa có
  SHA-256. Kết quả băm ghi vào sổ chung (§2) để máy khác khỏi đọc lại. *Vì 500 GB qua Wi‑Fi là vài giờ; hai file khác
  nhau mà trùng cỡ đến từng byte là hiếm.*
- Liệt kê lại cả cây **mỗi ngày một lần** (khi có lượt chạy), để bắt file người khác thêm bằng công cụ khác. Lượt liệt kê
  lại chạy nền như lượt chép, theo cùng điều kiện Wi‑Fi/sạc.
- Chỉ liệt kê khi lượt có file cần chép: không có gì mới thì không nối NAS chỉ để liệt kê. Bỏ qua mục ẩn (tên bắt đầu
  bằng `.`, gồm `.shotdex/`, `.DS_Store`, `._*`) và file `.shotdex-part`.
- Lần liệt kê mới: file không còn thì quên; file đổi cỡ (hoặc đổi ngày sửa, khi đã biết ngày) thì bỏ SHA cũ.

## 4. Chép một file — thêm bước so nội dung

Chen vào giữa FS-22.02 §2, sau khi bản gốc đã nằm ở thư mục tạm:

1. Dò trùng tên + cỡ ở đúng đường dẫn đích → `found` (như cũ).
2. Băm file tạm (SHA-256, đọc trên máy theo khối 1 MB; Pause dừng giữa chừng như FS-22.02 §1).
3. Tra SHA-256 trong bản sao cục bộ của sổ chung. Có → kiểm file đó **còn ở đích với đúng cỡ** (một lệnh hỏi thông tin
   file). Còn → **bỏ qua**: sổ ghi `duplicate` + đường dẫn file đã có; với nguồn Photos thêm dòng lịch sử upload FS-15
   trỏ vào file đó (nội dung đã khớp SHA-256, nên Free Up Space tính được). Mất hoặc lệch cỡ → xoá dòng đó khỏi bản sao
   cục bộ, đi tiếp.
4. Không có SHA khớp nhưng có file ở đích **cùng cỡ chưa băm** → đọc và băm những file đó (§3), rồi tra lại bước 3.
5. Vẫn không trùng → đẩy lên như FS-22.02 §2; xong thì thêm dòng vào sổ chung của máy này. Đích nằm trong một nguồn server
   (FS-19) → lượt quét nguồn đó lấy SHA-256 trong sổ (và sổ chung) theo đường dẫn + cỡ cho bản sao server, không đọc lại
   file ([FS-19.07 §5](../FS-19-photo-sources/07-on-server-check.md)).
6. Xoá file tạm — như cũ, trên máy không bao giờ quá 1 file.

- Trong cùng một lượt, file vừa chép vào bản sao cục bộ ngay, nên hai mục giống hệt trong cùng thư viện chỉ chép một lần.
- Tải từ iCloud vẫn xảy ra với một mục trùng (phải có byte mới băm được), nhưng không đẩy byte nào lên.
- Phần mở rộng tải nền (iOS 26.1+, FS-22.02 §3) không băm trước được — Photos tự đẩy. Lượt mở app kiểm file
  `.shotdex-part` của nó như cũ; nếu SHA-256 của part đã có ở chỗ khác trong đích → **xoá part** (file tạm của chính
  ShotDex, không phải ảnh của người dùng), sổ ghi `duplicate`. Không có tên thật nào thành bản trùng.

## 5. Hiển thị

- 1/6: `Checking NAS Home · 12,408 files` lúc liệt kê (§3). Dòng 2: `before the first copy` lần đầu, `daily check` các lần sau.
- 6/6: dưới **Backed Up** thêm dòng **Already on NAS Home · 312** (chỉ khi có ít nhất 1) — chạm mở danh sách: tên file ở
  máy → đường dẫn đã có ở đích.
- Chữ dùng **tên connection** như mọi trạng thái khác (`Can't Reach NAS Home`), vì đích có thể là folder Files chứ không
  phải NAS (người dùng 2026-10-13).
- Tổng ở 6/6 và đếm "N items" ở 1/6 tính cả `duplicate` là đã xong.
- Không báo lỗi, không hỏi người dùng khi bỏ qua một file trùng.

## 6. Giới hạn đã biết

- Hai máy chép **cùng một ảnh trong cùng một lúc** (chưa máy nào kịp ghi sổ chung) → cả hai bản có thể lên. Lượt sau
  không xoá bản nào. *Vì Backup không xoá ở đích.*
- File ở NAS bị sửa nội dung mà giữ nguyên cỡ và ngày sửa → sổ chung giữ SHA cũ; ảnh mới giống SHA cũ sẽ bị bỏ qua nhầm.
  Rất hiếm (công cụ nào sửa ảnh mà giữ nguyên ngày sửa); lần liệt kê hằng ngày thấy ngày sửa đổi thì bỏ SHA cũ.
- Hai máy chọn hai folder khác nhau (`Family/Tuan`, `Family/Vo`) → không thấy nhau. Đúng như phạm vi đã chọn.
