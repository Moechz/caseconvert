# Case Converter for TerraMaster TOS 7

An offline [Case Converter](https://caseconverter.cc/) web app packaged as a
**TOS 7 Docker application** for the TerraMaster App Center.

Paste or type text and convert it between **sentence case**, **title case**,
**capital case**, **lower case** and **UPPER CASE**, with live word and
character counts.

## Highlights

- **Fully offline.** The web page is embedded in `docker-compose.yml`; the only
  thing pulled from the network at install time is the nginx image from Docker
  Hub. After that the app never touches the network.
- **Private by design.** All conversion runs in your browser. No text is
  uploaded, no analytics, no ads, no cookies, no account.
- **Non-root.** The container runs as uid/gid `1000:1000` with a fixed,
  reproducible nginx image.
- **Clean.** The upstream site's Google Analytics, Google AdSense and external
  Formspree contact form have been removed.

## Requirements

- TerraMaster TOS 7 (x86_64), App Center
- Docker Engine (installed automatically by the App Center if missing)

## Install

1. Open **App Center → Case Converter → Install**.
2. Wait for the nginx image to download (about 50 MB).
3. Open the app from the desktop, or browse to
   `http://<NAS-IP>:8910/`.

The app data lives in `/Volume*/DockerAppData/caseconvert/`; deleting that
folder resets the app.

### Manual run (development / testing)

```bash
# test/compose-resolved/docker-compose.yml is the published compose with the
# /Volume*/ placeholder resolved to /Volume1/
docker compose -p caseconvert -f test/compose-resolved/docker-compose.yml up -d
# -> http://<IP>:8910/
```

## How it works

```
+-----------------------------------------------------------+
| caseconvert.tar.gz  (Release asset, contains 4 files)     |
|   config.ini, caseconvert.lang, caseconvert.svg,          |
|   docker-compose.yml  <- web page embedded as base64      |
+-----------------------------------------------------------+
                    |  App Center
                    v
   docker compose up  ->  nginxinc/nginx-unprivileged (Docker Hub)
                          extracts SITE_B64 to the data dir
                          serves it on container port 8080
                          published as host port 8910
```

- `src/docker-compose.yml` is a **template**; `scripts/build.sh` regenerates the
  base64 site payload from the human-readable `site/` directory and writes the
  final four-file package to `out/`.
- To inspect the embedded payload of a built package:

  ```bash
  tar xzOf out/caseconvert.tar.gz docker-compose.yml \
    | sed -n '/SITE_B64: |-/,/END embedded site payload/p' \
    | sed '1d;$d' | tr -d ' \t' | base64 -d | tar tzf -
  ```

  Or simply `scripts/unpack-site.sh out/caseconvert.tar.gz /tmp/site-review`.

## Build from source

```bash
scripts/build.sh 2024.2.11-1            # x86_64 (default)
scripts/build.sh 2024.2.11-1 aarch64    # other architecture
```

The script builds the deterministic site bundle, embeds it into the compose
file, runs the TOS review-standards self-check and packs
`out/caseconvert.tar.gz` + `out/caseconvert.tar.gz.sha256`.

`site/` can be regenerated from the upstream repository with
`scripts/make-site.py` (see the script header).

## Repository layout

```
src/          the four package files (config.ini, *.lang, *.svg, compose template)
site/         the TOS edition of the web app (source of the embedded payload)
scripts/      build.sh (build + verify + pack), make-site.py (upstream -> site/)
out/          build output (generated)
test/         volume-resolved compose for manual testing
```

## Upstream & license

- Upstream project: <https://github.com/caseconverter/caseconverter> (MIT)
- Upstream author: Case Converter
- Packaged for TOS by **Moechz**

The bundled web page is MIT-licensed; see [`LICENSE.md`](LICENSE.md).

## Versioning

`2024.2.11-1` = upstream snapshot `2024.2.11` + packaging iteration `1`.

The upstream project publishes no releases or version tags, so the version base is
the date of the upstream commit this build was made from
(`a6581d1f1bab0cfb6fe85d8f245610a82c1083e7`, 2024-02-11). The version is kept
identical in `config.ini`, every language section of `caseconvert.lang`, and the
GitHub Release tag (`v2024.2.11-1`).
