"""Make Pip's outfit variants: recoloured copies of his sprite sheets, so every player looks different.

    python tools/make_outfits.py

Reads assets/pip/pip-spritesheet.png and pip-weapons.png and writes assets/pip/outfits/<sheet>-<n>.png for outfits 1-3
(outfit 0 is the original sheet: the host). Every distinct colour on the sheets is sorted into a group by its colour:
skin and the dark outline stay as drawn; the tunic (tan), the trousers (olive), the scarf (lavender) and the hair
(orange-brown) are moved to each outfit's colours, keeping their light and shade (each colour's lightness relative to
its group is kept). Weapon metal and wood use the same browns and greys as the clothes in places, so the weapon sheet
is only recoloured where a colour is clearly clothing (tunic, trousers, scarf).
"""
import colorsys
import os
import numpy as np
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "pip")
OUT = os.path.join(ROOT, "outfits")

# group -> outfit -> (hue 0-1, saturation scale, value scale)
OUTFITS = {
    1: {"tunic": (0.60, 1.25, 0.92), "trousers": (0.62, 0.55, 0.62), "scarf": (0.12, 1.1, 1.0), "hair": (0.07, 0.75, 0.55)},   # blue tunic, gold scarf, dark hair
    2: {"tunic": (0.33, 0.85, 0.82), "trousers": (0.08, 0.5, 0.7), "scarf": (0.99, 1.2, 0.95), "hair": (0.0, 0.0, 0.32)},      # green ranger, red scarf, black hair
    3: {"tunic": (0.98, 1.1, 0.8), "trousers": (0.0, 0.0, 0.45), "scarf": (0.47, 1.0, 0.9), "hair": (0.13, 0.8, 1.25)},       # crimson tunic, teal scarf, blond
}


def group(rgb):
    r, g, b = [c / 255.0 for c in rgb]
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    hd = h * 360
    if v < 0.28:
        return None                      # outline and darkest shadows
    if 240 <= hd <= 275 and s > 0.15:
        return "scarf"                   # lavender / purple
    if 40 <= hd <= 75 and s < 0.35 and v < 0.62:
        return "trousers"                # olive greys
    if 30 <= hd <= 50 and 0.2 <= s <= 0.62 and v > 0.58:
        return "tunic"                   # tan cloth
    if 14 <= hd < 30 and s > 0.42 and v < 0.82:
        return "hair"                    # orange-brown hair
    return None                          # skin, highlights, everything else


def remap(rgb, spec):
    r, g, b = [c / 255.0 for c in rgb]
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    nh, ss, vs = spec
    nr, ng, nb = colorsys.hsv_to_rgb(nh, min(1.0, s * ss), min(1.0, v * vs))
    return (int(round(nr * 255)), int(round(ng * 255)), int(round(nb * 255)))


def make(sheet, clothing_only):
    im = Image.open(os.path.join(ROOT, sheet + ".png")).convert("RGBA")
    a = np.array(im)
    flat = a.reshape(-1, 4)
    opaque = flat[:, 3] > 0
    cols, inv = np.unique(flat[:, :3], axis=0, return_inverse=True)
    inv = inv.reshape(-1)
    groups = [group(tuple(int(x) for x in c)) for c in cols]
    for n, spec in OUTFITS.items():
        new_cols = cols.copy()
        for i, gname in enumerate(groups):
            if gname is None or (clothing_only and gname == "hair"):
                continue
            new_cols[i] = remap(tuple(int(x) for x in cols[i]), spec[gname])
        out = flat.copy()
        out[opaque, :3] = new_cols[inv[opaque]]
        os.makedirs(OUT, exist_ok=True)
        Image.fromarray(out.reshape(a.shape)).save(os.path.join(OUT, f"{sheet}-{n}.png"))
        print("wrote", f"outfits/{sheet}-{n}.png")


make("pip-spritesheet", False)
make("pip-weapons", False)
