#!/usr/bin/env python3
"""Renders Meno's app icon and writes Resources/AppIcon.icns.

Requires Pillow and numpy:  python3 -m pip install pillow numpy
"""
import io
import math
import struct
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SIZE = 1024
BODY = 824                      # squircle size inside the 1024 canvas
ORIGIN = (SIZE - BODY) // 2


def superellipse_mask(size, n=5.0, scale=1):
    """A continuous-corner squircle mask, rendered supersampled."""
    big = size * scale
    y, x = np.mgrid[0:big, 0:big]
    cx = cy = (big - 1) / 2
    r = big / 2
    v = np.abs((x - cx) / r) ** n + np.abs((y - cy) / r) ** n
    mask = (v <= 1).astype(np.uint8) * 255
    img = Image.fromarray(mask, "L")
    return img.resize((size, size), Image.LANCZOS) if scale > 1 else img


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def background(size):
    """Aurora gradient: periwinkle to violet with cyan and peach glows."""
    y, x = np.mgrid[0:size, 0:size] / (size - 1)
    t = np.clip((x * 0.55 + y * 0.45), 0, 1)[..., None]
    top = np.array([86, 104, 255], dtype=float)
    bottom = np.array([150, 70, 235], dtype=float)
    rgb = top * (1 - t) + bottom * t
    base = Image.fromarray(rgb.astype(np.uint8), "RGB").convert("RGBA")

    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(glow)
    d.ellipse([-160, 520, 520, 1180], fill=(40, 214, 226, 210))
    d.ellipse([520, -300, 1000, 200], fill=(255, 168, 120, 120))
    d.ellipse([260, 300, 820, 760], fill=(120, 150, 255, 90))
    glow = glow.filter(ImageFilter.GaussianBlur(120))
    return Image.alpha_composite(base, glow)


def rounded_mask(size, box, radius):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle(box, radius=radius, fill=255)
    return m


def glass(canvas, box, radius, tint=(255, 255, 255), strength=0.26):
    """Frosted glass: blurred backdrop, light fill, rim and top highlight."""
    w, h = canvas.size
    mask = rounded_mask((w, h), box, radius)

    # Shadow under the glass.
    shadow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [box[0] + 6, box[1] + 22, box[2] - 6, box[3] + 22], radius=radius, fill=(20, 10, 60, 110)
    )
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(26)))

    # Blurred, brightened backdrop.
    frosted = canvas.filter(ImageFilter.GaussianBlur(34))
    white = Image.new("RGBA", (w, h), tint + (255,))
    frosted = Image.blend(frosted, white, strength)
    canvas.paste(frosted, (0, 0), mask)

    # Top highlight.
    hl = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    hd = ImageDraw.Draw(hl)
    x0, y0, x1, y1 = box
    for i in range(int((y1 - y0) * 0.55)):
        a = int(70 * (1 - i / ((y1 - y0) * 0.55)) ** 2)
        hd.line([(x0, y0 + i), (x1, y0 + i)], fill=(255, 255, 255, a))
    canvas.alpha_composite(Image.composite(hl, Image.new("RGBA", (w, h), (0, 0, 0, 0)), mask))

    # Rim: bright at the top, fading towards the bottom.
    rim = Image.new("L", (w, h), 0)
    ImageDraw.Draw(rim).rounded_rectangle(box, radius=radius, outline=255, width=4)
    grad = Image.new("L", (w, h), 0)
    gd = ImageDraw.Draw(grad)
    for yy in range(y0, y1 + 1):
        t = (yy - y0) / max(y1 - y0, 1)
        gd.line([(0, yy), (w, yy)], fill=int(235 - 160 * t))
    rim = ImageChops.multiply(rim, grad)
    rim_layer = Image.new("RGBA", (w, h), (255, 255, 255, 0))
    rim_layer.putalpha(rim.filter(ImageFilter.GaussianBlur(0.8)))
    canvas.alpha_composite(rim_layer)


def bars(canvas, center, scale=1.0):
    """Meno's glyph: three rounded bars of increasing height."""
    cx, cy = center
    width = int(58 * scale)
    heights = [int(h * scale) for h in (118, 162, 206)]
    alphas = [150, 205, 255]
    gap = int(40 * scale)
    total = width * 3 + gap * 2
    x = cx - total // 2
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    sd = ImageDraw.Draw(shadow)
    for h, a in zip(heights, alphas):
        box = [x, cy - h // 2, x + width, cy + h // 2]
        sd.rounded_rectangle([box[0], box[1] + 10, box[2], box[3] + 10], radius=width // 2, fill=(30, 20, 90, 90))
        d.rounded_rectangle(box, radius=width // 2, fill=(255, 255, 255, a))
        x += width + gap
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(12)))
    canvas.alpha_composite(layer)


def dots(canvas, box, count=4):
    x0, y0, x1, y1 = box
    cy = (y0 + y1) // 2
    r = 17
    span = (x1 - x0) - 120
    d = ImageDraw.Draw(canvas)
    for i in range(count):
        cx = x0 + 60 + int(span * i / (count - 1))
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(255, 255, 255, 215 - i * 30))


def render():
    body = background(BODY)
    glass(body, (92, 238, BODY - 92, 488), radius=125)
    bars(body, (BODY // 2, 363))
    glass(body, (182, 566, BODY - 182, 660), radius=47, strength=0.2)
    dots(body, (182, 566, BODY - 182, 660))

    mask = superellipse_mask(BODY, scale=2)
    icon = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))

    drop = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    drop.paste(Image.new("RGBA", (BODY, BODY), (10, 6, 40, 120)), (ORIGIN, ORIGIN + 12), mask)
    icon.alpha_composite(drop.filter(ImageFilter.GaussianBlur(18)))

    shaped = Image.new("RGBA", (BODY, BODY), (0, 0, 0, 0))
    shaped.paste(body, (0, 0), mask)
    icon.alpha_composite(shaped, (ORIGIN, ORIGIN))

    # A hairline highlight around the edge of the squircle.
    edge = mask.filter(ImageFilter.FIND_EDGES).filter(ImageFilter.GaussianBlur(1))
    edge_layer = Image.new("RGBA", (BODY, BODY), (255, 255, 255, 0))
    edge_layer.putalpha(edge.point(lambda v: min(v, 110)))
    icon.alpha_composite(edge_layer, (ORIGIN, ORIGIN))
    return icon


def png_bytes(image, size):
    buffer = io.BytesIO()
    image.resize((size, size), Image.LANCZOS).save(buffer, format="PNG", optimize=True)
    return buffer.getvalue()


def write_icns(image, path):
    entries = [
        (b"icp4", 16), (b"icp5", 32), (b"icp6", 64), (b"ic07", 128), (b"ic08", 256),
        (b"ic09", 512), (b"ic10", 1024), (b"ic11", 32), (b"ic12", 64), (b"ic13", 256), (b"ic14", 512),
    ]
    chunks = b""
    for kind, size in entries:
        data = png_bytes(image, size)
        chunks += kind + struct.pack(">I", len(data) + 8) + data
    path.write_bytes(b"icns" + struct.pack(">I", len(chunks) + 8) + chunks)


if __name__ == "__main__":
    icon = render()
    write_icns(icon, ROOT / "Resources" / "AppIcon.icns")
    icon.resize((256, 256), Image.LANCZOS).save(ROOT / "docs" / "icon.png", optimize=True)
    print("Wrote Resources/AppIcon.icns and docs/icon.png")
