#!/usr/bin/env python3
"""Convert big-lama to a Core ML package ShotDex can load.

Two things make this more than a one-line `ct.convert`:

1. LaMa's fast Fourier convolutions call `torch.fft.rfftn` / `irfftn`, and
   coremltools has no FFT operation. At a fixed input size the transform is a
   pair of matrix multiplications with precomputed DFT bases, which converts
   cleanly, so `patch_fourier_units` swaps them in.
2. The app wants one call that takes an image plus a mask and returns finished
   pixels, so the traced wrapper does the masking and the final composite.

The contract with `PhotoRenderService.inpaintedPatch` is the input names
`image` and `mask`, the output name `output`, and the fixed edge below. Change
one and you change the other.

Only the generator is loaded — `make_generator` plus the checkpoint's state dict,
not `load_checkpoint` and the training module around it. That keeps the
dependencies down to torch, kornia, omegaconf and coremltools: no
pytorch_lightning, no albumentations, and above all no `requirements.txt`, whose
2020-era numpy pin has no arm64 wheel and fails to compile.

Usage:
    zsh Scripts/setup_lama_env.sh          # once
    python3 Scripts/convert_lama_coreml.py \
        --lama-repo ~/src/lama \
        --checkpoint ~/models/big-lama \
        --edge 800

See Scripts/README-lama.md.
"""

from __future__ import annotations

import argparse
import math
import os
import sys
from pathlib import Path

EDGE_DEFAULT = 800
OUTPUT_NAME = "LaMaInpainting.mlpackage"


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--lama-repo",
        required=True,
        type=Path,
        help="Clone of github.com/advimman/lama (needs its saicinpainting package).",
    )
    parser.add_argument(
        "--checkpoint",
        required=True,
        type=Path,
        help="Unpacked big-lama directory containing config.yaml and models/best.ckpt.",
    )
    parser.add_argument("--edge", type=int, default=EDGE_DEFAULT)
    parser.add_argument(
        "--out",
        type=Path,
        default=Path(__file__).resolve().parent.parent
        / "ShotDex"
        / "Resources"
        / "Models"
        / OUTPUT_NAME,
    )
    parser.add_argument(
        "--precision",
        choices=("fp16-safe-matmul", "fp16", "fp32"),
        default="fp16-safe-matmul",
        help=(
            "fp16-safe-matmul is what ShotDex ships: fp16 everywhere except the "
            "DFT matmuls, which overflow in half precision and come back as black "
            "pixels. Plain fp16 is ~103 MB and visibly corrupt on the GPU and the "
            "Neural Engine; fp32 is exact but ~206 MB."
        ),
    )
    return parser.parse_args()


# ---------------------------------------------------------------------------
# The FFT replacement
# ---------------------------------------------------------------------------


def dft_matrices(length: int, torch):
    """Forward real DFT bases for one axis, `norm='ortho'`.

    Returns cosine and negative-sine matrices of shape (length, length // 2 + 1)
    for the half-spectrum axis, and (length, length) for the full one.
    """
    half = length // 2 + 1
    scale = 1.0 / math.sqrt(length)
    n = torch.arange(length, dtype=torch.float64).unsqueeze(1)
    k_half = torch.arange(half, dtype=torch.float64).unsqueeze(0)
    k_full = torch.arange(length, dtype=torch.float64).unsqueeze(0)
    angle_half = 2.0 * math.pi * n * k_half / length
    angle_full = 2.0 * math.pi * n * k_full / length
    return {
        "half_cos": (torch.cos(angle_half) * scale).float(),
        "half_sin": (-torch.sin(angle_half) * scale).float(),
        "full_cos": (torch.cos(angle_full) * scale).float(),
        "full_sin": (-torch.sin(angle_full) * scale).float(),
    }


def inverse_dft_matrices(length: int, torch):
    """Inverse bases: full complex along one axis, half-to-real along the other."""
    half = length // 2 + 1
    scale = 1.0 / math.sqrt(length)
    k_full = torch.arange(length, dtype=torch.float64).unsqueeze(1)
    n_full = torch.arange(length, dtype=torch.float64).unsqueeze(0)
    angle_full = 2.0 * math.pi * k_full * n_full / length

    k_half = torch.arange(half, dtype=torch.float64).unsqueeze(1)
    angle_half = 2.0 * math.pi * k_half * n_full / length
    # Every bin except DC (and Nyquist when the length is even) stands for a
    # conjugate pair, so it counts twice on the way back.
    weight = torch.full((half, 1), 2.0, dtype=torch.float64)
    weight[0, 0] = 1.0
    if length % 2 == 0:
        weight[half - 1, 0] = 1.0
    return {
        "full_cos": (torch.cos(angle_full) * scale).float(),
        "full_sin": (torch.sin(angle_full) * scale).float(),
        "half_cos": (torch.cos(angle_half) * weight * scale).float(),
        "half_sin": (-torch.sin(angle_half) * weight * scale).float(),
    }


def patch_fourier_units(model, edge: int, torch) -> int:
    """Replaces every FourierUnit.forward with matmul DFTs. Returns the count."""
    from saicinpainting.training.modules.ffc import FourierUnit

    def forward(self, x):
        batch = x.shape[0]
        height, width = x.shape[-2], x.shape[-1]
        key = f"_dft_{height}x{width}"
        if not hasattr(self, key):
            setattr(self, key, (
                dft_matrices(width, torch),
                dft_matrices(height, torch),
                inverse_dft_matrices(height, torch),
                inverse_dft_matrices(width, torch),
            ))
        forward_w, forward_h, inverse_h, inverse_w = getattr(self, key)
        device, dtype = x.device, x.dtype

        def cast(matrix):
            return matrix.to(device=device, dtype=dtype)

        # Real DFT along W: (N, C, H, W) @ (W, W//2+1)
        real = x @ cast(forward_w["half_cos"])
        imag = x @ cast(forward_w["half_sin"])
        # Complex DFT along H, contracting the H axis.
        real_t = real.transpose(-2, -1)
        imag_t = imag.transpose(-2, -1)
        cos_h = cast(forward_h["full_cos"])
        sin_h = cast(forward_h["full_sin"])
        # (a + bi)(cos + i·(−sin)) with sin already negated in the basis.
        spectrum_real = (real_t @ cos_h + imag_t @ (-sin_h)).transpose(-2, -1)
        spectrum_imag = (imag_t @ cos_h + real_t @ sin_h).transpose(-2, -1)

        ffted = torch.stack((spectrum_real, spectrum_imag), dim=-1)
        ffted = ffted.permute(0, 1, 4, 2, 3).contiguous()
        ffted = ffted.view((batch, -1) + ffted.size()[3:])

        if getattr(self, "spectral_pos_encoding", False):
            height_f, width_f = ffted.shape[-2:]
            coords_vert = (
                torch.linspace(0, 1, height_f, device=device, dtype=dtype)[None, None, :, None]
                .expand(batch, 1, height_f, width_f)
            )
            coords_horiz = (
                torch.linspace(0, 1, width_f, device=device, dtype=dtype)[None, None, None, :]
                .expand(batch, 1, height_f, width_f)
            )
            ffted = torch.cat((coords_vert, coords_horiz, ffted), dim=1)

        if getattr(self, "use_se", False):
            ffted = self.se(ffted)

        ffted = self.conv_layer(ffted)
        ffted = self.relu(self.bn(ffted))

        ffted = ffted.view((batch, -1, 2) + ffted.size()[2:]).permute(0, 1, 3, 4, 2).contiguous()
        out_real = ffted[..., 0]
        out_imag = ffted[..., 1]

        # Inverse along H first (the forward pass did W then H), then the
        # half-spectrum inverse along W, which lands back on real pixels.
        real_t = out_real.transpose(-2, -1)
        imag_t = out_imag.transpose(-2, -1)
        icos_h = cast(inverse_h["full_cos"])
        isin_h = cast(inverse_h["full_sin"])
        mid_real = (real_t @ icos_h - imag_t @ isin_h).transpose(-2, -1)
        mid_imag = (real_t @ isin_h + imag_t @ icos_h).transpose(-2, -1)
        output = mid_real @ cast(inverse_w["half_cos"]) + mid_imag @ cast(inverse_w["half_sin"])
        return output

    patched = 0
    for module in model.modules():
        if isinstance(module, FourierUnit):
            module.forward = forward.__get__(module, FourierUnit)
            patched += 1
    return patched


# ---------------------------------------------------------------------------
# Tracing wrapper
# ---------------------------------------------------------------------------


class _StubPlaceholder:
    """Whatever the checkpoint pickled, reduced to an object that unpickles."""

    def __init__(self, *args, **kwargs):
        pass

    def __setstate__(self, state):
        pass


class _StubModule:
    """Module whose every attribute is a freshly minted placeholder class."""

    def __init__(self, name: str):
        self.__name__ = name
        self.__path__: list[str] = []
        self.__spec__ = None
        self.seed_everything = lambda *args, **kwargs: None

    def __getattr__(self, name: str):
        if name.startswith("__"):
            raise AttributeError(name)
        placeholder = type(name, (_StubPlaceholder,), {"__module__": self.__name__})
        setattr(self, name, placeholder)
        return placeholder


class _StubFinder:
    """Fabricates every `pytorch_lightning.*` module on demand.

    Two separate needs, one mechanism. `saicinpainting/utils.py` does
    `from pytorch_lightning import seed_everything` at module scope and `ffc.py`
    imports `get_shape` from that file, so loading the generator would otherwise
    drag in the whole training framework for a function only training calls. And
    the checkpoint itself pickles trainer state — `pytorch_lightning.callbacks.*`
    among it — which unpickling has to resolve to *something* even though the
    weights are the only part anybody reads.
    """

    PREFIX = "pytorch_lightning"

    def find_spec(self, fullname, path=None, target=None):
        if fullname != self.PREFIX and not fullname.startswith(self.PREFIX + "."):
            return None
        import importlib.util

        return importlib.util.spec_from_loader(fullname, self, is_package=True)

    def create_module(self, spec):
        return _StubModule(spec.name)

    def exec_module(self, module) -> None:
        pass


def stub_pytorch_lightning() -> None:
    if any(isinstance(finder, _StubFinder) for finder in sys.meta_path):
        return
    sys.meta_path.insert(0, _StubFinder())




def build_wrapper(generator, torch):
    class InpaintWrapper(torch.nn.Module):
        """image and mask in 0…1, finished pixels out in 0…255.

        The composite happens here so the returned patch matches the untouched
        surroundings exactly; ShotDex then blends it through its own feathered
        matte.
        """

        def __init__(self, generator):
            super().__init__()
            self.generator = generator

        def forward(self, image, mask):
            binary = (mask > 0.5).to(image.dtype)
            masked = image * (1 - binary)
            predicted = self.generator(torch.cat([masked, binary], dim=1))
            composited = binary * predicted + (1 - binary) * image
            return torch.clamp(composited, 0.0, 1.0) * 255.0

    return InpaintWrapper(generator).eval()


def main() -> int:
    arguments = parse_arguments()
    sys.path.insert(0, str(arguments.lama_repo.expanduser().resolve()))
    os.environ.setdefault("OMP_NUM_THREADS", "1")

    if sys.version_info < (3, 10):
        print(
            f"Python {sys.version_info.major}.{sys.version_info.minor} is too old for "
            "these wheels — run Scripts/setup_lama_env.sh first.",
            file=sys.stderr,
        )
        return 1

    try:
        import torch
        import coremltools as ct
        from omegaconf import OmegaConf

        stub_pytorch_lightning()
        from saicinpainting.training.modules import make_generator
    except ImportError as error:
        print(f"Missing dependency: {error}", file=sys.stderr)
        print("Run: zsh Scripts/setup_lama_env.sh", file=sys.stderr)
        return 1

    checkpoint = arguments.checkpoint.expanduser().resolve()
    config_path = checkpoint / "config.yaml"
    weights_path = checkpoint / "models" / "best.ckpt"
    for path in (config_path, weights_path):
        if not path.exists():
            print(f"Not found: {path}", file=sys.stderr)
            return 1

    config = OmegaConf.load(config_path)
    generator_config = OmegaConf.to_container(config.generator, resolve=True)
    generator = make_generator(config, **generator_config)

    # `load_checkpoint` would drag in the whole training module; the generator's
    # own weights are a flat prefix of the state dict.
    state = torch.load(str(weights_path), map_location="cpu", weights_only=False)
    state_dict = state.get("state_dict", state)
    generator_state = {
        key[len("generator.") :]: value
        for key, value in state_dict.items()
        if key.startswith("generator.")
    }
    if not generator_state:
        print("No 'generator.' weights in the checkpoint.", file=sys.stderr)
        return 1
    missing, unexpected = generator.load_state_dict(generator_state, strict=False)
    if missing:
        print(f"Missing {len(missing)} weights, first: {missing[:3]}", file=sys.stderr)
        return 1
    if unexpected:
        print(f"Ignoring {len(unexpected)} unexpected weights, first: {unexpected[:3]}")
    generator.eval()
    for parameter in generator.parameters():
        parameter.requires_grad_(False)

    patched = patch_fourier_units(generator, arguments.edge, torch)
    print(f"Patched {patched} FourierUnit modules to matmul DFTs.")
    if patched == 0:
        print(
            "No FourierUnit found — the checkpoint is not an FFC LaMa, "
            "or the repo layout changed.",
            file=sys.stderr,
        )
        return 1

    wrapper = build_wrapper(generator, torch)
    edge = arguments.edge
    example_image = torch.rand(1, 3, edge, edge)
    example_mask = torch.zeros(1, 1, edge, edge)
    example_mask[:, :, edge // 3 : edge // 2, edge // 3 : edge // 2] = 1.0

    with torch.no_grad():
        reference = wrapper(example_image, example_mask)
        traced = torch.jit.trace(wrapper, (example_image, example_mask))
        traced_output = traced(example_image, example_mask)
    drift = (reference - traced_output).abs().max().item()
    print(f"Trace matches eager to {drift:.4f} / 255.")

    if arguments.precision == "fp32":
        precision = ct.precision.FLOAT32
    elif arguments.precision == "fp16":
        precision = ct.precision.FLOAT16
    else:
        # The DFT bases replaced the FFTs with sums over 800 terms, and in half
        # precision those overflow to inf, come out of the graph as NaN, and land
        # in the output image as black pixels — on the Neural Engine a whole
        # corner of the frame, on the GPU a scattering of them. Keeping just the
        # matmuls in fp32 costs a couple of megabytes and fixes it.
        precision = ct.transform.FP16ComputePrecision(
            op_selector=lambda op: op.op_type not in ("matmul", "reduce_sum")
        )
    package = ct.convert(
        traced,
        inputs=[
            ct.ImageType(
                name="image",
                shape=(1, 3, edge, edge),
                scale=1 / 255.0,
                color_layout=ct.colorlayout.RGB,
            ),
            ct.ImageType(
                name="mask",
                shape=(1, 1, edge, edge),
                scale=1 / 255.0,
                color_layout=ct.colorlayout.GRAYSCALE,
            ),
        ],
        outputs=[ct.ImageType(name="output", color_layout=ct.colorlayout.RGB)],
        compute_precision=precision,
        minimum_deployment_target=ct.target.iOS17,
        convert_to="mlprogram",
    )
    package.short_description = (
        "LaMa (big-lama) inpainting, fixed "
        f"{edge}x{edge} input. Apache-2.0, github.com/advimman/lama"
    )

    destination = arguments.out.expanduser().resolve()
    destination.parent.mkdir(parents=True, exist_ok=True)
    package.save(str(destination))

    total = sum(
        path.stat().st_size for path in destination.rglob("*") if path.is_file()
    )
    print(f"Wrote {destination} ({total / 1_000_000:.1f} MB)")
    print(
        "Xcode compiles the .mlpackage to LaMaInpainting.mlmodelc automatically; "
        "the target picks it up with no project edit because ShotDex/ is a "
        "file-system-synchronized group."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
