#!/usr/bin/env python3
"""Convert the Lensfun database (data/db/*.xml) to the lens table ShotDex embeds.

Usage: Tools/lensfun-to-json.py <lensfun data/db dir> <output json> [--previous <json>]
                                [--commit <sha>] [--date <yyyy-mm-dd>]

Kept: maker, model strings (every language variant), mounts, calibration crop
factor, aspect ratio, and per lens the three corrections ShotDex reads —
distortion (poly3 / poly5 / ptlens), vignetting (pa, by focal, aperture and
distance, as `vignettingPA` rows [focal, aperture, distance, k1, k2, k3]) and
transverse chromatic aberration (linear / poly3) — plus each
camera's mount and crop factor so a lens can be matched to the body it was used
on. A lens with any one of the three is kept. The strings and numbers are copied
as they are — Lensfun is CC-BY-SA 3.0, and ShotDex keeps every change of its own
(name matching) outside the data so the table stays a verbatim subset.

The Lensfun commit and date go into the table's source (from --commit/--date,
or read from the git checkout the directory is in). With --previous, one line
compares the new table with the one it replaces, and lens ids that disappeared
are listed (FS-03.16b §4).

Fails — exit code 1, output file untouched — when the directory has no lenses,
the lens count drops more than 1% against --previous, or the JSON is larger than
the 4 MB ceiling.
"""
import argparse
import json
import os
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

CEILING_BYTES = 4 * 1024 * 1024
MAXIMUM_DROP = 0.01


def number(element, key):
    value = element.get(key)
    return float(value) if value is not None else None


def lens_entries(path):
    root = ET.parse(path).getroot()
    for lens in root.iter("lens"):
        distortion, vignetting, tca = [], [], []
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
            for v in cal.iter("vignetting"):
                if v.get("model") != "pa":
                    continue
                # One row per measurement: focal, aperture, distance, k1, k2,
                # k3 — the numbers as Lensfun has them, without 29 000 copies
                # of the key names (they were half the table).
                vignetting.append([
                    float(v.get("focal", "0")),
                    float(v.get("aperture", "0")),
                    float(v.get("distance", "0")),
                    float(v.get("k1", "0")),
                    float(v.get("k2", "0")),
                    float(v.get("k3", "0")),
                ])
            for t in cal.iter("tca"):
                model = t.get("model")
                if model not in ("linear", "poly3"):
                    continue
                entry = {"model": model, "focal": float(t.get("focal", "0"))}
                for key in ("kr", "kb", "br", "cr", "vr", "bb", "cb", "vb"):
                    if t.get(key) is not None:
                        entry[key] = float(t.get(key))
                tca.append(entry)
        if not (distortion or vignetting or tca):
            continue
        models = [m.text.strip() for m in lens.findall("model") if m.text]
        makers = [m.text.strip() for m in lens.findall("maker") if m.text and m.get("lang") is None]
        plain_models = [m.text.strip() for m in lens.findall("model") if m.text and m.get("lang") is None]
        if not models or not makers or not plain_models:
            continue
        crop = lens.findtext("cropfactor")
        aspect = lens.findtext("aspect-ratio")
        entry = {
            "maker": makers[0],
            "model": plain_models[0],
            "aliases": sorted(set(models)),
            "mounts": [m.text.strip() for m in lens.findall("mount") if m.text],
            "cropFactor": float(crop) if crop else 1.0,
            "aspectRatio": aspect.strip() if aspect else None,
            "distortion": sorted(distortion, key=lambda e: e["focal"]),
        }
        if vignetting:
            entry["vignettingPA"] = sorted(vignetting)
        if tca:
            entry["tca"] = sorted(tca, key=lambda e: e["focal"])
        yield entry


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


def lens_id(lens):
    """The id the app keys a chosen lens by (`LensfunLens.id`)."""
    crop = lens["cropFactor"]
    crop_text = repr(float(crop))
    return f'{lens["maker"]}|{lens["model"]}|{crop_text}'


def git_revision(directory):
    try:
        out = subprocess.run(
            ["git", "-C", str(directory), "log", "-1", "--format=%H %cs"],
            capture_output=True, text=True, check=True,
        ).stdout.split()
        return (out[0], out[1]) if len(out) == 2 else (None, None)
    except (OSError, subprocess.CalledProcessError):
        return (None, None)


def counts(payload):
    lenses = payload.get("lenses", [])
    return {
        "lenses": len(lenses),
        "vignetting": sum(1 for l in lenses if l.get("vignettingPA")),
        "tca": sum(1 for l in lenses if l.get("tca")),
        "cameras": len(payload.get("cameras", [])),
    }


def kilobytes(size):
    return f"{round(size / 1024)}KB"


def fail(message):
    print(f"lensfun-to-json: {message}", file=sys.stderr)
    sys.exit(1)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--previous", type=Path)
    parser.add_argument("--commit")
    parser.add_argument("--date")
    parser.add_argument("--ceiling", type=int, default=CEILING_BYTES, help=argparse.SUPPRESS)
    args = parser.parse_args(argv)

    lenses, cameras = [], []
    for path in sorted(args.source.glob("*.xml")):
        lenses.extend(lens_entries(path))
        cameras.extend(camera_entries(path))
    if not lenses:
        fail(f"no lenses in {args.source} — nothing written")
    lenses.sort(key=lambda l: (l["maker"].lower(), l["model"].lower()))

    commit, date = args.commit, args.date
    if commit is None or date is None:
        found_commit, found_date = git_revision(args.source)
        commit, date = commit or found_commit, date or found_date
    payload = {
        "source": "Lensfun database, https://github.com/lensfun/lensfun (data/db)",
        "lensfunCommit": commit,
        "lensfunDate": date,
        "license": "CC-BY-SA 3.0 — https://creativecommons.org/licenses/by-sa/3.0/",
        "cameras": cameras,
        "lenses": lenses,
    }
    text = json.dumps(payload, ensure_ascii=False, separators=(",", ":"))
    size = len(text.encode("utf-8"))
    now = counts(payload)

    if size > args.ceiling:
        fail(f"table is {kilobytes(size)}, over the {kilobytes(args.ceiling)} ceiling — nothing written")

    vanished = []
    if args.previous is not None and args.previous.exists():
        previous_text = args.previous.read_text()
        previous = json.loads(previous_text)
        before = counts(previous)
        drop = (before["lenses"] - now["lenses"]) / before["lenses"] if before["lenses"] else 0
        if drop > MAXIMUM_DROP:
            fail(f"lens count fell {before['lenses']} → {now['lenses']} (more than 1%) — nothing written")

        def arrow(key):
            delta = now[key] - before[key]
            return f"{before[key]} → {now[key]} ({delta:+d})"

        print(
            f"Lens profiles {arrow('lenses')} · vignetting {arrow('vignetting')} · TCA {arrow('tca')}"
            f" · cameras {arrow('cameras')} · {kilobytes(len(previous_text.encode('utf-8')))} → {kilobytes(size)}"
        )
        new_ids = {lens_id(l) for l in lenses}
        vanished = sorted(lens_id(l) for l in previous.get("lenses", []) if lens_id(l) not in new_ids)
        for identifier in vanished:
            print(f"warning: lens id gone: {identifier}")

    # Written beside the target and moved over it, so a failure half-way never
    # leaves a truncated table in the bundle.
    args.output.parent.mkdir(parents=True, exist_ok=True)
    handle, temporary = tempfile.mkstemp(dir=args.output.parent, suffix=".json")
    with os.fdopen(handle, "w", encoding="utf-8") as stream:
        stream.write(text)
    os.replace(temporary, args.output)
    print(
        f"{now['lenses']} lenses ({now['vignetting']} with vignetting, {now['tca']} with TCA), "
        f"{now['cameras']} cameras, Lensfun {commit or '?'} {date or '?'} -> {args.output} ({kilobytes(size)})"
    )


if __name__ == "__main__":
    main()
