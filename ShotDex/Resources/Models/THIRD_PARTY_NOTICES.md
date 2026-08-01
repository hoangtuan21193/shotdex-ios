# Third-party model notices

## DETRResnet50SemanticSegmentationF16P8

ShotDex bundles Apple's Core ML conversion of DETR ResNet-50 semantic
segmentation for its on-device Sky mask.

- Source package: Apple Machine Learning model assets
- Upstream architecture/model: `facebookresearch/detr`
- License: Apache License 2.0
- Copyright: Facebook, Inc. and its affiliates

The complete Apache License 2.0 text is included in
`LICENSE-DETR-APACHE-2.0.txt`. ShotDex does not send input images or model
outputs off the device.

## LaMaInpainting

ShotDex bundles a Core ML conversion of big-lama for the Clean Up tool's AI Fill.
Conversion script: `Scripts/convert_lama_coreml.py`.

- Upstream: `advimman/lama` — "Resolution-robust Large Mask Inpainting with
  Fourier Convolutions", WACV 2022
- License: Apache License 2.0, text in `LICENSE-LAMA-APACHE-2.0.txt`
- Copyright: Samsung Research and the LaMa authors
- Training data: Places365-Challenge, whose own terms describe non-commercial
  research use. The Apache-2.0 grant covers the code and the published weights;
  whether the dataset's terms reach the trained weights is unsettled and worth
  legal review before commercial release. Clean Up's Remove works without this
  model — it falls back to `PatchMatchInpainter`.

Inference is on-device. ShotDex does not send input images or model outputs off
the device.
