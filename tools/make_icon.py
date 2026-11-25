"""The app icon: python tools/make_icon.py
A 32x32 pixel picture (the party in its circle, seen from above) scaled up
whole into icon.png and the Android adaptive layers icon_fg.png / icon_bg.png."""
import os
from PIL import Image

R = os.path.dirname(os.path.dirname(os.path.abspath(__file__))) + '/'
N = 32
BG = (0x1c, 0x1a, 0x19, 255)
SOUL = (0xbf, 0xf2, 0xff, 255)
UNITS = [  # cloth, head
    ((0x47, 0x6b, 0xad, 255), (0xb3, 0xb8, 0xc2, 255)),
    ((0xb8, 0x6b, 0x33, 255), (0x9e, 0x9e, 0xa8, 255)),
    ((0x4d, 0x8c, 0x47, 255), (0x38, 0x5c, 0x33, 255)),
    ((0x73, 0x4d, 0x9e, 255), (0x4d, 0x33, 0x6b, 255)),
]

px = {}


def put(x, y, c):
    if 0 <= x < N and 0 <= y < N:
        px[(x, y)] = c


def disc(cx, cy, r, c):
    for y in range(N):
        for x in range(N):
            if (x - cx) ** 2 + (y - cy) ** 2 <= r * r:
                put(x, y, c)


# the circle, its notch at the top
for i in range(360):
    import math
    a = math.radians(i)
    put(round(15.5 + math.cos(a) * 13), round(15.5 + math.sin(a) * 13), SOUL)
for y in range(0, 5):
    put(15, y, SOUL)
    put(16, y, SOUL)
# four of the party inside it
for (cx, cy), (cloth, head) in zip([(11, 11), (20, 11), (11, 20), (20, 20)], UNITS):
    disc(cx, cy, 3.6, cloth)
    disc(cx, cy - 1, 1.6, head)


def art(bg):
    im = Image.new('RGBA', (N, N), BG if bg else (0, 0, 0, 0))
    for (x, y), c in px.items():
        im.putpixel((x, y), c)
    return im


def scaled(size, k, bg):
    im = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    a = art(bg).resize((N * k, N * k), Image.NEAREST)
    o = (size - N * k) // 2
    im.alpha_composite(a, (o, o))
    return im


scaled(192, 6, True).save(R + 'icon.png')
scaled(432, 8, False).save(R + 'icon_fg.png')
Image.new('RGBA', (432, 432), BG).save(R + 'icon_bg.png')
