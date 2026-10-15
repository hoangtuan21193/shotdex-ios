# FS-24.11 — Settings › Sources & Backup

`FS-24.11` · tier A · mã hiện có: `Features/Settings/`, `Features/Sources/`, `Features/Backup/` · board iPhone `PH_HubSources` · iPad
`IP_Settings` · Duo `DI_SourcesBackup` / `DC_SourcesBackup` · Mac `MAC_SettingsSources`, `MAC_SettingsSourcesBackup`; Settings › Playback iPhone `PH_SettingsPlayback` · iPad `IP_SettingsPlayback` · Duo `DI_SettingsPlayback` / `DC_SettingsPlayback` · Mac `MAC_SettingsGeneral` (Clear Listening History) · cập nhật 2026-10-16

**Một câu:** một trang nói mọi file của người dùng nằm ở đâu — thư viện Photos, thư mục, ổ, NAS, Plex, file đã chép —
và chứa ba việc quanh đó: duyệt mạng, sao lưu, và những gì đang giữ trên máy.

## 1. Lối vào và tên

- Hàng **Sources** của Settings (FS-08.01b) đổi tên **Sources & Backup** trên mọi thiết bị (người dùng 15/10); dòng giá trị
  `5 sources · backed up today`.
- Vào từ: ⚙ của mọi tab › Sources & Backup; chân nhóm Sources của Photos; nút **Add Source…** của mọi tab mở thẳng sheet
  Add a Source (không qua trang này).

## 2. Trang (thứ tự board `PH_HubSources`)

| Nhóm | Hàng |
|---|---|
| **Sources — where your files live** | một hàng mỗi nguồn: icon · tên · `loại · media nó cấp` (`SMB · photos, movies, music`, `movies, music` cho Plex, `imported on this iPhone` cho Files) · trạng thái; cuối nhóm **Add Source…** |
| **Browse** | Local Network · Cloud (cùng màn FS-15/FS-17 mở từ Photos › Utilities) |
| **Backup** | Back Up to NAS Home · `last run today 02:14` (FS-22); chưa có lịch: **Set Up Backup…** |
| **On this iPhone** | Kept on iPhone · `41.2 GB · 3 albums, 6 movies, 1 playlist` ([09 §5](09-keep-on-device.md)) |

- iPad/Mac (board `IP_Settings`, `MAC_SettingsSources`) thêm các nhóm hiện có của Settings › Sources: Metadata (.xmp
  sidecars), Drives and Indexing, Cache Size Limit — không đổi gì, chỉ cùng trang. Điện thoại cũng có đủ (NF-05 §1.1): các
  nhóm này nằm dưới On this iPhone. **Chốt 2026-10-16 (A14):** board iPhone `PH_HubSources` và Duo `DI_/DC_SourcesBackup` vẽ
  thêm ba nhóm đó (đã vẽ); không dời chúng vào trang chi tiết từng nguồn.
- iPhone Photos: `Photos · your videos` + quyền (`Full Access`, `Limited — 120 photos`, Manage Access…).

## 3. Một nguồn, nhiều loại media

- Một connection FS-15 hay một máy chủ Plex là **một hàng**; trang chi tiết nguồn liệt kê thư mục theo loại:
  `Photos — /Photos` · `Movies — /Video/Movies` · `Music — /Music`, mỗi loại **Add Folder…**/Remove; Plex: thư viện Movies,
  TV Shows, Music bật/tắt riêng.
- Trạng thái mỗi nguồn (FS-19.01b §1 cho cả ba loại): Connected · Reading `1,240 of 3,812` · Offline `Not connected · 214 songs kept`
  · Needs access (**Grant Access…**) · Plex token hết hạn: `Sign in to Plex again` + **Sign In** (FS-23.07 §5).
- **Remove…** nguồn: alert nói đủ cả ba loại: "Remove “NAS Home”? Its 1,102 photos, 128 movies and 2,410 songs leave ShotDex.
  Kept items stay on this iPhone. Nothing on NAS Home is deleted." Kept items ở lại, có nhãn nguồn đã gỡ (như FS-23.05 §1).
- Hàng thẻ nhớ đang cắm (FS-20): hiện ở nhóm Sources với `214 new photos` + **Import…**.

## 4. Lỗi

| Lỗi | Trên hàng nguồn |
|---|---|
| NAS không tới được | `Offline · last seen 2 h ago`; kept vẫn dùng được |
| mật khẩu SMB đổi | `Can't sign in` + **Update Password…** (FS-15) |
| Plex token thu hồi (401) | `Sign in to Plex again` + **Sign In**; phim, bài đã Keep vẫn phát |
| thư mục Files mất quyền | Needs access + **Grant Access…** (FS-19.01b §3) |
