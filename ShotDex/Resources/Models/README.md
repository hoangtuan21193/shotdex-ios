# Core ML models

The `.mlpackage` in this folder is not in git. It is 41 MB of weights that git
would carry in its history forever, and it can be re-downloaded, so `.gitignore`
keeps it out. A fresh clone therefore builds and runs — the feature that needs it
degrades instead of breaking:

| Missing model | What happens |
| --- | --- |
| `DETRResnet50SemanticSegmentationF16P8.mlpackage` | The **Sky** mask finds nothing. Every other mask kind is unaffected. |

## Putting it back

**`DETRResnet50SemanticSegmentationF16P8.mlpackage`** (41 MB) — Apple publishes it
on the [Core ML Models gallery](https://developer.apple.com/machine-learning/models/)
as *DETR Resnet50 Semantic Segmentation F16P8*. Download and drop it in this
folder; the target picks it up with no project edit
(`PBXFileSystemSynchronizedRootGroup`).

The licence is alongside this file, and credited in `THIRD_PARTY_NOTICES.md`.
