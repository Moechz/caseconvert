#!/usr/bin/env python3
"""Build the TOS edition of the Case Converter static site from the upstream
`docs/` tree (the upstream production site).

What it changes vs. upstream (all changes are recorded in
docs/DESIGN_DECISIONS.md D-002):

  * removes Google Analytics (gtag) and Google AdSense (adsbygoogle) scripts
  * removes JSON-LD blocks, canonical / og:image / og:url meta (they carry the
    live site's absolute https://caseconverter.cc URLs, meaningless offline)
  * rewrites absolute https://caseconverter.cc links to relative pages
  * drops the external Formspree contact form (it POSTs to a third-party site)
  * keeps only the assets the pages actually use (favicon.ico, img/contact.png)
  * replaces the generic upstream privacy policy with a short, accurate
    bilingual policy for the offline TOS app

Usage: scripts/make-site.py [upstream-docs-dir] [output-dir]
Default: build/upstream/docs -> site
"""
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "build" / "upstream" / "docs"
DST = Path(sys.argv[2]) if len(sys.argv) > 2 else ROOT / "site"

JSONLD = re.compile(r'<script type="application/ld\+json">.*?</script>\n?', re.S)
GA_SRC = re.compile(r'<script async src="https://www\.googletagmanager\.com[^"]*"></script>\n?')
GA_INLINE = re.compile(r'<script>\s*window\.dataLayer.*?</script>\n?', re.S)
ADSENSE = re.compile(r'<script async src="https://pagead2\.googlesyndication\.com[^>]*></script>\n?')
CANONICAL = re.compile(r'<link rel="canonical"[^>]*>\n?')
OG_URL = re.compile(r'<meta property="og:(?:image|url)"[^>]*>\n?')

LINK_MAP = [
    ("https://caseconverter.cc/terms", "terms.html"),
    ("https://caseconverter.cc/privacy", "privacy.html"),
    ("https://caseconverter.cc/contact", "contact.html"),
    ("https://caseconverter.cc/", "index.html"),
    ("https://caseconverter.cc", "index.html"),
]

# the Formspree form (external POST target) and its section
CONTACT_FORM = re.compile(r'<h2>Contact Form</h2>.*?</form>\n?', re.S)
STYLE_FORM = re.compile(r'<link rel="stylesheet" href="/style-form\.css">\n?')

PRIVACY = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Privacy Policy | Case Converter for TerraMaster TOS</title>
<meta name="description" content="Privacy policy for the Case Converter TOS application. The app runs entirely on your NAS; no text is uploaded, no analytics, no ads, no cookies.">
<link rel="stylesheet" href="/style.css">
<link rel="icon" href="/favicon.ico" type="image/x-icon">
</head>
<body>

<a href="index.html" style="text-decoration: none; color: inherit;"><h1>Privacy Policy</h1></a>

<h2>English</h2>
<p><b>Case Converter for TerraMaster TOS</b> is a fully local, offline
application. Everything it does happens inside the Docker container on your own
NAS.</p>
<ul>
<li><b>Your text is never uploaded.</b> Case conversion and the word/character
count run in your browser (JavaScript) and the text is never sent to the NAS,
to us, or to any third party.</li>
<li><b>No analytics, no advertising, no tracking.</b> The upstream website uses
Google Analytics and Google AdSense; both have been removed from this TOS
edition. The container makes no outbound network connections while you use it.</li>
<li><b>No cookies, no accounts.</b> The application has no login, no user
profile and sets no cookies.</li>
<li><b>No personal data is collected or stored.</b> The application keeps no
database and no access log of your input.</li>
<li><b>Network access.</b> The only network activity is the one-time image
download performed by the TOS App Center when you install the application (the
nginx container image from Docker Hub). After that the app works offline.</li>
</ul>
<p>The application embeds the static, MIT-licensed Case Converter web page
(<a href="https://github.com/caseconverter/caseconverter" target="_blank" rel="noopener noreferrer">github.com/caseconverter/caseconverter</a>).
If you have any question about this policy, please open an issue at
<a href="https://github.com/Moechz/caseconvert/issues" target="_blank" rel="noopener noreferrer">github.com/Moechz/caseconvert/issues</a>.</p>

<h2>简体中文</h2>
<p><b>Case Converter for TerraMaster TOS</b> 是一个完全本地、离线的应用，
所有处理都在您自己 NAS 上的 Docker 容器内完成。</p>
<ul>
<li><b>文本不会上传。</b>大小写转换与字数统计在您的浏览器内（JavaScript）
完成，文本不会发送到 NAS、我们或任何第三方。</li>
<li><b>无统计、无广告、无追踪。</b>上游网站使用 Google Analytics 与
Google AdSense，本 TOS 版本已全部移除；使用过程中容器不发起任何对外连接。</li>
<li><b>无 Cookie、无账号。</b>本应用没有登录、没有用户资料，也不设置 Cookie。</li>
<li><b>不收集、不存储任何个人数据。</b>应用不保存数据库，也不记录您的输入。</li>
<li><b>网络访问。</b>唯一的网络活动是安装时 TOS 应用中心从 Docker Hub
下载 nginx 镜像；此后应用可完全离线运行。</li>
</ul>
<p>本应用内嵌 MIT 许可的静态 Case Converter 网页
（<a href="https://github.com/caseconverter/caseconverter" target="_blank" rel="noopener noreferrer">github.com/caseconverter/caseconverter</a>）。
如有疑问，请在
<a href="https://github.com/Moechz/caseconvert/issues" target="_blank" rel="noopener noreferrer">github.com/Moechz/caseconvert/issues</a> 提出。</p>

<p style="font-size:80%;text-align:center;"><a href="index.html">Home</a> | <a href="terms.html">Terms of Use</a> | <a href="contact.html">Contact</a></p>

</body>
</html>
"""


def transform(html: str) -> str:
    html = JSONLD.sub("", html)
    html = GA_SRC.sub("", html)
    html = GA_INLINE.sub("", html)
    html = ADSENSE.sub("", html)
    html = CANONICAL.sub("", html)
    html = OG_URL.sub("", html)
    for old, new in LINK_MAP:
        html = html.replace(old, new)
    return html


def main() -> None:
    if not SRC.is_dir():
        sys.exit(f"upstream docs dir not found: {SRC}")
    if DST.exists():
        shutil.rmtree(DST)
    (DST / "img").mkdir(parents=True)

    for name in ("index.html", "contact.html", "terms.html"):
        text = (SRC / name).read_text(encoding="utf-8")
        text = transform(text)
        if name == "contact.html":
            text = CONTACT_FORM.sub("", text)
            text = STYLE_FORM.sub("", text)
        (DST / name).write_text(text, encoding="utf-8")
        print("wrote", name, len(text), "bytes")

    (DST / "privacy.html").write_text(PRIVACY, encoding="utf-8")
    print("wrote privacy.html")

    for rel in ("style.css", "favicon.ico", "img/contact.png"):
        shutil.copy2(SRC / rel, DST / rel)
        print("copied", rel)

    # sanity: no tracker / external-form / live-site references left
    banned = ("googletagmanager", "googlesyndication", "formspree",
              "caseconverter.cc/img", 'property="og:image"')
    for p in sorted(DST.rglob("*.html")):
        body = p.read_text(encoding="utf-8")
        for b in banned:
            if b in body:
                sys.exit(f"ERROR: {p.name} still contains {b!r}")
    print("site OK:", sum(f.stat().st_size for f in DST.rglob("*") if f.is_file()), "bytes")


if __name__ == "__main__":
    main()
