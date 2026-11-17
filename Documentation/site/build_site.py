#!/usr/bin/env python3
"""Builds the static site (user guide + privacy policy) in 8 languages, at the repository root (GitHub Pages serves main at /).

  python3 Documentation/site/build_site.py [--only en,fr] [--snapshot [X.Y]] [--freeze]

Versions: the root is the latest guide; v/<major.minor>/ holds a self-contained copy per app version (the apps link to their own version).
A plain build refreshes the current version's snapshot unless frozen; `--snapshot X.Y --freeze` freezes it at publication.

Content: Documentation/site/<lang>.py (en, fr, de, es, it, pt, zh, ru); each file defines UI (site labels), GUIDE (sections) and PRIVACY.
A section = (id, title, [blocks]); block = ("p", html) | ("ul", [html…]) | ("ol", [html…]) | ("note", html) | ("fig", image, caption) | ("table", [headers], [[cells]…]).
The script REFUSES a language whose structure (sections, number and kind of blocks) differs from English, or that lacks a UI key.
The support address is read from PhotoVideoBackup/App/AppConstants.swift: a single source.
Generated at the root: en/ fr/ de/ es/ it/ pt/ zh-Hans/ ru/, assets/, index.html, privacy-policy.html. Images are in images/.
"""
import html, importlib.util, re, shutil, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
LANGS = [("en", "English"), ("fr", "Français"), ("de", "Deutsch"), ("es", "Español"), ("it", "Italiano"), ("pt", "Português"), ("zh-Hans", "简体中文"), ("ru", "Русский"), ("ja", "日本語"), ("ko", "한국어"), ("hi", "हिन्दी"), ("ar", "العربية")]
UPDATED = "2026-11-17"
BRAND = "PhotoVideoBackup"
FROZEN = ".frozen"   # marker file in v/<X.Y>/: a published version, never rewritten
RTL = {"ar"}   # right-to-left languages: <html dir="rtl">; the stylesheet uses logical (start/end) properties


def load(code: str):
    f = Path(__file__).parent / f"{code.replace('-Hans', '')}.py"
    spec = importlib.util.spec_from_file_location(f"site_{code}", f)
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
    return m


def support_email() -> str:
    s = (ROOT / "PhotoVideoBackup/App/AppConstants.swift").read_text()
    return re.search(r'static let supportEmail\s*=\s*"([^"]+)"', s).group(1)


def shape(sections):
    return [(sid, [b[0] for b in blocks]) for sid, _t, blocks in sections]


def block(b) -> str:
    kind = b[0]
    if kind == "p": return f"<p>{b[1]}</p>"
    if kind == "note": return f'<div class="note">{b[1]}</div>'
    if kind in ("ul", "ol"): return f"<{kind}>" + "".join(f"<li>{x}</li>" for x in b[1]) + f"</{kind}>"
    if kind == "fig":
        return f'<figure class="shot"><img src="../images/{b[1]}.png" alt="{html.escape(re.sub("<[^>]+>", "", b[2]))}" loading="lazy"><figcaption>{b[2]}</figcaption></figure>'
    if kind == "table":
        head = "".join(f"<th>{h}</th>" for h in b[1])
        rows = "".join("<tr>" + "".join(f"<td>{c}</td>" for c in r) + "</tr>" for r in b[2])
        return f'<div class="tablewrap"><table><thead><tr>{head}</tr></thead><tbody>{rows}</tbody></table></div>'
    raise SystemExit(f"unknown block {kind}")


def page(code: str, mod, title: str, body: str, other: str) -> str:
    u = mod.UI
    rtl = ' dir="rtl"' if code in RTL else ""
    langs = " · ".join(f'<a href="../{c}/{other}" hreflang="{c}"{" aria-current=page" if c == code else ""}>{n}</a>' for c, n in LANGS)
    return f"""<!DOCTYPE html>
<html lang="{code}"{rtl}>
<head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(title)}</title>
<link rel="stylesheet" href="../assets/style.css">
</head>
<body>
<header><div class="wrap"><a class="brand" href="../index.html">{BRAND}</a><nav class="langs">{langs}</nav></div></header>
<main class="wrap">
{body}
</main>
<footer><div class="wrap"><p>{u["footer"]}</p></div></footer>
</body>
</html>
"""


def build_guide(code, mod, email):
    u = mod.UI
    toc = "".join(f'<li><a href="#{sid}">{t}</a></li>' for sid, t, _b in mod.GUIDE)
    secs = ""
    for i, (sid, t, blocks) in enumerate(mod.GUIDE, 1):
        secs += f'<section id="{sid}"><h2><span class="n">{i}</span> {t}</h2>' + "".join(block(b) for b in blocks) + "</section>\n"
    body = (f'<h1>{u["guide_title"]}</h1><p class="lead">{u["tagline"]}</p><p class="ver">{u["version_line"]}</p>'
            f'<nav class="toc"><h2>{u["toc"]}</h2><ol>{toc}</ol></nav>{secs}'
            f'<p class="links"><a href="privacy-policy.html">{u["privacy_link"]}</a> · <a href="mailto:{email}">{u["contact"]}: {email}</a></p>')
    return page(code, mod, u["guide_title"], body, "index.html")


def build_privacy(code, mod, email):
    u, p = mod.UI, mod.PRIVACY
    secs = "".join(f"<h2>{t}</h2>" + "".join(block(b) for b in blocks) for t, blocks in p["sections"])
    body = (f'<h1>{p["title"]}</h1><p class="ver">{p["updated"].replace("{date}", UPDATED)}</p><p class="lead">{p["summary"]}</p>{secs}'
            f'<p>{u["contact"]}: <a href="mailto:{email}">{email}</a></p>'
            f'<p class="links"><a href="index.html">&larr; {u["back"]}</a></p>')
    return page(code, mod, p["title"], body, "privacy-policy.html")


REDIRECT = """<script>
(function () {{
  var have = {{"en":1,"fr":1,"de":1,"es":1,"it":1,"pt":1,"zh":"zh-Hans","ru":1,"ja":1,"ko":1,"hi":1,"ar":1}};
  var l = (navigator.language || "en").slice(0, 2).toLowerCase();
  if (have[l] && !location.hash && !/chooser/.test(location.search)) location.replace((typeof have[l] === "string" ? have[l] : l) + "/{page}");
}})();
</script>"""


def chooser(en, page_name, heading):
    links = "".join(f'<li><a href="{c}/{page_name}" hreflang="{c}">{n}</a></li>' for c, n in LANGS)
    return f"""<!DOCTYPE html>
<html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>{BRAND}</title>
<link rel="stylesheet" href="assets/style.css"></head>
<body><main class="wrap chooser"><h1>{BRAND}</h1><p class="lead">{heading}</p><ul class="langlist">{links}</ul></main>
{REDIRECT.format(page=page_name)}</body></html>
"""


def generate(base: Path, only=None):
    """Writes the whole site (language folders, chooser pages, assets, images) under `base`.
    All links are relative, so the same tree works at the root and inside v/<major.minor>/."""
    email = support_email()
    en = load("en")
    ref_g = shape(en.GUIDE)
    ref_p = [[b[0] for b in blocks] for _t, blocks in en.PRIVACY["sections"]]
    for code, _name in LANGS:
        if only and code not in only: continue
        mod = load(code)
        missing = [x for x in en.UI if x not in mod.UI]
        if missing: sys.exit(f"{code}: missing UI keys {missing}")
        if shape(mod.GUIDE) != ref_g: sys.exit(f"{code}: guide structure differs from English")
        if [[b[0] for b in blocks] for _t, blocks in mod.PRIVACY["sections"]] != ref_p: sys.exit(f"{code}: privacy policy structure differs from English")
        for (sid, _t, bl_en), (_s, _t2, bl) in zip(en.GUIDE, mod.GUIDE):
            for be, b in zip(bl_en, bl):
                if be[0] == "fig" and be[1] != b[1]: sys.exit(f"{code}: different image in {sid}")
                if be[0] in ("ul", "ol") and len(be[1]) != len(b[1]): sys.exit(f"{code}: {sid}: list length differs")
                if be[0] == "table" and (len(be[2]) != len(b[2]) or len(be[1]) != len(b[1])): sys.exit(f"{code}: {sid}: table shape differs")
        out = base / code; out.mkdir(parents=True, exist_ok=True)
        (out / "index.html").write_text(build_guide(code, mod, email))
        (out / "privacy-policy.html").write_text(build_privacy(code, mod, email))
    (base / "index.html").write_text(chooser(en, "index.html", en.UI["chooser_tagline"]))
    (base / "privacy-policy.html").write_text(chooser(en, "privacy-policy.html", en.UI["chooser_privacy"]))
    (base / ".nojekyll").write_text("")


def used_images():
    return sorted({b[1] for _s, _t, bl in load("en").GUIDE for b in bl if b[0] == "fig"})


def current_minor() -> str:
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import check_docs
    return ".".join(map(str, check_docs.minor(check_docs.ios_version())))


def snapshot(version: str, freeze: bool):
    """v/<major.minor>/ = a self-contained copy of the guide (its own assets and screenshots).
    Rebuilt freely while the version is in test; FROZEN (never rewritten) once published."""
    if not re.fullmatch(r"\d+\.\d+", version): sys.exit(f"snapshot version must be major.minor, got '{version}'")
    base = ROOT / "v" / version
    if (base / FROZEN).exists():
        print(f"v/{version} is frozen (published) — left untouched"); return
    if base.exists(): shutil.rmtree(base)
    base.mkdir(parents=True)
    generate(base)
    shutil.copytree(ROOT / "assets", base / "assets")
    (base / "images").mkdir()
    for name in used_images():
        shutil.copy2(ROOT / "images" / f"{name}.png", base / "images" / f"{name}.png")
    if freeze: (base / FROZEN).write_text("published\n")
    print(f"snapshot -> v/{version}" + (" (frozen)" if freeze else " (draft)"))


def versions_page():
    vs = sorted((p.name for p in (ROOT / "v").glob("*") if p.is_dir()), key=lambda v: tuple(map(int, v.split("."))), reverse=True)
    items = "".join(f'<li><a href="v/{v}/index.html">{BRAND} {v}</a>{"" if (ROOT / "v" / v / FROZEN).exists() else " (draft)"}</li>' for v in vs)
    (ROOT / "versions.html").write_text(f"""<!DOCTYPE html>
<html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>{BRAND} — versions</title>
<link rel="stylesheet" href="assets/style.css"></head>
<body><main class="wrap chooser"><h1>{BRAND}</h1><p class="lead">User guide by app version</p><ul class="langlist">{items}</ul><p><a href="index.html">Latest</a></p></main></body></html>
""")


def main():
    only = None
    if "--only" in sys.argv: only = sys.argv[sys.argv.index("--only") + 1].split(",")
    generate(ROOT, only)
    # Version snapshots: --snapshot [X.Y] (default: the current iOS major.minor), --freeze when the version is published.
    # A plain build also refreshes the current version's snapshot unless it is already frozen.
    freeze = "--freeze" in sys.argv
    if "--snapshot" in sys.argv:
        i = sys.argv.index("--snapshot")
        v = sys.argv[i + 1] if i + 1 < len(sys.argv) and not sys.argv[i + 1].startswith("--") else current_minor()
        snapshot(v, freeze)
    elif not only:
        snapshot(current_minor(), False)
    versions_page()
    print("site generated ->", ROOT)
    # Keep the guide in step with the builds: version line, screenshots present and dated (see check_docs.py).
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import check_docs
    if check_docs.check() != 0:
        sys.exit("guide check failed — fix the errors above (screenshots/manifest/version line/snapshot)")


main()
