#!/bin/bash
# Print or extract the web page embedded in a built Case Converter package.
#
# Usage:
#   scripts/unpack-site.sh out/caseconvert.tar.gz            # list the files
#   scripts/unpack-site.sh out/caseconvert.tar.gz /tmp/site  # extract them
set -euo pipefail

pkg=${1:?usage: unpack-site.sh <caseconvert.tar.gz> [outdir]}
out=${2:-}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

tar xzOf "$pkg" docker-compose.yml > "$tmp/compose.yml"

python3 - "$tmp/compose.yml" "$tmp/site.tar.gz" <<'PY'
import base64, re, sys
comp, dest = sys.argv[1], sys.argv[2]
text = open(comp, encoding="utf-8").read()
m = re.search(r"SITE_B64:\s*\|-\n((?:[ \t]+[A-Za-z0-9+/=]+[ \t]*\n)+)", text)
if not m:
    sys.exit("ERROR: SITE_B64 block not found in docker-compose.yml")
open(dest, "wb").write(base64.b64decode("".join(m.group(1).split())))
PY

if [ -n "$out" ]; then
  mkdir -p "$out"
  tar xzf "$tmp/site.tar.gz" -C "$out"
  ls -la "$out"
else
  tar tzf "$tmp/site.tar.gz"
fi
