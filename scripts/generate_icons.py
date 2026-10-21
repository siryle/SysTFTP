#!/usr/bin/env python3
"""
Generate macOS App Icons and Iconset for SysTFTP.
Renders high-resolution 1024x1024 master icon and full Apple asset catalog sizes.
"""

import os
import math
import json
from PIL import Image, ImageDraw, ImageFilter, ImageFont

def create_master_icon(size=1024):
    # Supersampling 2x for ultra crisp antialiasing
    scale = 2
    W = size * scale
    H = size * scale

    # Base image with transparent background
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))

    # Squircle geometry (macOS icon standard: ~824px wide on 1024 canvas, corner radius ~185px)
    pad = int(96 * scale)
    box_w = W - 2 * pad
    box_h = H - 2 * pad
    radius = int(190 * scale)

    # 1. Soft Shadow
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    s_draw = ImageDraw.Draw(shadow)
    s_offset_y = int(24 * scale)
    s_draw.rounded_rectangle(
        [pad, pad + s_offset_y, pad + box_w, pad + box_h + s_offset_y],
        radius=radius,
        fill=(5, 12, 28, 140)
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(int(28 * scale)))
    img.alpha_composite(shadow)

    # Second tighter shadow for depth
    tight_shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ts_draw = ImageDraw.Draw(tight_shadow)
    ts_offset_y = int(12 * scale)
    ts_draw.rounded_rectangle(
        [pad, pad + ts_offset_y, pad + box_w, pad + box_h + ts_offset_y],
        radius=radius,
        fill=(2, 6, 18, 110)
    )
    tight_shadow = tight_shadow.filter(ImageFilter.GaussianBlur(int(12 * scale)))
    img.alpha_composite(tight_shadow)

    # 2. Main Icon Body with Mask
    mask = Image.new("L", (W, H), 0)
    m_draw = ImageDraw.Draw(mask)
    m_draw.rounded_rectangle([pad, pad, pad + box_w, pad + box_h], radius=radius, fill=255)

    body = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    b_draw = ImageDraw.Draw(body)

    # Gradient Background: Deep Space Navy (#0B132B) -> Deep Cobalt (#1C2B4E) -> Cyber Blue (#0284C7)
    for y in range(pad, pad + box_h):
        t = (y - pad) / box_h
        # Non-linear curve for sleek dark top to glowing bottom
        r = int(11 * (1 - t) + 10 * t * 0.4 + 2 * (t**1.8))
        g = int(19 * (1 - t) + 45 * t * 0.6 + 132 * (t**1.6))
        b = int(43 * (1 - t) + 110 * t * 0.7 + 215 * (t**1.4))
        b_draw.line([(pad, y), (pad + box_w, y)], fill=(r, g, b, 255))

    # Radial ambient center glow
    cx, cy = W // 2, H // 2
    ambient = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    a_draw = ImageDraw.Draw(ambient)
    max_r = int(380 * scale)
    for r in range(max_r, 0, -int(4 * scale)):
        ratio = r / max_r
        alpha = int((1.0 - ratio)**1.5 * 80)
        a_draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(56, 189, 248, alpha))
    body.alpha_composite(ambient)

    # Telemetry Matrix / Grid lines (Network Engineering aesthetic)
    grid_img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    g_draw = ImageDraw.Draw(grid_img)
    step = int(64 * scale)
    for x in range(pad, pad + box_w, step):
        g_draw.line([(x, pad), (x, pad + box_h)], fill=(255, 255, 255, 10), width=scale)
    for y in range(pad, pad + box_h, step):
        g_draw.line([(pad, y), (pad + box_w, y)], fill=(255, 255, 255, 10), width=scale)
    body.alpha_composite(grid_img)

    # 3. Syslog Concentric Radar Telemetry Rings
    radar = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    r_draw = ImageDraw.Draw(radar)
    radii = [int(320 * scale), int(240 * scale), int(160 * scale)]
    alphas = [40, 65, 95]
    for rad, al in zip(radii, alphas):
        r_draw.ellipse([cx - rad, cy - rad, cx + rad, cy + rad], outline=(56, 189, 248, al), width=int(2.5 * scale))

    # Telemetry pulse nodes (Syslog event points)
    pulse_nodes = [
        (cx + int(170 * scale), cy - int(130 * scale), (52, 211, 153, 230)), # Green
        (cx - int(140 * scale), cy + int(110 * scale), (56, 189, 248, 230)), # Cyan
        (cx + int(110 * scale), cy + int(140 * scale), (245, 158, 11, 230)), # Amber
        (cx - int(120 * scale), cy - int(120 * scale), (167, 139, 250, 230)), # Violet
    ]
    for px, py, color in pulse_nodes:
        # Glow
        nr = int(14 * scale)
        r_draw.ellipse([px - nr, py - nr, px + nr, py + nr], fill=(color[0], color[1], color[2], 60))
        cr = int(6 * scale)
        r_draw.ellipse([px - cr, py - cr, px + cr, py + cr], fill=color)

    body.alpha_composite(radar)

    # 4. Central Hexagonal Gateway / Router Emblem Shield
    hex_img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    h_draw = ImageDraw.Draw(hex_img)
    
    hex_r = int(240 * scale)
    points = []
    for i in range(6):
        angle = math.radians(60 * i - 30)
        px = cx + hex_r * math.cos(angle)
        py = cy + hex_r * math.sin(angle)
        points.append((px, py))
    
    # Shield background
    h_draw.polygon(points, fill=(11, 19, 43, 220), outline=(56, 189, 248, 180), width=int(4 * scale))
    
    # Inner border
    inner_points = []
    for i in range(6):
        angle = math.radians(60 * i - 30)
        px = cx + (hex_r - int(18 * scale)) * math.cos(angle)
        py = cy + (hex_r - int(18 * scale)) * math.sin(angle)
        inner_points.append((px, py))
    h_draw.polygon(inner_points, outline=(56, 189, 248, 50), width=int(1.5 * scale))

    body.alpha_composite(hex_img)

    # 5. High-Speed Bidirectional Transmission Arrows (TFTP & FTP)
    arrow_img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    arr_draw = ImageDraw.Draw(arrow_img)

    # Upward Arrow: Upload (Electric Cyan / Light Sky)
    # Arrow apex at (cx - 70*scale, cy - 130*scale)
    ax_up = cx - int(65 * scale)
    up_poly = [
        (ax_up, cy - int(140 * scale)),                       # tip
        (ax_up + int(75 * scale), cy - int(30 * scale)),       # right wing
        (ax_up + int(28 * scale), cy - int(30 * scale)),       # inner right
        (ax_up + int(28 * scale), cy + int(115 * scale)),      # stem bottom right
        (ax_up - int(28 * scale), cy + int(115 * scale)),      # stem bottom left
        (ax_up - int(28 * scale), cy - int(30 * scale)),       # inner left
        (ax_up - int(75 * scale), cy - int(30 * scale)),       # left wing
    ]
    arr_draw.polygon(up_poly, fill=(56, 189, 248, 240))

    # Downward Arrow: Download (Emerald Green / Mint)
    ax_down = cx + int(65 * scale)
    down_poly = [
        (ax_down, cy + int(140 * scale)),                     # tip bottom
        (ax_down + int(75 * scale), cy + int(30 * scale)),     # right wing
        (ax_down + int(28 * scale), cy + int(30 * scale)),     # inner right
        (ax_down + int(28 * scale), cy - int(115 * scale)),    # stem top right
        (ax_down - int(28 * scale), cy - int(115 * scale)),    # stem top left
        (ax_down - int(28 * scale), cy + int(30 * scale)),     # inner left
        (ax_down - int(75 * scale), cy + int(30 * scale)),     # left wing
    ]
    arr_draw.polygon(down_poly, fill=(52, 211, 153, 240))

    # Glow layer for arrows
    arr_glow = arrow_img.filter(ImageFilter.GaussianBlur(int(10 * scale)))
    body.alpha_composite(arr_glow)
    body.alpha_composite(arrow_img)

    # 6. Four Service Orbital Badges (TFTP Server, TFTP Client, FTP Server, Syslog)
    node_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    n_draw = ImageDraw.Draw(node_layer)

    orbital_nodes = [
        (cx, cy - int(295 * scale), "TFTP-S", (2, 132, 199), (56, 189, 248)),   # Top: TFTP Server
        (cx + int(295 * scale), cy, "FTP", (13, 148, 136), (52, 211, 153)),     # Right: FTP Server
        (cx, cy + int(295 * scale), "SYSLOG", (124, 58, 237), (192, 132, 252)), # Bottom: Syslog
        (cx - int(295 * scale), cy, "TFTP-C", (37, 99, 235), (96, 165, 250)),   # Left: TFTP Client
    ]

    for nx, ny, name, core_col, rim_col in orbital_nodes:
        # Connecting line to center
        n_draw.line([(cx, cy), (nx, ny)], fill=(rim_col[0], rim_col[1], rim_col[2], 65), width=int(2 * scale))
        # Node outer glow
        og = int(22 * scale)
        n_draw.ellipse([nx - og, ny - og, nx + og, ny + og], fill=(rim_col[0], rim_col[1], rim_col[2], 40))
        # Outer rim
        nr = int(15 * scale)
        n_draw.ellipse([nx - nr, ny - nr, nx + nr, ny + nr], fill=core_col, outline=rim_col, width=int(3 * scale))
        # Inner jewel
        ir = int(5 * scale)
        n_draw.ellipse([nx - ir, ny - ir, nx + ir, ny + ir], fill=(255, 255, 255, 255))

    body.alpha_composite(node_layer)

    # 7. Subtle top glass reflection highlight
    glass = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    g_draw = ImageDraw.Draw(glass)
    glass_poly = [
        (pad, pad),
        (pad + box_w, pad),
        (pad + box_w, pad + int(180 * scale)),
        (pad, pad + int(280 * scale)),
    ]
    g_draw.polygon(glass_poly, fill=(255, 255, 255, 18))
    body.alpha_composite(glass)

    # 8. Metallic Inner Bevel Stroke
    bevel = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    b_stroke = ImageDraw.Draw(bevel)
    b_stroke.rounded_rectangle(
        [pad + scale, pad + scale, pad + box_w - scale, pad + box_h - scale],
        radius=radius - scale,
        outline=(255, 255, 255, 60),
        width=int(2.5 * scale)
    )
    body.alpha_composite(bevel)

    # Composite body with squircle mask
    img.paste(body, (0, 0), mask)

    # Downsample from 2048 to target 1024 with Lanczos resampling
    final_icon = img.resize((size, size), Image.Resampling.LANCZOS)
    return final_icon

def generate_all_icons(master_img, base_dir):
    os.makedirs(base_dir, exist_ok=True)
    
    # Save master logo.png
    master_path = os.path.join(base_dir, "logo.png")
    master_img.save(master_path, "PNG")
    print(f"[OK] Master icon saved: {master_path}")

    # AppIcon.appiconset directory
    xcassets_dir = os.path.join(base_dir, "SysTFTP", "Resources", "Assets.xcassets", "AppIcon.appiconset")
    os.makedirs(xcassets_dir, exist_ok=True)

    # Apple icon sizes specification
    icon_specs = [
        {"size": 16, "scale": 1, "filename": "icon_16x16.png"},
        {"size": 16, "scale": 2, "filename": "icon_16x16@2x.png"},
        {"size": 32, "scale": 1, "filename": "icon_32x32.png"},
        {"size": 32, "scale": 2, "filename": "icon_32x32@2x.png"},
        {"size": 128, "scale": 1, "filename": "icon_128x128.png"},
        {"size": 128, "scale": 2, "filename": "icon_128x128@2x.png"},
        {"size": 256, "scale": 1, "filename": "icon_256x256.png"},
        {"size": 256, "scale": 2, "filename": "icon_256x256@2x.png"},
        {"size": 512, "scale": 1, "filename": "icon_512x512.png"},
        {"size": 512, "scale": 2, "filename": "icon_512x512@2x.png"},
    ]

    images_json = []

    for spec in icon_specs:
        px = spec["size"] * spec["scale"]
        resized = master_img.resize((px, px), Image.Resampling.LANCZOS)
        out_file = os.path.join(xcassets_dir, spec["filename"])
        resized.save(out_file, "PNG")

        images_json.append({
            "size": f"{spec['size']}x{spec['size']}",
            "idiom": "mac",
            "filename": spec["filename"],
            "scale": f"{spec['scale']}x"
        })
        print(f"  Generated {spec['filename']} ({px}x{px})")

    # Contents.json for Xcode Asset Catalog
    contents_data = {
        "images": images_json,
        "info": {
            "version": 1,
            "author": "xcode"
        }
    }
    with open(os.path.join(xcassets_dir, "Contents.json"), "w", encoding="utf-8") as f:
        json.dump(contents_data, f, indent=2)
    print(f"[OK] Asset catalog Contents.json generated at {xcassets_dir}")

    # Copy also to Assets folder
    assets_logo = os.path.join(base_dir, "Assets", "logo.png")
    master_img.save(assets_logo, "PNG")

if __name__ == "__main__":
    base_dir = r"c:\Users\Administrator\Documents\SysTFTP"
    print("Generating high-resolution master macOS App Icon (1024x1024)...")
    icon = create_master_icon(1024)
    generate_all_icons(icon, base_dir)
    print("All icons successfully generated!")
