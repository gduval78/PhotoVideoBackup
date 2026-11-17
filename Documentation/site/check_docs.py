#!/usr/bin/env python3
"""Keeps the user guide in step with the app builds.

  python3 Documentation/site/check_docs.py [--strict]

What it checks (build_site.py runs it after generating the site):

1. VERSION LINE — every language's UI["version_line"] names the current major.minor of the iOS app
   (MARKETING_VERSION in the Xcode project) and of the Android app (appVersion in
   android/app/build.gradle.kts). A guide that says "2.6" while the app is 2.7 is an ERROR.
2. SCREENSHOTS EXIST — every ("fig", name, …) block of the English guide has images/<name>.png. ERROR if missing.
3. SCREENSHOTS ARE DATED — images/manifest.json records, for each screenshot, the app version it is accurate
   for ("version") and what it shows ("note"). A screenshot with no entry is an ERROR; one whose version is
   older than the current major.minor of its platform ("android_*" = Android, everything else = iOS) is
   STALE: a WARNING (an ERROR with --strict). Retake it, or — if the screen did not change — bump its
   "version" after looking at it. Never bump a version without having looked at the screen.
4. SNAPSHOT — v/<major.minor>/ of the current iOS version exists with its screenshots (the apps link to it).
5. ORPHANS — images/*.png used by no guide are listed (information only).

Exit code 1 on any ERROR (or STALE with --strict).
"""
import importlib.util, json, re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
SITE = Path(__file__).resolve().parent
LANGS = ["en", "fr", "de", "es", "it", "pt", "zh", "zh-Hant", "ru", "ja", "ko", "hi", "ar"]


def load(code):
    spec = importlib.util.spec_from_file_location(f"chk_{code}", SITE / f"{code}.py")
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
    return m


def ios_version():
    s = (ROOT / "PhotoVideoBackup.xcodeproj/project.pbxproj").read_text()
    return sorted(set(re.findall(r"MARKETING_VERSION = ([0-9.]+);", s)))[-1]


def android_version():
    s = (ROOT / "android/app/build.gradle.kts").read_text()
    return re.search(r'val appVersion\s*=\s*"([0-9.]+)"', s).group(1)


def minor(v):
    p = v.split(".")
    return (int(p[0]), int(p[1]))


def platform(image):
    return "android" if image.startswith("android_") else "ios"


def check(strict=False):
    errors, stale, info = [], [], []
    current = {"ios": ios_version(), "android": android_version()}

    # 1. version line
    for code in LANGS:
        line = load(code).UI["version_line"]
        nums = re.findall(r"\b\d+\.\d+\b", line)
        want = ".".join(map(str, minor(current["ios"])))
        if want not in nums:
            errors.append(f"{code}: version_line says {nums or 'no version'}, the iOS app is {current['ios']}")

    # 2 + 3. screenshots
    figs = []
    for _sid, _title, blocks in load("en").GUIDE:
        figs += [b[1] for b in blocks if b[0] == "fig"]
    manifest_path = ROOT / "images/manifest.json"
    manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {}
    for name in dict.fromkeys(figs):
        if not (ROOT / "images" / f"{name}.png").exists():
            errors.append(f"images/{name}.png is used by the guide but does not exist")
            continue
        entry = manifest.get(name)
        if not entry:
            errors.append(f"images/manifest.json has no entry for '{name}'")
            continue
        p = platform(name)
        if minor(entry["version"]) < minor(current[p]):
            stale.append(f"'{name}' is accurate for {p} {entry['version']}, the app is {current[p]} — {entry.get('note', '')}".rstrip(" —"))

    # 3b. version snapshot: the apps link to v/<major.minor>/, so it must exist and be complete
    snap = ROOT / "v" / ".".join(map(str, minor(current["ios"])))
    if not (snap / "index.html").exists():
        errors.append(f"{snap.relative_to(ROOT)}/ is missing — run build_site.py (the apps link to it)")
    else:
        for name in dict.fromkeys(figs):
            if not (snap / "images" / f"{name}.png").exists():
                errors.append(f"{snap.relative_to(ROOT)}/images/{name}.png is missing from the snapshot")

    # 4. orphans
    used = set(figs)
    for f in sorted((ROOT / "images").glob("*.png")):
        if f.stem not in used:
            info.append(f.name)

    print(f"Guide check — iOS {current['ios']}, Android {current['android']}")
    for e in errors: print("  ERROR ", e)
    for s in stale:  print("  STALE ", s)
    if info: print(f"  info   {len(info)} unused image(s): " + ", ".join(info))
    if not errors and not stale: print("  OK     guide and screenshots match the builds")
    return 1 if errors or (strict and stale) else 0


if __name__ == "__main__":
    sys.exit(check("--strict" in sys.argv))
