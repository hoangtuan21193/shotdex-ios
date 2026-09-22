# BD-05 — Sensor format, crop factor, tiêu cự tương đương

`BD-05` · `ShotDex/Domain/SensorLookup.swift` · `EquivalentFocalLength.swift`
· test `SensorLookupTests` · `EquivalentFocalLengthTests` · cập nhật 2026-09-22

**Một câu:** hai phép tính là lý do app tồn tại, cộng cách xử lý camera chưa biết.

## 1. Quy tắc

- Sensor format tra từ `Resources/sensor_database.json` (bundle sẵn, load vào DB lúc khởi tạo).
- **Normalize camera model trước khi lookup**: bỏ khoảng trắng thừa, không phân biệt hoa thường,
  chuẩn hoá prefix hãng, hỗ trợ alias.
- Không tra được → format `Unknown`, crop factor `null`, cho map tay trong Settings và lưu lại.

## 2. Sensor database

Cấu trúc record: `manufacturer · camera model · sensor format · crop factor`.

| Ví dụ | Format | Crop |
|---|---|---|
| Canon EOS R6 Mark II | Full Frame | 1.0× |
| Sony A6700 | APS-C | 1.5× |
| Canon EOS R7 | APS-C | 1.6× |
| OM System OM-1 | Micro Four Thirds | 2.0× |
| Sony RX100 VII | 1-inch | 2.7× |

Phạm vi ~580 model: mirrorless/DSLR/compact (Canon kèm dạng EXIF ngắn `EOS R5m2` và tên Rebel/Kiss theo
vùng, Sony ILCE/DSC/NEX/SLT, Nikon, Fujifilm, Olympus/OM System, Panasonic DMC/DC, Leica, Ricoh/Pentax,
Hasselblad, Sigma), action cam và drone (GoPro, DJI), điện thoại/tablet (iPhone/iPad/iPod touch, Samsung
theo mã SM-, Google Pixel, BlackBerry, Lumia).

**App update mang database mới tự sửa ảnh đã index, không cần reindex**:
Một lượt chạy lúc khởi động chạy lúc khởi động,
cập nhật sensor format, crop factor và tiêu cự tương đương cho model vừa được biết.

## 3. Tiêu cự tương đương Full Frame

```
fullFrameEquivalent = actualFocalLength × cropFactor
```

25mm trên MFT → 50mm · 50mm trên APS-C 1.5× → 75mm · 50mm trên Canon APS-C 1.6× → 80mm ·
150mm trên MFT → 300mm.

Thứ tự ưu tiên:

1. trường tiêu cự quy đổi 35mm từ EXIF nếu có và hợp lệ.
2. Tính từ tiêu cự thật × crop factor.
3. Không biết crop factor → **không hiển thị** tiêu cự tương đương.

Settings chọn hiển thị Actual hay Full-frame equivalent
([FS-08](../02-functional-spec/FS-08-settings/README.md)).
