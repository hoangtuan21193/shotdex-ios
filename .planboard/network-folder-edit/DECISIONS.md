# FS-17.06 — Sửa và xuất ảnh trên server — các quyết định

| ID | Quyết định | Kết quả | Lựa chọn |
|---|---|---|---|
| D1 | Editor và các công cụ nhận ảnh server bằng cách nào | OK | Nguồn dạng file (song song với PHAsset) |
| D2 | Làm trong mấy đợt | OK | Hai đợt: editor và nhóm file trước, collage/video/combine sau |
| D3 | Tải về bản tạm | OK | — |
| D4 | Đích Photos Library lưu thành gì | OK | Asset phẳng: chỉ bản render |
| D5 | Ghi lên server bằng code nào | OK | Bộ ghi file cục bộ riêng, dùng lại path và client |
| D6 | Ghi lịch sử upload cho file xuất | OK | Không ghi, sửa spec |
| D7 | Nhận biết folder 'chỉ đọc' | OK | Không thử trước; lỗi quyền báo ở đích, có Choose Another Folder |
| D8 | Chọn folder khác | OK | — |
| D9 | Một nguồn cho tên và glyph của lệnh | OK | Định nghĩa lệnh dùng chung |
| D10 | Tiến độ tải hiện ở đâu | OK | Sheet tiến độ như Import |
| D11 | Nút lưu của editor khi nguồn là file | OK | — |
| D12 | Share và Copy | OK | — |

## D1 — Editor và các công cụ nhận ảnh server bằng cách nào
- **Chốt:** Thêm một nguồn ảnh dạng file. Phiên sửa ảnh có hai loại: từ PHAsset như hiện nay, hoặc từ file tạm đã tải về. Từ bước có file tạm trở đi, editor, render, mask và lens profile dùng chung code. Những chỗ cần PHAsset (revert, Live Photo, adjustment data, ngày chụp khi Save Copy) chuyển sang đọc EXIF của file, hoặc ẩn đi.
- **Vì sao:** Đây là quyết định kiến trúc của cả tính năng. Chọn tạm-asset thì mọi ảnh đều đi qua Photos: iCloud đồng bộ nó lên, và xoá thì hệ thống bật hộp xác nhận, ảnh còn nằm 30 ngày trong Recently Deleted. Như vậy trái đúng điều người dùng muốn là không để lại bản sao trong library.
- **Đã cân nhắc:** Tạo asset tạm trong Photos, xuất xong thì xoá — Mỗi lần xoá hệ thống hỏi xác nhận, iCloud đẩy lên rồi lại xoá; Recently Deleted giữ 30 ngày, Quyền .limited: asset mới có thể không đọc lại được; Editor dùng nguồn file, collage/video/combine dùng asset tạm — Một khái niệm hai cách làm, Vẫn dính hộp xác nhận xoá cho collage và video
- **Lịch sử:** vòng 1 — trang không lưu câu trả lời; người dùng trả lời trong chat 2026-09-30: "OK hết theo đề xuất".

## D2 — Làm trong mấy đợt
- **Chốt:** Hai đợt trong cùng intent. Đợt 1: menu, tải tạm, Edit một tấm và cả loạt, Paste Edits, Resize, Share, Copy, Export EXIF, sheet xuất. Đợt 2: Create Collage, Create Video, Combine Photos (AC-67). Trong đợt 1 ba mục này chưa có trong menu, chứ không hiện rồi mờ.
- **Vì sao:** Collage, Video Studio và Combine (focus stack, panorama) mỗi cái bám PHAsset theo một kiểu riêng. Video Studio còn khoá clip theo assetID và requestAVAsset. Làm hết một lần thì 3 tuần không có gì dùng được, và rủi ro dồn vào một commit lớn.
- **Đã cân nhắc:** Làm hết một lần — Lâu mới có gì chạy được, Sai ở D1 thì sửa 6 chỗ một lúc
- **Lịch sử:** vòng 1 — trang không lưu câu trả lời; người dùng trả lời trong chat 2026-09-30: "OK hết theo đề xuất".

## D3 — Tải về bản tạm
- **Chốt:** Tách bước tải + kiểm của một ảnh (theo khối, số byte, ImageIO mở được, SHA khi biết) thành một hàm Domain dùng chung. Import gọi nó rồi ghi Photos; bản tạm gọi nó rồi dừng. Thư mục tạm có tiền tố ShotDexServerEdit-, đăng ký vào TemporaryWorkspace để được dọn lúc khởi động. Kiểm chỗ trống dùng lại spaceShortfall (ước tính + 1 GB).
- **Vì sao:** ServerDownloadSession hiện luôn ghi vào Photos rồi xoá file (ServerDownloadSession.swift:153-200). Sửa nó thì dễ làm hỏng Import đang chạy tốt; viết lại từ đầu thì có hai cách kiểm file.
- **Lịch sử:** vòng 1 — trang không lưu câu trả lời; người dùng trả lời trong chat 2026-09-30: "OK hết theo đề xuất".

## D4 — Đích Photos Library lưu thành gì
- **Chốt:** Asset phẳng, chỉ gồm bản render JPEG/HEIC, giống kết quả Resize (createFlatAsset). Ngày chụp và vị trí lấy từ EXIF của file gốc. Spec §6 đổi 'như Save Copy' thành câu này.
- **Vì sao:** Spec đang ghi 'như Save Copy'. Nhưng Save Copy của editor đưa cả bản gốc vào làm base, kèm adjustment data (PhotoEditingService.swift:303-331). Với ảnh server, bản gốc RAW 60 MB sẽ vào library, mà điều này người dùng không muốn.
- **Đã cân nhắc:** Như Save Copy: bản gốc + render + recipe — Bản gốc (có khi là RAW) vào library, Recipe còn sống sau khi xuất, trái luật 'xoá sau khi xuất'
- **Lịch sử:** vòng 1 — trang không lưu câu trả lời; người dùng trả lời trong chat 2026-09-30: "OK hết theo đề xuất".

## D5 — Ghi lên server bằng code nào
- **Chốt:** Viết một bộ ghi nhỏ trong Domain cho file cục bộ: tạo folder thiếu, tên _edited theo ServerUploadPath.editedFilename, trùng thì nextFreeName (2), ghi .shotdex-part, đọc lại SHA, rồi move. Replace Original: xoá bản gốc rồi move, sau khi người dùng đã xác nhận. Bộ ghi dùng lại RemoteFileClient và ServerUploadPath, không đụng ServerUploadSession.
- **Vì sao:** ServerUploadSession khoá mọi item theo assetId: ServerUploadItem, AssetFileExporting và dòng lịch sử (ServerUploadSession.swift:4-14, :273-283). Bản render từ ảnh server không có assetId. Nới session đó ra thì upload FS-15, vốn đã có 40 AC, dễ bị hỏng theo.
- **Đã cân nhắc:** Nới ServerUploadSession cho item không có assetId — Đổi kiểu item và exporter, lịch sử phải nullable (cần migration), Có nguy cơ làm hỏng 40 AC FS-15
- **Lịch sử:** vòng 1 — trang không lưu câu trả lời; người dùng trả lời trong chat 2026-09-30: "OK hết theo đề xuất".

## D6 — Ghi lịch sử upload cho file xuất
- **Chốt:** Không ghi lịch sử. Bỏ câu đó khỏi spec §6. Lưới tải lại folder nên file mới vẫn hiện ra.
- **Vì sao:** Spec §6 ghi 'ghi lịch sử upload để lưới hiện dấu'. Nhưng dòng lịch sử cần assetId, và dấu In Library nghĩa là 'asset còn trong thư viện'. File xuất từ server không có asset nào.
- **Đã cân nhắc:** Cho assetId rỗng trong bảng lịch sử (migration) — Migration trên bảng đang có dữ liệu, Phải sửa mọi truy vấn In Library cho khỏi dính dòng rỗng
- **Lịch sử:** vòng 1 — trang không lưu câu trả lời; người dùng trả lời trong chat 2026-09-30: "OK hết theo đề xuất".

## D7 — Nhận biết folder 'chỉ đọc'
- **Chốt:** Không thử ghi trước. Original Folder chỉ mờ khi biết chắc: đang ở gốc SMB, hoặc folder Files không ghi được (hệ thống báo qua bookmark). Còn lại, lỗi quyền lúc ghi hiện ở đúng đích đó ('You can't write to this folder') kèm Choose Another Folder, và bản tạm vẫn được giữ. AC-65 đổi theo.
- **Vì sao:** Spec §6 và AC-65 muốn Original Folder mờ khi connection chỉ đọc. Nhưng code không có cờ chỉ đọc (ServerBrowserModel.swift:208-215): canEdit chỉ là 'không ở gốc SMB', và lỗi quyền chỉ lộ ra khi ghi thật (permissionDenied).
- **Đã cân nhắc:** Mở sheet là thử ghi rồi xoá một file .shotdex-probe — Chỉ mở sheet đã ghi lên server, Chậm thêm một vòng mạng; NAS có log ghi
- **Lịch sử:** vòng 1 — trang không lưu câu trả lời; người dùng trả lời trong chat 2026-09-30: "OK hết theo đề xuất".

## D8 — Chọn folder khác
- **Chốt:** Dùng lại màn duyệt server ở chế độ chọn folder (ServerBrowserModel mode .chooseFolder) như sheet upload, kèm danh sách connection từ FileServerCatalog.
- **Lịch sử:** vòng 1 — trang không lưu câu trả lời; người dùng trả lời trong chat 2026-09-30: "OK hết theo đề xuất".

## D9 — Một nguồn cho tên và glyph của lệnh
- **Chốt:** Tách định nghĩa lệnh (tên, glyph, thứ tự) ra một chỗ chung. SelectionBarViews của album và menu server cùng đọc từ đó, và test so hai danh sách bằng cách duyệt qua chúng.
- **Vì sao:** AC-53 đòi menu server trùng menu album. Nếu chép chữ sang ServerBrowserScreen thì lần sau đổi tên ở album, bên server sẽ lệch mà không ai biết (component-consistency).
- **Đã cân nhắc:** Chép tên sang menu server — Hai bản chữ, sẽ lệch dần
- **Lịch sử:** vòng 1 — trang không lưu câu trả lời; người dùng trả lời trong chat 2026-09-30: "OK hết theo đề xuất".

## D10 — Tiến độ tải hiện ở đâu
- **Chốt:** Một sheet nhỏ (tier A) cùng khuôn với tiến độ Import: 'Downloading 3 of 12', byte, Cancel có hỏi, giữ màn hình sáng. Tải xong thì sheet đóng và editor mở.
- **Vì sao:** Tải loạt 12 RAW trên SMB mất vài phút. Nếu tiến độ chỉ là một vòng xoay trên lưới thì người dùng tưởng app treo; còn một sheet thì che lưới trong lúc chờ.
- **Đã cân nhắc:** Thanh tiến độ trên lưới — Thêm một kiểu tiến độ thứ hai, Chạm vào lưới lúc đang tải thì sao: phải thêm luật
- **Lịch sử:** vòng 1 — trang không lưu câu trả lời; người dùng trả lời trong chat 2026-09-30: "OK hết theo đề xuất".

## D11 — Nút lưu của editor khi nguồn là file
- **Chốt:** Save Copy / Save Changes thay bằng Export…. Loạt nhiều ảnh: Export… xuất mọi ảnh đã sửa. Cancel khi có sửa thì hỏi Discard edits?. Menu ⋯ của editor ẩn Revert và Live Photo.
- **Lịch sử:** vòng 1 — trang không lưu câu trả lời; người dùng trả lời trong chat 2026-09-30: "OK hết theo đề xuất".

## D12 — Share và Copy
- **Chốt:** Share đưa file tạm (URL) vào PhotoShareSheet.present(items:), vốn đã nhận URL, và dùng lại luật bỏ GPS. Copy đặt ảnh giải mã (tối đa 4096 px) lên pasteboard. Xong thì xoá bản tạm.
- **Lịch sử:** vòng 1 — trang không lưu câu trả lời; người dùng trả lời trong chat 2026-09-30: "OK hết theo đề xuất".
