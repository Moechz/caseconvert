#!/bin/bash
# Build the Case Converter TOS Docker application package
# (out/caseconvert.tar.gz + .sha256).
#
# Usage: scripts/build.sh [version] [platform]
#   version  default: 2024.2.11-4
#            format : <upstream-base>-<packaging-iteration>, strictly increasing
#   platform default: x86_64   (x86_64 | aarch64; config.ini.platform follows it)
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$(pwd)
SRC="$ROOT/src"
SITE="$ROOT/site"
STAGE="$ROOT/build/stage"
DIST="$ROOT/dist"
OUT="$ROOT/out"
APPID="caseconvert"

VERSION="${1:-2024.2.11-4}"
PLATFORM="${2:-x86_64}"

case "$PLATFORM" in
  x86_64|aarch64) : ;;
  *) echo "FATAL: platform must be x86_64 or aarch64 (got '$PLATFORM')"; exit 1 ;;
esac
case "$VERSION" in
  *-0|*-0[0-9]*)
    echo "FATAL: packaging iteration must not be zero padded (got '$VERSION')"; exit 1 ;;
  [0-9]*.[0-9]*.[0-9]*-[1-9]*) : ;;
  *) echo "FATAL: version must look like MAJOR.MINOR.PATCH-<iteration> (got '$VERSION')"; exit 1 ;;
esac

echo ">> packaging ${APPID} version ${VERSION} platform ${PLATFORM}"

rm -rf "$STAGE" "$DIST" "$OUT"
mkdir -p "$STAGE" "$DIST" "$OUT"

# ---------- 1. deterministic site bundle ----------
python3 - "$SITE" "$DIST/site.tar.gz" <<'PY'
import io, gzip, pathlib, sys, tarfile
site, dest = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
if not (site / "index.html").is_file():
    sys.exit(f"FATAL: {site}/index.html not found; run scripts/make-site.py first")
buf = io.BytesIO()
with tarfile.open(fileobj=buf, mode="w", format=tarfile.GNU_FORMAT) as tf:
    # directories first, sorted, so the archive is deterministic
    for d in sorted([p for p in site.rglob("*") if p.is_dir()]):
        ti = tf.gettarinfo(str(d), arcname=str(d.relative_to(site)))
        ti.uid = ti.gid = 0; ti.uname = ti.gname = "root"; ti.mtime = 0; ti.mode = 0o755
        tf.addfile(ti)
    for f in sorted([p for p in site.rglob("*") if p.is_file()]):
        ti = tf.gettarinfo(str(f), arcname=str(f.relative_to(site)))
        ti.uid = ti.gid = 0; ti.uname = ti.gname = "root"; ti.mtime = 0; ti.mode = 0o644
        with open(f, "rb") as fh:
            tf.addfile(ti, fh)
with open(dest, "wb") as fh:
    with gzip.GzipFile(fileobj=fh, mode="wb", compresslevel=9, mtime=0) as gz:
        gz.write(buf.getvalue())
print(f"site bundle: {dest} {dest.stat().st_size} bytes")
PY

# ---------- 2. base64 (wrapped, for embedding in docker-compose.yml) ----------
python3 - "$DIST/site.tar.gz" "$DIST/site.b64" <<'PY'
import base64, pathlib, sys
src, dest = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
data = base64.b64encode(src.read_bytes()).decode("ascii")
lines = [data[i:i+100] for i in range(0, len(data), 100)]
dest.write_text("\n".join(lines), encoding="ascii")
print(f"base64: {dest} {dest.stat().st_size} bytes, {len(lines)} lines")
PY

# ---------- 3. assemble the four package files ----------
for f in config.ini "$APPID.lang" "$APPID.svg" docker-compose.yml; do
  cp "$SRC/$f" "$STAGE/$f"
done

python3 - "$STAGE" "$DIST/site.b64" "$VERSION" "$PLATFORM" "$APPID" <<'PY'
import pathlib, sys
stage, b64file, ver, plat, appid = (pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]),
                                     sys.argv[3], sys.argv[4], sys.argv[5])
b64 = b64file.read_text(encoding="ascii").strip()

for name in ("config.ini", f"{appid}.lang"):
    p = stage / name
    text = p.read_text(encoding="utf-8").replace("@@VERSION@@", ver).replace("@@PLATFORM@@", plat)
    p.write_bytes(text.replace("\r\n", "\n").encode("utf-8"))

comp = stage / "docker-compose.yml"
text = comp.read_text(encoding="utf-8")
assert "@@SITE_B64@@" in text, "docker-compose.yml is missing the @@SITE_B64@@ placeholder"
# first base64 line keeps the placeholder's own 8-space indentation; the rest
# are indented to the same level so the YAML literal block stays aligned
comp.write_text(text.replace("@@SITE_B64@@", b64.replace("\n", "\n        ")), encoding="utf-8")
print("substituted version/platform/base64")
PY

# ---------- 4. build-machine hygiene + line endings ----------
export COPYFILE_DISABLE=1
find "$STAGE" \( -name '._*' -o -name '.DS_Store' \) -delete
xattr -rc "$STAGE" 2>/dev/null || true
python3 - "$STAGE" <<'PY'
import pathlib, sys
stage = pathlib.Path(sys.argv[1])
for p in stage.rglob("*"):
    if p.is_file():
        b = p.read_bytes()
        if b.startswith(b"\xef\xbb\xbf"):
            b = b[3:]
        if b"\r\n" in b:
            b = b.replace(b"\r\n", b"\n")
        p.write_bytes(b)
PY

# ---------- 5. verify (TOS review-standards self-check) ----------
python3 - "$STAGE" "$VERSION" "$PLATFORM" "$APPID" "$SITE" "$DIST/site.tar.gz" <<'PY'
import base64, hashlib, io, json, re, sys, tarfile, pathlib
import xml.etree.ElementTree as ET

stage, ver, plat, appid, site, bundle = (pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3],
                                         sys.argv[4], pathlib.Path(sys.argv[5]), pathlib.Path(sys.argv[6]))
errs = []
def chk(cond, msg):
    if not cond:
        errs.append(msg)

# ---- exactly the four required files at the archive root ----
names = sorted(p.name for p in stage.iterdir())
chk(names == sorted(["config.ini", f"{appid}.lang", f"{appid}.svg", "docker-compose.yml"]),
    f"archive must contain exactly 4 required files, got {names}")

# ---- config.ini ----
raw_cfg = (stage / "config.ini").read_text(encoding="utf-8")
chk("@@" not in raw_cfg, "config.ini still contains unreplaced @@PLACEHOLDER@@")
cfg = json.loads(raw_cfg)
chk(cfg["id"] == appid, "id must equal appid")
chk(cfg["version"] == ver, f"config.ini version must be {ver}")
chk(cfg["application_type"] == "docker", "application_type must be docker")
chk("DockerEngine" in cfg["depend"], "depend must include DockerEngine")
chk("docker" in cfg["relation"] and "DockerEngine" in cfg["relation"], "relation must list docker + DockerEngine")
chk("type" not in cfg, "deb-only 'type' field must NOT appear (Docker apps use open_path)")
chk(cfg.get("open_path") is True, "open_path must be true")
chk(cfg["icon"] == f"/images/icons/{appid}.svg", "icon must be /images/icons/<appid>.svg")
chk(cfg["compose_project"] == appid, "compose_project must equal appid")
chk(cfg["platform"] == plat, f"config.ini platform must be {plat}")
chk(cfg.get("beta") is False, "beta must be false for a store submission")
chk(cfg.get("publisher") == "Moechz", "publisher must be Moechz (packaging guide pitfall 49)")
chk(isinstance(cfg.get("category"), list) and 1 <= len(cfg["category"]) <= 3,
    "category must be a list of 1..3 official categories")
for fld in ("id", "icon", "publisher", "exec", "version", "low_version", "category",
            "depend", "platform", "application_type", "user", "all_user_display",
            "allow_open_in_mobile", "path", "name", "help"):
    chk(fld in cfg, f"required config.ini field missing: {fld}")
m = re.fullmatch(r"http://\$\{ip\}:(\d+)", cfg["path"])
chk(m is not None, "path must be http://${ip}:<port> (Docker app URL form)")
cfg_port = int(m.group(1)) if m else 0
for bad in ("help", "official", "Official"):
    v = cfg.get(bad)
    if v:
        chk(v.startswith("https://github.com/"),
            f"{bad} must be a github.com URL (link checker does an HTTP GET)")

# ---- lang ----
lang = (stage / f"{appid}.lang").read_text(encoding="utf-8")
chk("@@" not in lang, "lang still contains unreplaced @@PLACEHOLDER@@")
secs = re.findall(r"^\[([a-z]{2}-[a-z]{2})\]$", lang, re.M)
required14 = set("zh-cn zh-hk en-us fr-fr de-de it-it es-es hu-hu ja-jp ko-kr "
                 "pl-pl ru-ru tr-tr pt-pt".split())
chk(required14.issubset(set(secs)), f"lang missing required languages: {sorted(required14 - set(secs))}")
chk(len(secs) == len(set(secs)), "lang has duplicate language sections")
for s in secs:
    body = lang.split(f"[{s}]", 1)[1].split("[", 1)[0]
    for key in ("name", "auth", "version", "descript", "release_note", "important"):
        mm = re.search(rf'{key}\s*=\s*"(.+)"', body)
        chk(mm is not None and mm.group(1).strip(), f"[{s}] {key} empty or missing")
    chk(f'version      = "{ver}"' in body, f"[{s}] version != {ver}")
chk(re.search(r"\bbeta\b", lang, re.I) is None, "lang must not contain the word 'beta' (V11)")

# ---- svg icon (TOS Icon Compliance: <= 50 KB, <= 50 elements) ----
svg_path = stage / f"{appid}.svg"
svg_bytes = svg_path.read_bytes()
chk(len(svg_bytes) <= 50 * 1024, f"icon too large: {len(svg_bytes)} bytes (limit 50 KB)")
svg_txt = svg_bytes.decode("utf-8")
try:
    root = ET.fromstring(svg_txt)
    n_elems = sum(1 for _ in root.iter())
    chk(root.tag.endswith("svg"), "icon root element must be <svg>")
    chk("viewBox" in root.attrib, "icon svg must declare viewBox")
    chk(n_elems <= 50, f"icon has {n_elems} elements (limit 50)")
except ET.ParseError as e:
    errs.append(f"icon is not valid XML: {e}")
for banned in ("<filter", "<use", "sodipodi", "inkscape", "<metadata", "rdf:"):
    chk(banned not in svg_txt, f"icon must not contain {banned}")

# ---- docker-compose.yml ----
comp = (stage / "docker-compose.yml").read_text(encoding="utf-8")
chk("@@" not in comp, "compose still contains unreplaced @@PLACEHOLDER@@")
comp_nc = "\n".join(l for l in comp.splitlines() if not l.lstrip().startswith("#"))
chk(re.search(r"(?<![-\w])privileged(?![-\w])", comp_nc) is None,
    "compose must not use privileged mode (note: the image name 'unprivileged' is fine)")
for banned in ("network_mode", "docker.sock", "cap_add", "pid:", "ipc:"):
    chk(banned not in comp_nc, f"compose must not use {banned}")
chk(re.search(r"ghcr\.io|quay\.io|lscr\.io|registry\.", comp_nc) is None,
    "images must come from Docker Hub (bare names)")
chk(":latest" not in comp_nc, "image must use a fixed tag, never :latest")
chk("nginxinc/nginx-unprivileged:1.27-alpine" in comp_nc, "expected the pinned nginx-unprivileged image")
chk(re.search(rf"container_name:\s*{appid}\s*$", comp_nc, re.M) is not None,
    "main container_name must equal appid")
services = comp_nc.count("container_name:")
chk(services == 1, f"expected exactly one service, got {services}")
chk(comp_nc.count('user: "1000:1000"') == services, "every service must pin non-root user 1000:1000")
chk(comp_nc.count("restart: unless-stopped") == services, "every service must use restart: unless-stopped")
chk(comp_nc.count("healthcheck:") == services, "every service must define a healthcheck")
chk(len(re.findall(r"^\s+TZ:\s*\S", comp_nc, re.M)) == services, "every service must set TZ explicitly")
chk(f"/Volume*/DockerAppData/{appid}/" in comp_nc, f"volumes must live under /Volume*/DockerAppData/{appid}/")
chk(comp_nc.rstrip().endswith("protocol: http"), "x-app-meta must be the last block")
chk("x-app-meta:" in comp_nc and f"port: {cfg_port}" in comp_nc,
    "x-app-meta web.port must match config.ini path port")
ports = re.findall(r"^\s*-\s*[\"'](\d+):(\d+)[\"']\s*$", comp_nc, re.M)
chk(len(ports) == 1, f"compose must publish exactly one host port, got {ports}")
if len(ports) == 1:
    host, cont = int(ports[0][0]), int(ports[0][1])
    chk(host == cfg_port, f"published host port {host} != config.ini path port {cfg_port}")
    chk(host not in (22, 80, 443, 445, 3306, 5050, 5432, 6379, 8080, 8181, 8443),
        f"host port {host} is reserved or already used by the platform")
    chk(8000 <= host <= 19999, f"host port {host} outside the TOS-recommended 8000-19999 range")
    chk(cont == 8080, f"container port should be 8080, got {cont}")
for pat, msg in ((r"(?i)(PASSWORD|SECRET|TOKEN|API_KEY):\s*\S", "compose must not contain a literal secret"),):
    chk(re.search(pat, comp_nc) is None, msg)
# every '$' must be escaped as '$$' (compose does ${VAR} interpolation)
bad_dollars = re.findall(r"(?<!\$)\$\{?[A-Za-z_]", comp_nc)
chk(not bad_dollars, f"unescaped '$' in compose (use '$$'): {sorted(set(bad_dollars))}")
chk("$$uri" in comp_nc, "nginx try_files must use '$$uri'")
chk("listen 8080;" in comp_nc, "nginx config must listen on 8080")
chk("x-app-meta:" in comp_nc, "compose must contain x-app-meta")

# ---- embedded site: decode SITE_B64 and compare with site/ ----
m = re.search(r"SITE_B64:\s*\|-\n((?:[ \t]+[A-Za-z0-9+/=]+[ \t]*\n)+)", comp)
chk(m is not None, "compose must embed the SITE_B64 literal block")
if m:
    b64 = "".join(m.group(1).split())
    try:
        raw = base64.b64decode(b64)
    except Exception as e:
        errs.append(f"SITE_B64 is not valid base64: {e}")
        raw = b""
    chk(raw == bundle.read_bytes(), "embedded SITE_B64 != dist/site.tar.gz (rebuild needed)")
    if raw:
        with tarfile.open(fileobj=io.BytesIO(raw), mode="r:gz") as tf:
            members = sorted(tf.getnames())
            expected = sorted(str(p.relative_to(site)) for p in site.rglob("*")
                              if p.is_file() or p.is_dir())
            chk(members == expected, f"embedded tar members != site/ ({members} vs {expected})")
            for ti in tf.getmembers():
                chk(ti.uid == 0 and ti.gid == 0 and ti.mtime == 0,
                    f"tar member {ti.name} is not deterministic (uid/gid/mtime)")
            fdata = tf.extractfile("index.html").read() if "index.html" in members else b""
            chk(b"Case Converter" in fdata, "embedded index.html does not look like the site")
            chk(b"googletagmanager" not in fdata and b"googlesyndication" not in fdata,
                "embedded site still contains trackers")

if errs:
    print("VERIFY FAIL:")
    for e in errs:
        print("  -", e)
    sys.exit(1)
print(f"verify OK: files={names} langs={len(secs)} icon_elements={n_elems} "
      f"icon_bytes={len(svg_bytes)} host_port={cfg_port} site_bundle={bundle.stat().st_size}B")
PY

# ---------- 6. pack (deterministic tar.gz) ----------
python3 - "$STAGE" "$OUT" "$APPID" <<'PY'
import tarfile, pathlib, gzip, io, sys
stage, out, appid = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3]
tarpath = out / f"{appid}.tar.gz"
buf = io.BytesIO()
with tarfile.open(fileobj=buf, mode="w", format=tarfile.GNU_FORMAT) as tf:
    for p in sorted(stage.iterdir()):
        ti = tf.gettarinfo(str(p), arcname=p.name)
        ti.uid = ti.gid = 0
        ti.uname = ti.gname = "root"
        ti.mtime = 0
        ti.mode = 0o644
        with open(p, "rb") as fh:
            tf.addfile(ti, fh)
with open(tarpath, "wb") as fh:
    with gzip.GzipFile(fileobj=fh, mode="wb", compresslevel=9, mtime=0) as gz:
        gz.write(buf.getvalue())
print("packed", tarpath, f"{tarpath.stat().st_size} bytes")
PY

python3 - "$OUT" "$APPID" <<'PY'
import hashlib, pathlib, sys
out, appid = pathlib.Path(sys.argv[1]), sys.argv[2]
p = out / f"{appid}.tar.gz"
h = hashlib.sha256(p.read_bytes()).hexdigest()
(out / f"{appid}.tar.gz.sha256").write_text(f"{h}  {appid}.tar.gz\n")
print(f"sha256 {h}  {appid}.tar.gz")
PY

# ---------- 7. volume-resolved copy for manual (non-store) testing ----------
mkdir -p "$ROOT/test/compose-resolved"
sed 's#/Volume\*/DockerAppData/#/Volume1/DockerAppData/#g' "$STAGE/docker-compose.yml" \
  > "$ROOT/test/compose-resolved/docker-compose.yml"

echo ">> done:"
ls -la "$OUT"
