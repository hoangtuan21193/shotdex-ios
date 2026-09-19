"""Give the exported attachments their real names.

`xcresulttool export attachments` writes each file under an opaque name and a
manifest.json that maps it back to the name the test gave it; older
toolchains instead append "_<index>_<uuid>" to the real name. Handle both,
and leave anything unrecognised alone rather than clobbering it.
"""
import json
import os
import re
import shutil
import sys

out = sys.argv[1]
unique = re.compile(r"_\d+_[0-9A-Fa-f-]{36}(?=\.[A-Za-z0-9]+$)")
manifest = os.path.join(out, "manifest.json")


def rename(src_name, wanted):
    if not wanted or wanted == src_name:
        return
    src = os.path.join(out, src_name)
    if os.path.exists(src):
        shutil.move(src, os.path.join(out, wanted))


if os.path.exists(manifest):
    with open(manifest) as handle:
        tests = json.load(handle)
    for test in tests:
        for item in test.get("attachments", []):
            exported = item.get("exportedFileName")
            if not exported:
                continue
            rename(exported, item.get("suggestedHumanReadableName") or unique.sub("", exported))
    os.remove(manifest)

for name in os.listdir(out):
    rename(name, unique.sub("", name))
