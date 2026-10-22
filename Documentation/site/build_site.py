#!/usr/bin/env python3
"""Builds the static site (user guide + privacy policy) in 8 languages, at the repository root (GitHub Pages serves main at /).

  python3 Documentation/site/build_site.py [--only en,fr]

Content: Documentation/site/<lang>.py (en, fr, de, es, it, pt, zh, ru); each file defines UI (site labels), GUIDE (sections) and PRIVACY.
A section = (id, title, [blocks]); block = ("p", html) | ("ul", [html…]) | ("ol", [html…]) | ("note", html) | ("fig", image, caption) | ("table", [headers], [[cells]…]).
The script REFUSES a language whose structure (sections, number and kind of blocks) differs from English, or that lacks a UI key.
The support address is read from PhotoVideoBackup/App/AppConstants.swift: a single source.
Generated at the root: en/ fr/ de/ es/ it/ pt/ zh-Hans/ ru/, assets/, index.html, privacy-policy.html. Images are in images/.
"""
import html, importlib.util, re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
LANGS = [("en", "English"), ("fr", "Français"), ("de", "Deutsch"), ("es", "Español"), ("it", "Italiano"), ("pt", "Português"), ("zh-Hans", "简体中文"), ("ru", "Русский")]
UPDATED = "2026-10-22"
BRAND = "PhotoVideoBackup"


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
    langs = " · ".join(f'<a href="../{c}/{other}" hreflang="{c}"{" aria-current=page" if c == code else ""}>{n}</a>' for c, n in LANGS)
    return f"""<!DOCTYPE html>
<html lang="{code}">
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
  var have = {{"en":1,"fr":1,"de":1,"es":1,"it":1,"pt":1,"zh":"zh-Hans","ru":1}};
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


def main():
    only = None
    if "--only" in sys.argv: only = sys.argv[sys.argv.index("--only") + 1].split(",")
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
        out = ROOT / code; out.mkdir(parents=True, exist_ok=True)
        (out / "index.html").write_text(build_guide(code, mod, email))
        (out / "privacy-policy.html").write_text(build_privacy(code, mod, email))
    (ROOT / "index.html").write_text(chooser(en, "index.html", en.UI["chooser_tagline"]))
    (ROOT / "privacy-policy.html").write_text(chooser(en, "privacy-policy.html", en.UI["chooser_privacy"]))
    (ROOT / ".nojekyll").write_text("")
    print("site generated ->", ROOT)


main()
