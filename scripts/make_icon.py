"""Renders the Anilite app icon (1024x1024 PNG) and asset catalog JSON.

Run: python scripts/make_icon.py
"""
import json
import math
import os
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "App", "Resources", "Assets.xcassets")
S = 2048  # supersampled canvas

VERMILION = (255, 90, 120)
CYAN = (111, 227, 255)
VIOLET = (140, 108, 242)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def background():
    img = Image.new("RGB", (S, S), (6, 6, 11))
    px = img.load()
    cx, cy = S * 0.5, S * 0.32
    for y in range(0, S, 2):
        for x in range(0, S, 2):
            d = math.hypot((x - cx) / S, (y - cy) / S)
            t = max(0.0, 1.0 - d * 1.55)
            c = lerp((6, 6, 11), (38, 26, 64), t ** 1.8)
            px[x, y] = c
            if x + 1 < S: px[x + 1, y] = c
            if y + 1 < S:
                px[x, y + 1] = c
                if x + 1 < S: px[x + 1, y + 1] = c
    return img


def ring_layer(width, alpha=255):
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx, cy, r = S * 0.5, S * 0.53, S * 0.30
    start, sweep = 120.0, 290.0
    steps = 600
    for i in range(steps):
        t = i / steps
        a0 = math.radians(start + sweep * t)
        a1 = math.radians(start + sweep * (t + 1.0 / steps) + 0.2)
        col = lerp(VERMILION, VIOLET, t * 2) if t < 0.5 else lerp(VIOLET, CYAN, (t - 0.5) * 2)
        # Taper the tail so the ring reads as motion.
        w = width * (0.35 + 0.65 * min(1.0, t * 3))
        bbox = [cx - r, cy - r, cx + r, cy + r]
        d.arc(bbox, math.degrees(a0), math.degrees(a1), fill=col + (alpha,), width=int(w))
    # Moon at the head of the ring.
    a = math.radians(start + sweep)
    mx, my = cx + r * math.cos(a), cy + r * math.sin(a)
    mr = width * 0.95
    d.ellipse([mx - mr, my - mr, mx + mr, my + mr], fill=(235, 250, 255, alpha))
    return layer


def sparkle(draw, x, y, size, color):
    pts = []
    for k in range(8):
        ang = math.pi / 4 * k
        rad = size if k % 2 == 0 else size * 0.18
        pts.append((x + rad * math.cos(ang), y + rad * math.sin(ang)))
    draw.polygon(pts, fill=color)


def main():
    img = background().convert("RGBA")
    glow = ring_layer(170, 210).filter(ImageFilter.GaussianBlur(90))
    img = Image.alpha_composite(img, glow)
    img = Image.alpha_composite(img, ring_layer(118))
    stars = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sd = ImageDraw.Draw(stars)
    sparkle(sd, S * 0.50, S * 0.53, S * 0.075, (255, 255, 255, 255))
    sparkle(sd, S * 0.73, S * 0.25, S * 0.03, (255, 220, 230, 230))
    sparkle(sd, S * 0.25, S * 0.80, S * 0.022, (200, 240, 255, 210))
    img = Image.alpha_composite(img, stars.filter(ImageFilter.GaussianBlur(14)))
    img = Image.alpha_composite(img, stars)
    icon = img.convert("RGB").resize((1024, 1024), Image.LANCZOS)

    appicon = os.path.join(ASSETS, "AppIcon.appiconset")
    os.makedirs(appicon, exist_ok=True)
    icon.save(os.path.join(appicon, "AppIcon-1024.png"), optimize=True)
    with open(os.path.join(appicon, "Contents.json"), "w") as f:
        json.dump({"images": [{"filename": "AppIcon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
                   "info": {"author": "xcode", "version": 1}}, f, indent=2)
    with open(os.path.join(ASSETS, "Contents.json"), "w") as f:
        json.dump({"info": {"author": "xcode", "version": 1}}, f, indent=2)

    def color_set(name, r, g, b):
        path = os.path.join(ASSETS, name + ".colorset")
        os.makedirs(path, exist_ok=True)
        with open(os.path.join(path, "Contents.json"), "w") as f:
            json.dump({"colors": [{"idiom": "universal", "color": {"color-space": "srgb", "components": {
                "red": f"{r / 255:.3f}", "green": f"{g / 255:.3f}", "blue": f"{b / 255:.3f}", "alpha": "1.000"}}}],
                "info": {"author": "xcode", "version": 1}}, f, indent=2)

    color_set("AccentColor", *VERMILION)
    color_set("LaunchBackground", 7, 7, 12)
    print("icon written")


if __name__ == "__main__":
    main()
