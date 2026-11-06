"""Contact sheet of Pip carrying each weapon in every direction (v0.8.2), placed by the same rules as the game
(scripts/avatar.gd, _update_prop): which hand (the one on screen-left facing us, S and SE; the right one otherwise),
two pixels out from his middle, mirrored views (SW, W, NW) flipped, the weapon pointing out from the hand, drawn in
front. Rows: the 8 directions; columns: idle, walk (4 frames), run (3), dash, in the air.

    python tools/carry_sheet.py <out folder>     -> carry_<weapon>.png, 4x, nearest-neighbour
"""
import json
import os
import sys
from PIL import Image, ImageDraw

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "pip")
CELL = 64
ANCHOR_X = 32
DIRS = ["S", "SE", "E", "NE", "N", "NW", "W", "SW"]
MIRROR = {"SW": "SE", "W": "E", "NW": "NE"}
COLS = [("idle", 0), ("walk", 0), ("walk", 1), ("walk", 2), ("walk", 3), ("run", 0), ("run", 2), ("run", 4), ("dash", 2), ("air", 0)]


def main(out):
    meta = json.load(open(os.path.join(ROOT, "pip-spritesheet.json")))
    rowof = {(a["name"], a["dir"]): (a["row"], a["frames"]) for a in meta["animations"]}
    hands = json.load(open(os.path.join(ROOT, "garb", "pip-hands.json")))["pip-spritesheet"]
    carry = json.load(open(os.path.join(ROOT, "carry", "carry.json")))
    sheets = {"plain": Image.open(os.path.join(ROOT, "pip-spritesheet.png")).convert("RGBA"),
              "wizard": Image.open(os.path.join(ROOT, "garb", "pip-spritesheet-wizard.png")).convert("RGBA"),
              "shadow": Image.open(os.path.join(ROOT, "garb", "pip-spritesheet-shadow.png")).convert("RGBA")}
    for weapon in ["sword", "club", "bow", "sling", "staff", "wand"]:
        look = "wizard" if weapon == "staff" else ("shadow" if weapon == "wand" else "plain")
        z = 4
        H = CELL + 12
        S = Image.new("RGBA", (len(COLS) * CELL * z, len(DIRS) * H * z), (90, 140, 110, 255))
        m = carry[weapon]
        img = Image.open(os.path.join(ROOT, "carry", weapon + ".png")).convert("RGBA")
        img_m = Image.open(os.path.join(ROOT, "carry", weapon + "-m.png")).convert("RGBA")
        for r, d in enumerate(DIRS):
            cd = MIRROR.get(d, d)
            mirror_view = d in MIRROR
            for c, (anim, f) in enumerate(COLS):
                row, frames = rowof[(anim, cd)]
                f = min(f, frames - 1)
                cell = sheets[look].crop((f * CELL, row * CELL, f * CELL + CELL, row * CELL + CELL))
                hv = hands.get("%d:%d" % (row, f), [-1, -1, -1, -1])
                use_left = cd in ("S", "SE")
                hx, hy = (hv[0], hv[1]) if use_left else (hv[2], hv[3])
                if hx < 0:
                    hx, hy = ANCHOR_X + (-8 if use_left else 8), 58 - 14
                hx += 2 if hx >= ANCHOR_X else -2
                if cd == "E":
                    hx = max(hx, ANCHOR_X) + 5
                if mirror_view:
                    cell = cell.transpose(Image.FLIP_LEFT_RIGHT)
                    hx = CELL - 1 - hx
                mirror_img = use_left != mirror_view
                gx, gy = m["grip"]
                if mirror_img:
                    gx = m["size"][0] - 1 - gx
                canvas = Image.new("RGBA", (CELL, CELL + 40), (0, 0, 0, 0))
                canvas.alpha_composite(cell, (0, 20))
                canvas.alpha_composite(img_m if mirror_img else img, (int(hx - gx), int(hy - gy + 20)))
                big = canvas.resize((CELL * z, (CELL + 40) * z), Image.NEAREST).crop((0, 8 * z, CELL * z, (8 + H) * z))
                S.alpha_composite(big, (c * CELL * z, r * H * z))
            ImageDraw.Draw(S).text((4, r * H * z + 4), d, fill=(255, 255, 0, 255))
        S.save(os.path.join(out, "carry_%s.png" % weapon))
        print("wrote", "carry_%s.png" % weapon)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else ".")
