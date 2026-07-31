# Core ML models

Neither `.mlpackage` in this folder is in git. Together they are 139 MB of
weights that git would carry in its history forever, and both can be rebuilt or
re-downloaded, so `.gitignore` keeps them out. A fresh clone therefore builds and
runs — the two features that need them degrade instead of breaking:

| Missing model | What happens |
| --- | --- |
| `LaMaInpainting.mlpackage` | Clean Up's **AI Fill** switch stays hidden and Remove falls back to `PatchMatchInpainter`. A recipe saved with `usesModel: true` still renders, through the fallback. |
| `DETRResnet50SemanticSegmentationF16P8.mlpackage` | The **Sky** mask finds nothing. Every other mask kind is unaffected. |

## Putting them back

**`LaMaInpainting.mlpackage`** (98 MiB, 800×800, fp16 except the DFT matmuls) —
follow [`Scripts/README-lama.md`](../../../Scripts/README-lama.md):

```bash
zsh Scripts/setup_lama_env.sh
~/.venvs/lama/bin/python Scripts/convert_lama_coreml.py
```

**`DETRResnet50SemanticSegmentationF16P8.mlpackage`** (41 MB) — Apple publishes it
on the [Core ML Models gallery](https://developer.apple.com/machine-learning/models/)
as *DETR Resnet50 Semantic Segmentation F16P8*. Download and drop it in this
folder; the target picks it up with no project edit
(`PBXFileSystemSynchronizedRootGroup`).

Licences for both are alongside this file, and credited in
`THIRD_PARTY_NOTICES.md`.
