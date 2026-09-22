# FS-03.02 — Film simulation và preset

`FS-03.02` · `Domain/Editing/FilmSimulation.swift` · `LookPresetStore` · `EditorFiltersPanel`
· test `FilmSimulationTests` · `LookPresetStoreTests` · cập nhật 2026-09-22

**Một câu:** 49 look màu, năm cái được **đo** từ ảnh tham chiếu và phần còn lại chỉnh tay — tài liệu ghi rõ
cái nào là cái nào.

## 1. Quy tắc

- **Một look là một mô tả màu, không phải một chuỗi filter dựng sẵn.**
- **Look chạy dưới dạng bảng tra màu 3D 33³**, một pass duy nhất: thumbnail 150px, preview trên máy và bản
  lưu full-res **chắc chắn cùng một màu**.
- **Tên strip không mang tên hãng** — heading là chữ của ShotDex, gắn tên hãng lên đó là mời khiếu nại
  nhãn hiệu; tên từng look thì không sao.
- **Preset của người dùng chỉ mang "cái nhìn"** (tone, màu, curve, film look) — crop, mask, markup, nét vẽ
  ở lại với ảnh.
- Look đã đo thì **không chỉnh tay đè lên số đo**.

## 2. 49 look, ba strip

| Strip | Số look | Nội dung |
|---|---|---|
| Basic | 10 | Original · Vivid · Vivid Warm/Cool · Dramatic · Dramatic Warm/Cool · Mono · Silvertone · Noir — **không đi qua bảng tra màu**, nên recipe lưu trước khi có film sim vẫn render y như cũ |
| Film | 24 | 10 màu của một máy Fujifilm X-T5 · 12 Leica Looks · 8 stock phim |
| B&W | 15 | 9 đơn sắc Fujifilm + phần còn lại |

- Chia strip theo **look đó LÀ gì**, không theo hãng: bản in bạc nhuộm màu nằm cùng B&W dù của hãng nào
  (có test khoá bất biến này).
- **Không có REALA ACE** — mode đó không có trên máy tham chiếu.
- Slider **Intensity** (blend với ảnh chưa filter) áp cho mọi look.

## 3. Năm look được đo

| Look | Sai số (RMSE) | Số scene |
|---|---|---|
| Classic Neg. | 0,013 | 5 (+4 cho hiệu với Nostalgic) |
| Nostalgic Neg. | 0,008 | 5 |
| ASTIA | 0,0087 | 1 |
| Classic Chrome | 0,0066 | 1 |
| ETERNA | 0,0055 | 1 |

**Cách đo**: 10 sheet so sánh đã publish, **cùng một khung hình render bằng bản neutral và bằng
simulation**. Mỗi panel bị crop/scale khác nhau nên **không so pixel-đối-pixel** — mọi mẫu lấy theo **toạ
độ scene trong rect riêng của từng panel**, nên ghép đúng cùng một điểm bất kể panel publish ở cỡ nào.

- **165.000 cặp pixel**, bin thành lưới **tone × hue (8×13)**, rồi fit **chính kiểu dữ liệu app dùng để
  render** vào lưới đó bằng coordinate descent, có bound + ridge; band chiếm < 1,2% dữ liệu thì khoá ở
  identity.
- **Ngưỡng nhận**: sai số ≤ 0,014 · curve đơn điệu · hai panel trên sheet khớp **rank correlation ≥ 0,90**.
  Dùng Spearman chứ không Pearson — Pearson phạt oan đúng những look đổi contrast mạnh.

**Không đo được, giữ chỉnh tay, kèm lý do**: Velvia (fit không hội tụ, ra curve không đơn điệu — scene
tham chiếu quá đặc biệt) · ETERNA Bleach Bypass (sai số 0,025) · PRO Neg. Hi và Std (sheet tham chiếu là
chân dung studio nền đen ~90% khung → không có dải tone để đo) · PROVIA (nó **là** baseline).

## 4. Số đo lật bốn quan niệm

1. **ASTIA**: chữ "/Soft" là nghĩa đen — cả đỏ lẫn lục ra **contrast âm**, tức look *làm phẳng* tone;
   màu đến từ saturation (×1,12).
2. **Classic Chrome**: chữ ký là **desaturate toàn cục về 0,82 + reshape riêng kênh blue** (nâng đáy, làm
   phẳng, shoulder dài → shadow lạnh, highlight ấm, không đụng hue). Trong dữ liệu **không hề có** chuyện
   "dìm riêng màu đỏ" như bản chỉnh tay đã bịa.
3. **Classic Neg.**: highlight **ấm do đỏ dẫn** (đỏ tăng gấp đôi lục, gấp bốn lam) — **không phải magenta**
   như marketing nói; shadow cyan-green thì đúng. Green quay **+29° về phía cyan**, và **cyan mất 1/3
   saturation** rồi sáng lên — chính hành vi trời/mù này mới làm nên danh tiếng của look.
4. **ETERNA** đúng như tiếng tăm: mọi kênh nâng khỏi đen, mọi trần hạ xuống, saturation 0,78.

**Cấu trúc thật của Classic Neg.**: red là curve dốc nhất (contrast 0,90 — đúng mức trần mà S-curve còn
đơn điệu), green có đáy cao nhất. Green nằm trên red ở đáy → shadow cyan-green; red vượt cả hai ở đỉnh →
highlight ấm. **Đảo một trong hai thứ tự đó là look lộn ngược.**

**Nostalgic Neg. không phải Classic Neg. đảo dấu**: red nâng khỏi đáy còn blue gần như không, và blue bị
chặn trần → **amber chạy từ shadow sâu nhất tới highlight sáng nhất**. Blue bị **làm phẳng** chứ không
được nâng. Gain của red đo được 1,014 nhưng **ship ở 1,0** để đỉnh roll-off chứ không clip phẳng 1% cuối.

## 5. Look không có số đo

- **12 Leica Looks: không có cặp before/after publish nào** → theo mô tả chính hãng. Ba look đã sửa vì bản
  đầu mâu thuẫn thẳng với mô tả: Chrome ("muted palette" — bản đầu làm thành no màu, gần như ngược),
  Classic (phần "washed-out" chính là nâng đáy: contrast cao **và** đen không tới đen), Contemporary
  ("subtle reddish tint" — bản đầu cho shadow xanh lạnh).
- **Stock phim** (Portra, Kodachrome, Ektar, Superia, CineStill, Tri-X, HP5): **về bản chất không tồn tại
  ảnh "before"** — phim là chính môi trường ghi hình, nên mọi mô phỏng đều là diễn giải.

## 6. Một look mô tả năm thứ

Bộ điều khiển màu chuẩn không làm được năm thứ này, nên look là kiểu dữ liệu riêng (thuần, có test):

1. **Tone curve riêng từng kênh** — ba lớp thuốc nhuộm không dùng chung một curve; đây là 80% "chất film".
2. **Crosstalk giữa các lớp** — đỏ trầm + vàng ngả olive của Classic Chrome là crosstalk, không phải giảm
   saturation.
3. **Desaturate vùng highlight** — thuốc nhuộm hết dải nên màu sáng nhạt dần về trắng; màu sáng mà vẫn no
   là dấu hiệu "digital" lộ nhất.
4. **Split tone** shadow/highlight riêng.
5. **Dịch hue theo dải** — cosine falloff và cộng dồn nên liệt kê thứ tự nào cũng ra kết quả như nhau.

Đây là mô phỏng chỉnh theo ảnh tham chiếu, **không phải profile đo mật độ** — giống đúng bản chất "film
simulation" của chính hãng máy.

## 7. Bảng tra màu

- Bảng **575 KB**, dựng **3 ms** (mono) đến **~13 ms** (look nhiều hue band), cache tối đa **24** look.
- 24 = đúng một strip đầy, nên render lại swatch sau khi slider dừng thì **dùng lại bảng** thay vì dựng
  lại hai chục cái.
- **33 là cỡ chuẩn của LUT thương mại**: số lẻ nên xám trung tính được sample đúng tâm.
- Curve được chỉnh trên giá trị đã gamma-encode nên bảng áp trong không gian sRGB.

## 8. Panel Presets

- **Bỏ hàng chip category** — gộp cả 49 look vào **một dải cuộn ngang**, mở ra tự cuộn tới look đang chọn.
- Trên cùng là dòng **Amount** (chỉ khi có look, 0…100%, có mốc 100).
- Mỗi look là **card dọc**: thumbnail 62×62 (ảnh đang sửa qua look đó) + tên dưới; chọn = viền accent 2pt
  + dấu tick góc trên-phải.
- Thumbnail render **lần lượt từng category** (mỗi batch ≤ 24 look nên không làm tràn cache bảng), **bỏ
  mask** nhưng **giữ tone/màu/crop** nên luôn dự báo đúng. Dựng lại khi tone/màu/crop/nguồn đổi, **không**
  khi đổi look hay Amount. Chưa có thumbnail thì vẽ gradient hai tông sinh từ chính look.

## 9. My Looks

Nằm **trên cùng** panel Presets, trước dải 49 film look. Lưu JSON trong `UserDefaults`.

- Header **My Looks** + nút **＋ Save Current** (tắt khi recipe là identity — tile không làm gì đọc như
  tile hỏng). Chưa có preset nào thì thay dải chip bằng dòng *"Save an edit here and it can be put on any
  photo."*
- Chạm = áp look lên ảnh đang mở; giữ = Delete.
- **Lưu look-only**: recipe bị cắt lát trước khi lưu **và** khi áp — preset mang theo crop 4:5 + mask
  khuôn mặt của một tấm chân dung sẽ phá mọi tấm nó chạm vào. Hệ quả: recipe **chỉ có crop thì không lưu
  được** (sau khi cắt lát chẳng còn gì).
- Trùng tên (không phân biệt hoa thường) thì **ghi đè** — hai chip "Golden Hour" là hai chip người dùng
  không phân biệt nổi. Tên trắng bị từ chối, tên được trim. Danh sách xếp **mới nhất trước**.

## 10. Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../../README.md#6-việc-còn-nợ).
