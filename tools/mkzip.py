#!/usr/bin/env python3
"""Zip a directory with entries at the archive ROOT (itch.io requires
index.html at zip root). stdlib-only: this host has no `zip` binary.
Usage: mkzip.py <out.zip> <dir>"""
import os
import sys
import zipfile

def main() -> int:
    if len(sys.argv) != 3:
        print("usage: mkzip.py <out.zip> <dir>", file=sys.stderr)
        return 2
    out, src = sys.argv[1], sys.argv[2]
    if not os.path.isdir(src):
        print(f"not a directory: {src}", file=sys.stderr)
        return 2
    names = []
    for root, _dirs, files in os.walk(src):
        for f in files:
            p = os.path.join(root, f)
            names.append((p, os.path.relpath(p, src).replace(os.sep, "/")))
    names.sort(key=lambda t: t[1])
    if ("index.html" not in [n for _p, n in names]):
        print("refusing to write zip: index.html missing at root "
              "(itch.io requirement)", file=sys.stderr)
        return 1
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
        for p, n in names:
            zf.write(p, n)
    print(f"wrote {out} ({len(names)} entries, "
          f"{os.path.getsize(out)} bytes)")
    return 0

if __name__ == "__main__":
    sys.exit(main())
