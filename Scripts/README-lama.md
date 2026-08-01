# AI Fill: converting big-lama to Core ML

ShotDex's Clean Up tool works without this. Remove falls back to PatchMatch
(`PatchMatchInpainter`) whenever `LaMaInpainting.mlmodelc` is missing from the
bundle, and the AI Fill switch stays hidden. Everything below is only needed to
turn that switch on.

## What you end up with

`ShotDex/Resources/Models/LaMaInpainting.mlpackage`, **103 MB** (98 MiB on disk)
— big-lama's generator is 51.0M parameters, stored fp16 except the DFT matmuls.
That is the whole increase in app size; Core ML weights barely compress, so the
App Store download grows by about the same. For comparison the sky-segmentation
model already in the bundle is 41 MB.

Measured after conversion, comparing Core ML against PyTorch fp32 on an 800×800
frame with a 200×100 hole:

| Compute units | Warm inference | Difference outside the hole |
|---|---|---|
| `.all` | 1.1 s | **0.0** — exact |
| `.cpuAndGPU` | 0.33 s | 69 px in a 12×6 block at the top-left corner |
| `.cpuOnly` | 1.8 s | 0.0 — exact |

`PhotoRenderService.loadInpaintingModel()` asks for `.all`, which is the exact
column. The corner block the GPU path produces is a Metal edge artifact — nothing
inside the hole, and the app crops the tile out of the middle of the square and
blends it through a feathered matte, so the frame border is never sampled.

## Why fp16 alone is not enough

The DFT bases replaced each FFT with a sum over 800 terms. In half precision
those overflow to infinity, leave the graph as NaN, and land in the output image
as **black pixels** — a whole corner of the frame on the Neural Engine (25 074
pixels, and a `MILCompilerForANE ... ANECCompile() FAILED` on load), scattered
ones on the GPU. `--precision fp16-safe-matmul`, the default, keeps `matmul` and
`reduce_sum` in fp32 and the rest in fp16: same 103 MB, and exact output. Plain
`--precision fp16` reproduces the corruption; `--precision fp32` is exact at
206 MB.

## Steps

One-off setup — clones the repo, downloads the checkpoint, builds a venv:

```bash
zsh Scripts/setup_lama_env.sh
```

Then convert:

```bash
source ~/.venvs/lama/bin/activate
python3 Scripts/convert_lama_coreml.py --lama-repo ~/src/lama --checkpoint ~/models/big-lama
```

`brew install python@3.12` first if the setup script says it cannot find a Python
— Xcode's bundled 3.9 has no wheels for these packages.

### Do not install lama's requirements.txt

Those pins are from 2020 and include a numpy with no arm64 wheel, so pip compiles
it from source and the old numpy build system passes `-faltivec`, a PowerPC flag
clang rejects:

```
clang: error: the clang compiler does not support 'faltivec'
```

None of that file is needed. The conversion loads the generator only — via
`make_generator` plus the checkpoint's `generator.*` weights, not
`load_checkpoint` and the training module around it — so the dependency list is
torch, kornia (imported by the FFC package), omegaconf and coremltools. No
pytorch_lightning, no albumentations, no scikit-anything.

Then build. `ShotDex/` is a `PBXFileSystemSynchronizedRootGroup`, so the new
`.mlpackage` joins the target with no project file edit, and Xcode compiles it to
`LaMaInpainting.mlmodelc` at the bundle root — which is the name
`PhotoRenderService.loadInpaintingModel()` looks for.

## The contract with the app

`PhotoRenderService.inpaintedPatch` hard-codes four things. Change any of them in
the script and you have to change them there too:

| Thing | Value |
|---|---|
| Resource name | `LaMaInpainting` |
| Input image | `image`, RGB, 800×800 |
| Input mask | `mask`, grayscale, 800×800, white = fill this |
| Output | `output`, RGB, 800×800 |

The app aspect-fits one stroke's tile into the square on a black field and crops
the result back out, so the fixed size costs nothing in flexibility. It does cap
detail: a removal far larger than the tile comes back softer.

## Why the script is not a one-liner

LaMa's fast Fourier convolutions call `torch.fft.rfftn` / `irfftn`, and
coremltools has no FFT operation. At a fixed input size a DFT is just a
multiplication by a constant matrix, so `patch_fourier_units` replaces both
transforms with separable matmuls (real DFT along width, complex along height,
and the mirror image on the way back) and prints how closely the traced graph
still matches eager PyTorch.

That patch is the fragile part, and it has not been run here — it was written
against the module layout of `saicinpainting.training.modules.ffc.FourierUnit`.
If the conversion fails, that is the first place to look.

## Licensing

The [LaMa repository](https://github.com/advimman/lama) is Apache-2.0, with no
non-commercial clause, and the widely used ONNX export
([Carve/LaMa-ONNX](https://huggingface.co/Carve/LaMa-ONNX)) is published under
the same licence. Drop `LICENSE-LAMA-APACHE-2.0.txt` next to the model and add a
line to `THIRD_PARTY_NOTICES.md`, the way the bundled DETR model does.

One caveat worth knowing before shipping commercially: big-lama is trained on
Places365-Challenge, whose own terms describe non-commercial research use.
Whether that reaches the trained weights is a legal question rather than a
technical one, and LaMa says nothing about it either way. The PatchMatch path has
no such question hanging over it.
