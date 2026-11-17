#!/usr/bin/env python3
"""Regenerates every zh-Hant text derived from zh-Hans: the iOS catalogs and the guide (Documentation/site/zh-Hant.py).
The Android strings and the Play listing derive theirs when their own generators run (gen_android_strings.py, make_play_listing.py).
Run after changing any zh-Hans text or hant_convert.PHRASES (macOS + swiftc):  python3 Documentation/site/regen_hant.py"""
import ast, json, sys
from pathlib import Path
HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
sys.path.insert(0, str(HERE))
import hant_convert as h

for f in ("Localizable", "InfoPlist"):
    p = ROOT / f"PhotoVideoBackup/Resources/{f}.xcstrings"
    d = json.loads(p.read_text(encoding="utf-8"))
    refs = [(v["localizations"], v["localizations"]["zh-Hans"]["stringUnit"]["value"])
            for v in d["strings"].values() if "zh-Hans" in v.get("localizations", {})]
    for (loc, _), t in zip(refs, h.convert([t for _, t in refs])):
        loc["zh-Hant"] = {"stringUnit": {"state": "translated", "value": t}}
    p.write_text(json.dumps(d, indent=2, separators=(",", " : "), ensure_ascii=False) + "\n", encoding="utf-8")
    print(f, len(refs), "strings")
out = h.convert([(HERE / "zh.py").read_text(encoding="utf-8")], python_source=True)[0]
ast.parse(out)
(HERE / "zh-Hant.py").write_text(out, encoding="utf-8")
print("zh-Hant.py regenerated")
