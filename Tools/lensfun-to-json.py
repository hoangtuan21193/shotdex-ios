#!/usr/bin/env python3
"""Convert the Lensfun database (data/db/*.xml) to the distortion table ShotDex embeds.

Usage: Tools/lensfun-to-json.py <lensfun data/db dir> <output json>

Only what the JPEG lens-profile pass reads is kept: maker, model strings (every
language variant), mounts, calibration crop factor, aspect ratio and the
per-focal distortion terms (poly3 / poly5 / ptlens), plus each camera's mount
and crop factor so a lens can be matched to the body it was used on. The strings and numbers are
copied as they are — Lensfun is CC-BY-SA 3.0, and ShotDex keeps every change of
its own (name matching) outside the data so the table stays a verbatim subset.
"""
import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


def lens_entries(path):
    root = ET.parse(path).getroot()
    for lens in root.iter("lens"):
        distortion = []
        for cal in lens.iter("calibration"):
            for d in cal.iter("distortion"):
                model = d.get("model")
                if model not in ("poly3", "poly5", "ptlens"):
                    continue
                entry = {"model": model, "focal": float(d.get("focal", "0"))}
                for key in ("k1", "k2", "a", "b", "c"):
                    if d.get(key) is not None:
                        entry[key] = float(d.get(key))
                if d.get("real-focal") is not None:
                    entry["realFocal"] = float(d.get("real-focal"))
                distortion.append(entry)
        if not distortion:
            continue
        models = [m.text.strip() for m in lens.findall("model") if m.text]
        makers = [m.text.strip() for m in lens.findall("maker") if m.text and m.get("lang") is None]
        if not models or not makers:
            continue
        crop = lens.findtext("cropfactor")
        aspect = lens.findtext("aspect-ratio")
        yield {
            "maker": makers[0],
            "model": [m.text.strip() for m in lens.findall("model") if m.text and m.get("lang") is None][0],
            "aliases": sorted(set(models)),
            "mounts": [m.text.strip() for m in lens.findall("mount") if m.text],
            "cropFactor": float(crop) if crop else 1.0,
            "aspectRatio": aspect.strip() if aspect else None,
            "distortion": sorted(distortion, key=lambda e: e["focal"]),
        }


def camera_entries(path):
    root = ET.parse(path).getroot()
    for camera in root.iter("camera"):
        makers = [m.text.strip() for m in camera.findall("maker") if m.text and m.get("lang") is None]
        models = [m.text.strip() for m in camera.findall("model") if m.text]
        mount = camera.findtext("mount")
        crop = camera.findtext("cropfactor")
        if not makers or not models or not mount:
            continue
        yield {
            "maker": makers[0],
            "aliases": sorted(set(models)),
            "mount": mount.strip(),
            "cropFactor": float(crop) if crop else 1.0,
        }


def main():
    source, output = Path(sys.argv[1]), Path(sys.argv[2])
    lenses, cameras = [], []
    for path in sorted(source.glob("*.xml")):
        lenses.extend(lens_entries(path))
        cameras.extend(camera_entries(path))
    lenses.sort(key=lambda l: (l["maker"].lower(), l["model"].lower()))
    payload = {
        "source": "Lensfun database, https://github.com/lensfun/lensfun (data/db)",
        "license": "CC-BY-SA 3.0 — https://creativecommons.org/licenses/by-sa/3.0/",
        "cameras": cameras,
        "lenses": lenses,
    }
    output.write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))
    print(f"{len(lenses)} lenses with distortion data, {len(cameras)} cameras -> {output} ({output.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
