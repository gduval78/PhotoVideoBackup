#!/usr/bin/env python3
"""Android launcher icon + Play Store icon + feature graphic, derived from the iOS artwork.

The iOS icon (PhotoVideoBackup/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png) shows the vault AND an
iPhone; the Android assets use only the vault (a crop). Outputs:
  app/src/main/res/mipmap-xxxhdpi/ic_launcher_foreground.png   adaptive icon foreground (432 px, vault in the safe zone)
  app/src/main/res/values/ic_launcher_background.xml           adaptive icon background colour
  store/icon-512.png                                           Play Store icon
  store/feature-graphic-1024x500.png                           Play Store feature graphic
Run from the repo root:  python3 android/tools/make_icons.py
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "PhotoVideoBackup/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
RES = ROOT / "android/app/src/main/res"
STORE = ROOT / "android/store"
STORE.mkdir(exist_ok=True)

art = Image.open(SRC).convert("RGB")
crop = art.crop((125, 0, 885, 760))                         # the vault, without the phone

# Play Store icon: the square crop
crop.resize((512, 512), Image.LANCZOS).save(STORE / "icon-512.png")

# Background colour = the artwork's top edge
bg = crop.getpixel((20, 20))
(RES / "values").mkdir(parents=True, exist_ok=True)
(RES / "values/ic_launcher_background.xml").write_text(
    '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <color name="ic_launcher_background">#%02X%02X%02X</color>\n</resources>\n' % bg)

# Adaptive foreground: 108 dp = 432 px at xxxhdpi, the visible/safe zone is the central 66 % -> the vault at ~62 %
size, art_px = 432, 292
fg = Image.new("RGBA", (size, size), (0, 0, 0, 0))
tile = crop.resize((art_px, art_px), Image.LANCZOS).convert("RGBA")
mask = Image.new("L", (art_px, art_px), 0)
ImageDraw.Draw(mask).rounded_rectangle((10, 10, art_px - 10, art_px - 10), radius=40, fill=255)
mask = mask.filter(ImageFilter.GaussianBlur(14))           # feathered edge: the tile melts into the background colour
tile.putalpha(mask)
fg.paste(tile, ((size - art_px) // 2, (size - art_px) // 2), tile)
out = RES / "mipmap-xxxhdpi"; out.mkdir(parents=True, exist_ok=True)
fg.save(out / "ic_launcher_foreground.png")

# Feature graphic 1024x500
W, H = 1024, 500
g = Image.new("RGB", (W, H))
px = g.load()
top, bottom = (14, 27, 56), (44, 82, 140)
for y in range(H):
    t = y / (H - 1)
    for x in range(W):
        px[x, y] = tuple(int(top[i] + (bottom[i] - top[i]) * (0.6 * t + 0.4 * x / W)) for i in range(3))
vault = crop.resize((420, 420), Image.LANCZOS)
vm = Image.new("L", (420, 420), 0)
ImageDraw.Draw(vm).rounded_rectangle((6, 6, 414, 414), radius=60, fill=255)
vm = vm.filter(ImageFilter.GaussianBlur(10))
g.paste(vault, (W - 420 - 28, 40), vm)
d = ImageDraw.Draw(g)
def font(size, bold=True):
    for p, idx in (("/System/Library/Fonts/HelveticaNeue.ttc", 1 if bold else 0), ("/System/Library/Fonts/Helvetica.ttc", 1 if bold else 0)):
        try: return ImageFont.truetype(p, size, index=idx)
        except Exception: pass
    return ImageFont.load_default()
d.text((56, 140), "PhotoVideoBackup", font=font(54), fill="white")
d.text((58, 222), "Your photos and videos,", font=font(34, False), fill=(214, 226, 248))
d.text((58, 266), "safe on an SSD, SD card or NAS.", font=font(34, False), fill=(214, 226, 248))
d.rounded_rectangle((58, 340, 330, 392), radius=26, fill=(255, 255, 255))
d.text((84, 350), "SHA-256 verified", font=font(28), fill=(20, 40, 80))
g.save(STORE / "feature-graphic-1024x500.png")
print("ok", bg)
