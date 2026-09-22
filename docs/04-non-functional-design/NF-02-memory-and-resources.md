# NF-02 — Bộ nhớ và tài nguyên

`NF-02` · `ShotDexKit/` · `ShotDexEdit/` · `Data/Sources/PhotoRenderService.swift` · cập nhật 2026-09-22

**Một câu:** trần bộ nhớ theo từng target, vòng đời bộ nhớ đệm, và luật cho những thứ nặng nhất.

## 1. Quy tắc

- **Mọi bộ nhớ đệm ảnh phải có trần** — theo chi phí hoặc theo số khối; **không** cái nào được lớn theo số
  ảnh trong thư viện.
- **Nhả sạch khi hệ thống báo thiếu bộ nhớ.**
- Xin thumbnail **đúng cỡ ô**, ở độ phân giải thật của màn; **không** xin bản lớn nhất trừ khi người dùng
  chủ động phóng (ảnh toàn cảnh là ngoại lệ có chủ ý).
- Kích thước màn và cửa sổ hỏi qua lớp riêng của app
  ([OV-02](../00-overview/OV-02-platform-and-technology.md)).
- **Đường lưu không được giữ ảnh nén song song với ảnh đã render** — ở app là lãng phí, trong extension
  đang render nguồn 48MP là khác biệt giữa "lưu được" và "bị giết đúng lúc lưu"
  ([FS-03.06](../02-functional-spec/FS-03-photo-editor/06-saving-recipe-and-live-photo.md)).

## 2. Dọn dẹp và tái dùng

- **Quét thư mục tạm mồ côi lúc app khởi động**: xoá mọi thư mục tạm còn sót của các công cụ (sửa ảnh, kéo
  thả, nhận thả, video). Mỗi công cụ vẫn tự dọn phần của mình, nhưng **tắt app đột ngột, crash, hoặc bị hệ
  thống giết** thì không ai dọn — mà một thư mục sót có thể đang giữ một file RAW đã chép. **Chỉ an toàn ở
  thời điểm khởi động**, vì lúc đó không phiên làm việc nào còn sống. Có test.
- **Giữ lại ba phiên sửa ảnh gần nhất** (ảnh đang xem và hai ảnh kề), và hâm nóng trước hai ảnh bên cạnh.
  Bộ nhớ đệm chỉ giữ **phần chuẩn bị của hệ thống và thư mục tạm**, không giữ ảnh đã giải mã, nên tốn ít và
  có trần. Kết thúc một phiên **không** xoá thứ còn trong bộ đệm (xoá thư mục tạm thì lần mở sau không đọc
  được file nữa); toàn bộ được nhả khi rời editor.

## 3. Trần theo target

| Target | Trần | Hệ quả |
|---|---|---|
| App | theo thiết bị | không giữ nhiều bản ảnh đầy đủ cùng lúc |
| Extension sửa ảnh | **~120 MB** *(cần xác nhận trên máy đích)* | render nguồn 48MP phải làm theo dòng |
| Extension chia sẻ và widget | chặt hơn app | widget chỉ đọc dữ liệu app đã ghi sẵn |

Bộ nhớ đệm bảng màu film: tối đa **24 look**.

## 4. Ràng buộc còn treo

- Không có test bộ nhớ, và không có phép kiểm ngưỡng khi xuất video hay khi render 48MP trong extension
  *(cần xác nhận)*.
