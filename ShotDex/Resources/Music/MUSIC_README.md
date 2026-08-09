# Bundled Music

Soundtrack beds for the Video Studio (see spec §7.9). Five moods, AAC `.m4a`
44.1 kHz stereo. The catalog is hardcoded in
`ShotDex/Data/Sources/MusicTrackCatalog.swift`; a track whose file is missing
simply doesn't show its chip, so tracks can be swapped by replacing files with
the same names:

- `Upbeat.m4a`
- `Chill.m4a`
- `Cinematic.m4a`
- `Acoustic.m4a`
- `Electronic.m4a`

## ⚠️ Placeholders

The current files are **synthesized placeholder loops** generated in-repo
(simple sine-layer chord/arpeggio synthesis — no third-party material, no
license constraints). They exist so the feature works end to end.

**Replace them with licensed production music before shipping**, and record
each track's real license in `MUSIC_THIRD_PARTY_NOTICES.md` (the
`Resources/Models/` folder shows the pattern used for the DETR model).
