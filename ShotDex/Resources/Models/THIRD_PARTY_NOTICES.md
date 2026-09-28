# Third-party model notices

## DETRResnet50SemanticSegmentationF16P8

ShotDex bundles Apple's Core ML conversion of DETR ResNet-50 semantic
segmentation for its on-device Sky mask.

- Source package: Apple Machine Learning model assets
- Upstream architecture/model: `facebookresearch/detr`
- License: Apache License 2.0
- Copyright: Facebook, Inc. and its affiliates

The complete Apache License 2.0 text is included in
`LICENSE-DETR-APACHE-2.0.txt`. Inference is on-device. ShotDex does not send
input images or model outputs off the device.

## DepthAnythingV2SmallF16

ShotDex bundles Apple's Core ML conversion of Depth Anything V2 Small to
estimate depth for Lens Blur on photos that were captured without a depth map.

- Source package: `apple/coreml-depth-anything-v2-small` (Hugging Face)
- Upstream model: Depth Anything V2 Small (`DepthAnything/Depth-Anything-V2`)
- License: Apache License 2.0 (the Small model only)
- Copyright: the Depth Anything V2 authors

The complete Apache License 2.0 text is included in
`LICENSE-DEPTH-ANYTHING-APACHE-2.0.txt`. Inference is on-device. ShotDex does
not send input images or model outputs off the device.
