"""v0.13.0 Smiguel's peeking portrait (assets/smiguel/peek.png): a big pixel-art picture of him, an original design
(the same character as his costume, tools/make_costumes.py "smiguel"): a wiry old ranchero, weathered tan skin, wide
staring eyes under bushy grey brows, a black handlebar moustache over a toothy grin, wispy grey hair, a wide straw
sombrero with a zigzag trim, a rainbow serape with a fringe, his bony hands clasped at his chest. SmiguelView leans it
out from behind a tree or a pillar (tilted), and slides it back.

    python tools/make_smiguel_peek.py
"""
import os
from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "smiguel", "peek.png")
W, H = 96, 150
OUTLINE = (29, 22, 48, 255)
STRAW = [(236, 202, 136), (208, 168, 102), (176, 136, 78), (138, 102, 56)]
SKIN = [(222, 170, 122), (196, 142, 100), (166, 114, 80), (132, 88, 62)]
HAIR = [(222, 220, 222), (184, 182, 186), (146, 144, 150)]
STACHE = [(64, 56, 60), (40, 34, 38), (24, 20, 24)]
SERAPE = [(206, 44, 52), (236, 120, 40), (246, 204, 64), (64, 168, 80), (40, 120, 196), (126, 64, 170)]


def c(t):
    return tuple(t) + (255,) if len(t) == 3 else t


def main():
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    cx = 48
    # ---- the serape: a wide trapezoid from the shoulders down, in stripes (drawn first: the head goes over it)
    top, bot = 78, 146
    for y in range(top, bot):
        u = (y - top) / (bot - top)
        half = int(20 + 18 * u ** 0.7)
        band = SERAPE[((y - top) // 3) % len(SERAPE)]
        line = (y - top) % 9 == 8
        for x in range(cx - half, cx + half + 1):
            t = (x - (cx - half)) / (2 * half)
            k = 1.08 if t < 0.3 else (0.95 if t < 0.72 else 0.78)
            col = (60, 30, 40) if line else tuple(int(min(255, v * k)) for v in band)
            im.putpixel((x, y), c(col))
    for x in range(cx - 37, cx + 38, 2):   # the fringe
        for y in (bot, bot + 1, bot + 2):
            if y < H:
                im.putpixel((x, y), c((226, 200, 150) if y < bot + 2 else (190, 160, 110)))
    # a dark V of the neck opening
    for i in range(7):
        for x in range(cx - 6 + i, cx + 7 - i):
            im.putpixel((x, top + i), c(SKIN[2] if i < 3 else SKIN[3]))
    # ---- the hands clasped at his chest: bony fingers interlaced
    hy = 96
    d.ellipse([cx - 14, hy - 6, cx + 14, hy + 8], fill=c(SKIN[1]))
    for i in range(6):   # knuckles and finger lines
        x = cx - 11 + i * 4
        d.line([x, hy - 5, x + 1, hy + 6], fill=c(SKIN[3]))
        im.putpixel((x + 1, hy - 4), c(SKIN[0]))
    d.ellipse([cx - 17, hy - 2, cx - 9, hy + 9], fill=c(SKIN[2]))   # a thumb on each side
    d.ellipse([cx + 9, hy - 2, cx + 17, hy + 9], fill=c(SKIN[2]))
    # the arms in the serape's sleeves, coming in to the hands
    for side in (-1, 1):
        d.polygon([(cx + side * 26, 84), (cx + side * 34, 110), (cx + side * 16, hy + 6), (cx + side * 12, hy - 4)], fill=c(SERAPE[4] if side < 0 else SERAPE[0]))
    # ---- the head: long and gaunt-cheeked but human, big ears, a long nose
    hx0, hx1, hy0, hy1 = cx - 15, cx + 15, 34, 78
    d.ellipse([hx0, hy0, hx1, hy1], fill=c(SKIN[1]))
    d.ellipse([hx0 + 3, hy0 + 2, hx1 - 8, hy1 - 10], fill=c(SKIN[0]))   # the lit side
    d.ellipse([hx0 - 5, 50, hx0 + 3, 62], fill=c(SKIN[2]))   # ears
    d.ellipse([hx1 - 3, 50, hx1 + 5, 62], fill=c(SKIN[2]))
    # wrinkles across the brow
    for y in (44, 47):
        d.line([cx - 8, y, cx + 8, y], fill=c(SKIN[2]))
    # bushy grey brows, raised
    d.line([cx - 15, 44, cx - 3, 41], fill=c(HAIR[0]), width=2)
    d.line([cx + 3, 41, cx + 15, 44], fill=c(HAIR[0]), width=2)
    # wide staring eyes: whites, dark pupils looking at you, a glint
    # big googly eyes (like the prize fiesta's): huge whites bulging past his face, small pupils rolled off-centre,
    # each a different way
    for ex, (px_, py_) in ((cx - 8, (-2, 1)), (cx + 8, (3, -2))):
        d.ellipse([ex - 8, 45, ex + 8, 62], fill=c(OUTLINE[:3]))
        d.ellipse([ex - 7, 46, ex + 7, 61], fill=c((250, 248, 240)))
        d.ellipse([ex - 6, 47, ex + 2, 52], fill=c((255, 255, 255)))
        d.ellipse([ex + px_ - 3, 52 + py_ - 3, ex + px_ + 3, 52 + py_ + 3], fill=c((24, 20, 22)))
        im.putpixel((ex + px_ - 1, 52 + py_ - 2), c((255, 255, 255)))
    # the nose
    d.polygon([(cx - 1, 56), (cx + 3, 66), (cx - 3, 66)], fill=c(SKIN[2]))
    im.putpixel((cx - 2, 66), c(SKIN[3]))
    im.putpixel((cx + 2, 66), c(SKIN[3]))
    # the grin with a few teeth
    d.chord([cx - 9, 66, cx + 9, 76], 0, 180, fill=c((70, 30, 34)))
    for tx in (cx - 5, cx - 1, cx + 3):
        d.rectangle([tx, 71, tx + 2, 73], fill=c((236, 226, 196)))
    # the handlebar moustache: thick over the lip, sweeping out and curling up
    d.ellipse([cx - 11, 65, cx + 11, 71], fill=c(STACHE[1]))
    for side in (-1, 1):
        pts = [(cx + side * 10, 68), (cx + side * 16, 68), (cx + side * 19, 65), (cx + side * 19, 62), (cx + side * 17, 61)]
        d.line(pts, fill=c(STACHE[1]), width=3)
        im.putpixel((cx + side * 17, 61), c(STACHE[0]))
    # wispy grey hair poking out at the sides under the hat
    for side in (-1, 1):
        for i in range(5):
            x = cx + side * (13 + i)
            d.line([x, 38 + i, x + side * 2, 50 + i * 2], fill=c(HAIR[1] if i % 2 else HAIR[0]))
    # ---- the sombrero: a wide brim (an ellipse seen from a little above, upturned edges) and a tall round crown
    d.ellipse([cx - 46, 28, cx + 46, 44], fill=c(STRAW[1]))
    d.ellipse([cx - 44, 28, cx + 44, 39], fill=c(STRAW[0]))
    for side in (-1, 1):   # upturned edges
        d.ellipse([cx + side * 40 - 6, 26, cx + side * 40 + 6, 36], fill=c(STRAW[1]))
    for x in range(cx - 44, cx + 45):   # the woven zigzag trim along the rim
        y = 40 + ((x // 3) % 2)
        im.putpixel((x, y), c(STRAW[3]))
    d.ellipse([cx - 17, 2, cx + 17, 40], fill=c(STRAW[1]))   # the crown
    d.ellipse([cx - 15, 3, cx + 5, 36], fill=c(STRAW[0]))
    d.line([cx, 3, cx, 14], fill=c(STRAW[3]))   # the dent
    for x in range(cx - 16, cx + 17):   # its zigzag band
        for y in (28, 29, 30, 31):
            zz = ((x + y) % 6) < 3
            im.putpixel((x, y), c((206, 44, 52) if zz else (40, 120, 196)) if y in (29, 30) else c(STRAW[3]))
    # ---- the outline round everything
    src = im.copy()
    px = src.load()
    out = im.load()
    for y in range(H):
        for x in range(W):
            if px[x, y][3] == 0 and any(0 <= x + dx < W and 0 <= y + dy < H and px[x + dx, y + dy][3] > 0
                                        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                out[x, y] = OUTLINE
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    im.save(OUT)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
