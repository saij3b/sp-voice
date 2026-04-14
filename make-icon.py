#!/usr/bin/env python3
"""Generate SPVoice app icon matching the in-app waveform branding.

macOS Big Sur+ style: squircle gradient background + white waveform glyph.
Gradient matches DS.Gradients.listen (violet -> magenta).
"""
import math
import os
import subprocess
import sys
from PIL import Image, ImageDraw, ImageFilter

# DS.Gradients.listen: (0.55, 0.40, 1.00) -> (0.87, 0.35, 0.95)
COLOR_FROM = (140, 102, 255)
COLOR_TO   = (222,  89, 242)

OUT_DIR = "/tmp/sp-voice/SPVoice.iconset"
ICNS_OUT = "/tmp/sp-voice/SPVoice/SPVoice/Resources/SPVoice.icns"


def render_icon(size: int) -> Image.Image:
    # Full-bleed: macOS Big Sur squircle is 824/1024 of full frame,
    # but we'll fill the image (macOS adds shadow/inset automatically at display time).
    # We use the standard full-canvas approach: inset ~10% margin, squircle corners.
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Gradient fill (top-left -> bottom-right)
    grad = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    g = ImageDraw.Draw(grad)
    for y in range(size):
        for x in range(size):
            # diagonal t in [0,1]
            t = (x + y) / (2 * (size - 1) + 1e-9)
            r = int(COLOR_FROM[0] + (COLOR_TO[0] - COLOR_FROM[0]) * t)
            gg = int(COLOR_FROM[1] + (COLOR_TO[1] - COLOR_FROM[1]) * t)
            b = int(COLOR_FROM[2] + (COLOR_TO[2] - COLOR_FROM[2]) * t)
            g.point((x, y), fill=(r, gg, b, 255))

    # Squircle mask with margin
    margin = int(size * 0.095)       # 9.5% outer inset, matches macOS icon template
    inner = size - 2 * margin
    corner = int(inner * 0.225)      # ~22.5% corner radius
    mask = Image.new("L", (size, size), 0)
    mdraw = ImageDraw.Draw(mask)
    mdraw.rounded_rectangle(
        (margin, margin, size - margin, size - margin),
        radius=corner, fill=255
    )

    # Composite gradient under mask
    icon = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    icon.paste(grad, (0, 0), mask)

    # Inner highlight (top sheen)
    sheen = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sdraw = ImageDraw.Draw(sheen)
    for yy in range(margin, margin + int(inner * 0.45)):
        alpha = int(90 * (1 - (yy - margin) / (inner * 0.45)))
        sdraw.line([(margin, yy), (size - margin, yy)], fill=(255, 255, 255, max(alpha, 0)))
    sheen_masked = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sheen_masked.paste(sheen, (0, 0), mask)
    icon = Image.alpha_composite(icon, sheen_masked)

    # Waveform: 5 rounded-rect vertical bars, centered.
    # Kept compact so the glyph reads at the same weight as the in-app
    # sidebar brand badge (SF Symbol "waveform" inside a 32pt tile).
    cx = size // 2
    cy = size // 2
    bar_count = 5
    bar_spacing = inner * 0.075
    bar_width = inner * 0.055
    # heights form a "hill": shorter, taller, tallest, taller, shorter
    heights_ratio = [0.22, 0.34, 0.44, 0.34, 0.22]
    total_width = bar_count * bar_width + (bar_count - 1) * bar_spacing
    start_x = cx - total_width / 2
    bdraw = ImageDraw.Draw(icon)
    for i in range(bar_count):
        h = inner * heights_ratio[i]
        x0 = start_x + i * (bar_width + bar_spacing)
        y0 = cy - h / 2
        x1 = x0 + bar_width
        y1 = cy + h / 2
        r = bar_width / 2
        bdraw.rounded_rectangle((x0, y0, x1, y1), radius=r, fill=(255, 255, 255, 255))

    # Subtle drop-shadow under bars (inner shadow for depth)
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sdraw2 = ImageDraw.Draw(shadow)
    for i in range(bar_count):
        h = inner * heights_ratio[i]
        x0 = start_x + i * (bar_width + bar_spacing) + 1
        y0 = cy - h / 2 + 2
        x1 = x0 + bar_width
        y1 = cy + h / 2 + 2
        r = bar_width / 2
        sdraw2.rounded_rectangle((x0, y0, x1, y1), radius=r, fill=(0, 0, 0, 60))
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=max(1, size / 256)))
    shadow_masked = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    shadow_masked.paste(shadow, (0, 0), mask)
    # composite: shadow under bars — redraw bars on top
    final = Image.alpha_composite(shadow_masked, icon)
    return final


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    # Apple iconset required sizes
    sizes = [
        (16,   "icon_16x16.png"),
        (32,   "icon_16x16@2x.png"),
        (32,   "icon_32x32.png"),
        (64,   "icon_32x32@2x.png"),
        (128,  "icon_128x128.png"),
        (256,  "icon_128x128@2x.png"),
        (256,  "icon_256x256.png"),
        (512,  "icon_256x256@2x.png"),
        (512,  "icon_512x512.png"),
        (1024, "icon_512x512@2x.png"),
    ]
    # Render only unique sizes, then copy/rename
    cache = {}
    for size, name in sizes:
        if size not in cache:
            cache[size] = render_icon(size)
        cache[size].save(os.path.join(OUT_DIR, name))
        print(f"wrote {name} ({size}x{size})")

    # Build icns
    subprocess.check_call(["iconutil", "-c", "icns", OUT_DIR, "-o", ICNS_OUT])
    print(f"wrote {ICNS_OUT}")


if __name__ == "__main__":
    main()
