"""Give the exported attachments their real names.

`xcresulttool export attachments` appends "_<index>_<uuid>" to every file so
two attachments with the same name cannot collide. The driver already names
each artifact itself, so strip the suffix back off and drop the manifest.
"""
import os
import re
import shutil
import sys

out = sys.argv[1]
unique = re.compile(r"_\d+_[0-9A-Fa-f-]{36}(?=\.[A-Za-z0-9]+$)")

for name in os.listdir(out):
    if name == "manifest.json":
        os.remove(os.path.join(out, name))
        continue
    wanted = unique.sub("", name)
    if wanted != name:
        shutil.move(os.path.join(out, name), os.path.join(out, wanted))
