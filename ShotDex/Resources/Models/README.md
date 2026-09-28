# Core ML models

The `.mlpackage`s in this folder are not in git. They are 41–48 MB of weights that git
would carry in its history forever, and it can be re-downloaded, so `.gitignore`
keeps it out. A fresh clone therefore builds and runs — the feature that needs it
degrades instead of breaking:

| Missing model | What happens |
| --- | --- |
| `DETRResnet50SemanticSegmentationF16P8.mlpackage` | The **Sky** mask finds nothing. Every other mask kind is unaffected. |
| `DepthAnythingV2SmallF16.mlpackage` | **Lens Blur** leaves photos without a captured depth map as shot. Portrait photos still blur by their own map. |

## Putting it back

**`DETRResnet50SemanticSegmentationF16P8.mlpackage`** (41 MB) — Apple publishes it
on the [Core ML Models gallery](https://developer.apple.com/machine-learning/models/)
as *DETR Resnet50 Semantic Segmentation F16P8*. Download and drop it in this
folder; the target picks it up with no project edit
(`PBXFileSystemSynchronizedRootGroup`).

**`DepthAnythingV2SmallF16.mlpackage`** (48 MB) — Apple's Core ML conversion on
Hugging Face, [`apple/coreml-depth-anything-v2-small`](https://huggingface.co/apple/coreml-depth-anything-v2-small),
folder `DepthAnythingV2SmallF16.mlpackage` (three files: `Manifest.json`,
`Data/com.apple.CoreML/model.mlmodel`, `Data/com.apple.CoreML/weights/weight.bin`,
SHA-256 of the weights `fa60d9b6…a0fed`). Only the **Small** variant is Apache-2.0;
Base and Large are not, and must not be bundled.

The licences are alongside this file, and credited in `THIRD_PARTY_NOTICES.md`.
