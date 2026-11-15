#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Builds the IslandPup brand art from the pixel-dog frames in Resources/DogFrames.

Writes two files next to this repo's other brand art (Resources/Brand):
  IslandPup-AppIcon.png  1024x1024 app icon: dog on a rounded-square tile
  IslandPup-Mark.png     1024x1024 white-on-transparent dog, used by MakeIcon.swift
                         for the menu bar template glyph and the in-app mark

Run again after changing the frame or colours:  python3 Tools/make-islandpup-icon.py
Needs Pillow (pip install pillow). The committed PNGs are what build.sh reads, so a
normal build does not need Python or Pillow.
"""
import os
import sys
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICON_FRAME = os.environ.get("ISLANDPUP_ICON_FRAME", "awake_0")    # app icon: sitting dog with a mug
MARK_FRAME = os.environ.get("ISLANDPUP_MARK_FRAME", "walk_0")     # menu bar glyph: plain profile, reads at 12 pt
OUT = os.path.join(ROOT, "Resources", "Brand")

CANVAS = 1024
TILE = 824                      # macOS icon grid: 100 px margin on a 1024 canvas
RADIUS = 186
TOP, BOTTOM = (126, 214, 235), (52, 128, 214)   # sky gradient


def load_frame(name):
    path = os.path.join(ROOT, "Resources", "DogFrames", name + ".png")
    img = Image.open(path).convert("RGBA")
    return img.crop(img.getchannel("A").getbbox())


def scaled(img, target):
    """Integer nearest-neighbour upscale so pixel art stays crisp."""
    factor = max(1, int(target // max(img.size)))
    return img.resize((img.width * factor, img.height * factor), Image.NEAREST)


def app_icon(dog):
    tile = Image.new("RGBA", (TILE, TILE))
    px = tile.load()
    for y in range(TILE):
        t = y / (TILE - 1)
        row = tuple(int(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3)) + (255,)
        for x in range(TILE):
            px[x, y] = row
    # soft highlight in the upper left
    glow = Image.new("RGBA", (TILE, TILE), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse((-TILE // 3, -TILE // 2, TILE, TILE // 2), fill=(255, 255, 255, 46))
    tile.alpha_composite(glow.filter(ImageFilter.GaussianBlur(60)))
    # the dog, centred and a little low so the mug sits on the tile
    big = scaled(dog, TILE * 0.86)
    tile.alpha_composite(big, ((TILE - big.width) // 2, (TILE - big.height) // 2 + 18))

    mask = Image.new("L", (TILE, TILE), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, TILE - 1, TILE - 1), RADIUS, fill=255)
    tile.putalpha(mask)

    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        ((CANVAS - TILE) // 2, (CANVAS - TILE) // 2 + 12, (CANVAS + TILE) // 2, (CANVAS + TILE) // 2 + 12),
        RADIUS, fill=(0, 0, 0, 90))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(14)))
    canvas.alpha_composite(tile, ((CANVAS - TILE) // 2, (CANVAS - TILE) // 2))
    return canvas


def mark(dog):
    """White silhouette; dark fur stays opaque, white fur turns translucent.

    macOS template images use alpha only, so this keeps eye, ear and chest
    detail readable at 12 pt instead of a solid blob.
    """
    px = dog.load()
    out = Image.new("RGBA", dog.size)
    op = out.load()
    for y in range(dog.height):
        for x in range(dog.width):
            r, g, b, a = px[x, y]
            luma = (0.299 * r + 0.587 * g + 0.114 * b) / 255
            op[x, y] = (255, 255, 255, int(a * (1.0 - 0.62 * luma)))
    big = scaled(out, CANVAS)
    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    canvas.alpha_composite(big, ((CANVAS - big.width) // 2, (CANVAS - big.height) // 2))
    return canvas


def main():
    app_icon(load_frame(ICON_FRAME)).save(os.path.join(OUT, "IslandPup-AppIcon.png"))
    mark(load_frame(MARK_FRAME)).save(os.path.join(OUT, "IslandPup-Mark.png"))
    print("wrote IslandPup-AppIcon.png (%s) and IslandPup-Mark.png (%s)" % (ICON_FRAME, MARK_FRAME))


if __name__ == "__main__":
    sys.exit(main())
