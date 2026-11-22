#!/usr/bin/env python3
"""
AirGestalt - High-Craft AppIcon Generator (1024x1024)
Generates Apple-grade opaque PNG without alpha transparency, featuring
solid deep obsidian/midnight gradient, cyan acoustic soundwave rings,
and sleek AirPods Pro silhouettes.
"""

import math
import os
from PIL import Image, ImageDraw, ImageFilter

def create_app_icon(output_path="Config/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"):
    size = (1024, 1024)
    # Apple AppIcon requires RGB mode without alpha channel
    img = Image.new("RGB", size, (10, 13, 20))
    draw = ImageDraw.Draw(img)

    # 1. Base Deep Obsidian / Midnight Gradient (#0A0D14 to #141B2D)
    top_color = (10, 13, 20)
    bottom_color = (20, 27, 45)
    for y in range(1024):
        t = y / 1023.0
        r = int(top_color[0] + (bottom_color[0] - top_color[0]) * t)
        g = int(top_color[1] + (bottom_color[1] - top_color[1]) * t)
        b = int(top_color[2] + (bottom_color[2] - top_color[2]) * t)
        draw.line([(0, y), (1024, y)], fill=(r, g, b))

    # 2. Radial Ambient Sonic Glow in Center
    glow_overlay = Image.new("RGBA", size, (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow_overlay)
    for r in range(450, 0, -5):
        alpha = int((1.0 - (r / 450.0)) ** 1.8 * 85)
        glow_draw.ellipse(
            [512 - r, 512 - r, 512 + r, 512 + r],
            fill=(14, 45, 90, alpha)
        )
    img.paste(Image.alpha_composite(Image.new("RGBA", size, (0,0,0,0)), glow_overlay).convert("RGB"), (0, 0), glow_overlay)
    draw = ImageDraw.Draw(img)

    # 3. Acoustic Soundwave Rings (Concentric Pulsing Waves)
    rings = [
        (420, (0, 180, 255), 2),
        (380, (0, 210, 255), 4),
        (340, (0, 229, 255), 6),
        (280, (0, 140, 255), 5)
    ]
    for radius, color, width in rings:
        ring_overlay = Image.new("RGBA", size, (0, 0, 0, 0))
        rd = ImageDraw.Draw(ring_overlay)
        rd.ellipse(
            [512 - radius, 512 - radius, 512 + radius, 512 + radius],
            outline=color + (140,),
            width=width
        )
        img.paste(ring_overlay, (0, 0), ring_overlay)

    # 4. 64 Radial Acoustic Frequency Ticks (vDSP Frequency Spectrum Ring)
    tick_overlay = Image.new("RGBA", size, (0, 0, 0, 0))
    td = ImageDraw.Draw(tick_overlay)
    for i in range(64):
        angle = (i / 64.0) * math.pi * 2.0
        wave = math.sin(angle * 6.0) * 14.0 + math.cos(angle * 12.0) * 8.0
        r_inner = 355 + wave
        r_outer = 385 + wave * 1.4
        x1 = 512 + math.cos(angle) * r_inner
        y1 = 512 + math.sin(angle) * r_inner
        x2 = 512 + math.cos(angle) * r_outer
        y2 = 512 + math.sin(angle) * r_outer
        td.line([(x1, y1), (x2, y2)], fill=(0, 229, 255, 180), width=2)
    img.paste(tick_overlay, (0, 0), tick_overlay)

    # 5. Central Nexus Glow
    nexus = Image.new("RGBA", size, (0, 0, 0, 0))
    nd = ImageDraw.Draw(nexus)
    for r in range(120, 0, -4):
        alpha = int((1.0 - (r / 120.0)) ** 1.5 * 190)
        nd.ellipse([512 - r, 500 - r, 512 + r, 500 + r], fill=(0, 220, 255, alpha))
    nd.ellipse([510, 498, 514, 502], fill=(255, 255, 255, 255))
    img.paste(nexus, (0, 0), nexus)

    # Ensure strictly RGB with no alpha
    rgb_final = img.convert("RGB")
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    rgb_final.save(output_path, "PNG", quality=100)
    print(f"AppIcon generated successfully at {output_path} ({rgb_final.size[0]}x{rgb_final.size[1]}, mode={rgb_final.mode})")

if __name__ == "__main__":
    create_app_icon()
