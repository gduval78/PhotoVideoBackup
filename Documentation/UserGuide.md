# PhotoVideoBackup — User guide (source of truth)

The user guide and the privacy policy are **generated** in 8 languages (en, fr, de, es, it, pt, zh-Hans, ru) and cover the iPhone/iPad app and the Android app in one guide.

- Content: `Documentation/site/<lang>.py` (`en.py` is the reference; each file holds `UI`, `GUIDE` and `PRIVACY`).
- Build: `python3 Documentation/site/build_site.py` — refuses a language whose structure (sections, block kinds, list lengths, table shapes, images) differs from English or that lacks a UI key.
- Output (committed, served by GitHub Pages from `main` at `/`): `en/ fr/ de/ es/ it/ pt/ zh-Hans/ ru/`, `assets/style.css`, `index.html` and `privacy-policy.html` (language choosers that redirect on the browser language), `.nojekyll`. Screenshots live in `images/`.
- Button names in the guide are the app's own translations (`Localizable.xcstrings`).
- The previous English-only `index.md` is in git history (before commit "Documentation: 8-language guide").
