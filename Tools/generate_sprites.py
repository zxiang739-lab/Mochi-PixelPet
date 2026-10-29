#!/usr/bin/env python3
"""
Mochi — pixel sprite generator.

Draws every animation frame of the creature from code, so the art is:
  * original (no third-party assets, no licensing risk),
  * regenerable and diffable (change a constant, rerun),
  * exactly consistent in grid, palette and outline weight.

No third-party dependencies: PNGs are encoded by hand with zlib so this runs on
any machine with a stock Python 3.

Usage:
    python Tools/generate_sprites.py            # writes into Resources/Assets.xcassets
    python Tools/generate_sprites.py --out DIR  # custom output root
"""

from __future__ import annotations

import argparse
import json
import math
import struct
import zlib
from pathlib import Path
from typing import List, Tuple

Color = Tuple[int, int, int, int]
Canvas = List[List[Color]]

FRAME = 32

# --------------------------------------------------------------------------- #
# PNG encoding
# --------------------------------------------------------------------------- #


def _chunk(tag: bytes, data: bytes) -> bytes:
    return (
        struct.pack(">I", len(data))
        + tag
        + data
        + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    )


def write_png(path: Path, canvas: Canvas) -> None:
    height = len(canvas)
    width = len(canvas[0])
    raw = bytearray()
    for row in canvas:
        raw.append(0)  # filter type 0 (None)
        for r, g, b, a in row:
            raw += bytes((r, g, b, a))
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    png = (
        b"\x89PNG\r\n\x1a\n"
        + _chunk(b"IHDR", ihdr)
        + _chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + _chunk(b"IEND", b"")
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png)


# --------------------------------------------------------------------------- #
# Drawing primitives
# --------------------------------------------------------------------------- #


def new_canvas(w: int = FRAME, h: int = FRAME) -> Canvas:
    return [[(0, 0, 0, 0) for _ in range(w)] for _ in range(h)]


def blend(dst: Color, src: Color) -> Color:
    sr, sg, sb, sa = src
    if sa == 255:
        return src
    if sa == 0:
        return dst
    dr, dg, db, da = dst
    a = sa / 255.0
    return (
        int(sr * a + dr * (1 - a)),
        int(sg * a + dg * (1 - a)),
        int(sb * a + db * (1 - a)),
        max(da, sa),
    )


def px(c: Canvas, x: int, y: int, col: Color) -> None:
    if 0 <= y < len(c) and 0 <= x < len(c[0]):
        c[y][x] = blend(c[y][x], col)


def fill_ellipse(c: Canvas, cx: float, cy: float, rx: float, ry: float, col: Color) -> None:
    if rx <= 0 or ry <= 0:
        return
    for y in range(int(math.floor(cy - ry)) - 1, int(math.ceil(cy + ry)) + 2):
        for x in range(int(math.floor(cx - rx)) - 1, int(math.ceil(cx + rx)) + 2):
            dx = (x + 0.5 - cx) / rx
            dy = (y + 0.5 - cy) / ry
            if dx * dx + dy * dy <= 1.0:
                px(c, x, y, col)


def fill_rect(c: Canvas, x0: int, y0: int, w: int, h: int, col: Color) -> None:
    for y in range(y0, y0 + h):
        for x in range(x0, x0 + w):
            px(c, x, y, col)


def outline_ellipse(c: Canvas, cx, cy, rx, ry, fill: Color, line: Color) -> None:
    """Draws a 1px outline ring then the fill inside it."""
    fill_ellipse(c, cx, cy, rx + 1, ry + 1, line)
    fill_ellipse(c, cx, cy, rx, ry, fill)


def line_px(c: Canvas, x0: float, y0: float, x1: float, y1: float, col: Color) -> None:
    steps = int(max(abs(x1 - x0), abs(y1 - y0)) * 3) + 1
    for i in range(steps + 1):
        t = i / steps
        px(c, int(round(x0 + (x1 - x0) * t)), int(round(y0 + (y1 - y0) * t)), col)


def hex_rgba(value: str, alpha: int = 255) -> Color:
    value = value.lstrip("#")
    return (int(value[0:2], 16), int(value[2:4], 16), int(value[4:6], 16), alpha)


def with_alpha(col: Color, alpha: int) -> Color:
    return (col[0], col[1], col[2], alpha)


def with_alpha(col: Color, alpha: int) -> Color:
    return (col[0], col[1], col[2], alpha)


# --------------------------------------------------------------------------- #
# Palettes
# --------------------------------------------------------------------------- #


class Palette:
    def __init__(self, name, body, shade, light, outline, accent, blush):
        self.name = name
        self.body = hex_rgba(body)
        self.shade = hex_rgba(shade)
        self.light = hex_rgba(light)
        self.outline = hex_rgba(outline)
        self.accent = hex_rgba(accent)
        self.blush = hex_rgba(blush, 170)


PALETTES = {
    "dewdrop": Palette("dewdrop", "#9FE3D2", "#6FBFAE", "#D9FBF2", "#274B45", "#7FD8C4", "#F2A0A8"),
    "sprout": Palette("sprout", "#AEDD88", "#7FB663", "#E4F7CE", "#2F4A28", "#9ED77A", "#F0A6AE"),
    "bloom": Palette("bloom", "#F0AECB", "#CB7FA4", "#FDE3EF", "#4A2740", "#E79BC8", "#F58AA8"),
    "aurora": Palette("aurora", "#A9BDF7", "#7C8FD6", "#E2E9FF", "#272E56", "#8FA8F0", "#F0A0C0"),
}

STAGE_NAMES = ["dewdrop", "sprout", "bloom", "aurora"]

# --------------------------------------------------------------------------- #
# Poses
# --------------------------------------------------------------------------- #

EYE_OPEN, EYE_BLINK, EYE_HAPPY, EYE_BIG, EYE_HALF, EYE_SAD, EYE_CLOSED = range(7)
MOUTH_NONE, MOUTH_SMILE, MOUTH_OPEN, MOUTH_SMALL, MOUTH_FROWN, MOUTH_WAVE = range(6)


class Pose:
    def __init__(
        self,
        dx=0.0,
        dy=0.0,
        squash=1.0,
        stretch=1.0,
        eyes=EYE_OPEN,
        mouth=MOUTH_SMILE,
        blush=False,
        extras=(),
        tail_lift=0.0,
        lean=0.0,
    ):
        self.dx = dx
        self.dy = dy
        self.squash = squash
        self.stretch = stretch
        self.eyes = eyes
        self.mouth = mouth
        self.blush = blush
        self.extras = extras
        self.tail_lift = tail_lift
        self.lean = lean


# --------------------------------------------------------------------------- #
# Creature rendering
# --------------------------------------------------------------------------- #


def add_outline(dest: Canvas, layer: Canvas, color: Color) -> None:
    """Grows a 1px outline around the silhouette instead of around each part.

    Outlining per-shape produces seams wherever two shapes overlap; outlining the
    union produces the single continuous contour that makes pixel art read as one
    creature.
    """
    h, w = len(layer), len(layer[0])
    filled = [[layer[y][x][3] > 0 for x in range(w)] for y in range(h)]
    for y in range(h):
        for x in range(w):
            if filled[y][x]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and filled[ny][nx]:
                    px(dest, x, y, color)
                    break


def composite(dest: Canvas, layer: Canvas) -> None:
    for y in range(len(layer)):
        row = layer[y]
        for x in range(len(row)):
            col = row[x]
            if col[3]:
                px(dest, x, y, col)


def add_outline(dest: Canvas, layer: Canvas, color: Color) -> None:
    """Grows a 1px outline around the silhouette instead of around each part.

    Outlining per-shape produces seams wherever two shapes overlap; outlining the
    union produces the single continuous contour that makes pixel art read as one
    creature.
    """
    h, w = len(layer), len(layer[0])
    filled = [[layer[y][x][3] > 0 for x in range(w)] for y in range(h)]
    for y in range(h):
        for x in range(w):
            if filled[y][x]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and filled[ny][nx]:
                    px(dest, x, y, color)
                    break


def composite(dest: Canvas, layer: Canvas) -> None:
    for y in range(len(layer)):
        row = layer[y]
        for x in range(len(row)):
            col = row[x]
            if col[3]:
                px(dest, x, y, col)


def draw_creature(c: Canvas, pal: Palette, stage_idx: int, pose: Pose) -> None:
    cx = FRAME / 2 + pose.dx + pose.lean
    cy = 19 + pose.dy
    rx = 7.6 * pose.stretch
    ry = 6.8 * pose.squash

    layer = new_canvas()

    # ---- tail: a short curl off the lower right, body will cover its root ----
    tail_root_x = cx + rx - 1.6
    tail_root_y = cy + ry * 0.22
    tail_segments = []
    for i, (ox, oy, r) in enumerate(((0.0, 0.0, 1.9), (2.1, -1.9, 1.4), (3.6, -3.9, 1.0))):
        tx = tail_root_x + ox
        ty = tail_root_y + oy - pose.tail_lift
        tail_segments.append((tx, ty, r))
        fill_ellipse(layer, tx, ty, r, r, pal.body if i < 2 else pal.light)

    # ---- bloom stage: petals on the tail tip ----
    if stage_idx == 2 and tail_segments:
        ttx, tty, _ = tail_segments[-1]
        for k in range(5):
            ang = k * 2 * math.pi / 5 + 0.3
            fill_ellipse(layer, ttx + math.cos(ang) * 1.8, tty + math.sin(ang) * 1.8,
                         1.2, 1.2, pal.blush)

    # ---- feet: peek out below the body so they read as feet ----
    for fx in (cx - 3.5, cx + 2.6):
        fill_ellipse(layer, fx, cy + ry + 0.4, 2.6, 1.5, pal.shade)

    # ---- ears ----
    ear_y = cy - ry * 0.84
    for ex in (cx - 4.3, cx + 4.3):
        fill_ellipse(layer, ex, ear_y, 2.3, 3.2, pal.body)

    # ---- body ----
    fill_ellipse(layer, cx, cy, rx, ry, pal.body)

    # ---- inner shading (bottom-right) ----
    for y in range(int(cy), int(cy + ry) + 1):
        for x in range(int(cx), int(cx + rx) + 1):
            dx = (x + 0.5 - cx) / rx
            dy = (y + 0.5 - cy) / ry
            if 0.38 < dx * dx + dy * dy <= 1.0 and dx + dy > 0.5:
                px(layer, x, y, with_alpha(pal.shade, 120))

    # ---- top-left highlight ----
    fill_ellipse(layer, cx - rx * 0.40, cy - ry * 0.50, rx * 0.30, ry * 0.20, with_alpha(pal.light, 200))

    # ---- ear inner blush ----
    for ex in (cx - 4.3, cx + 4.3):
        fill_ellipse(layer, ex, ear_y + 0.4, 1.1, 1.5, with_alpha(pal.blush, 150))

    # ---- sprout (stage 1+) ----
    if stage_idx >= 1:
        stem_top = cy - ry - 2.6
        line_px(layer, cx, cy - ry + 1.0, cx, stem_top + 0.6, hex_rgba("#6E9E4E"))
        for dirn in (-1, 1):
            fill_ellipse(layer, cx + dirn * 2.1, stem_top, 2.0, 1.2, pal.accent)

    # ---- face ----
    eye_dx = rx * 0.40
    eye_y = cy - ry * 0.14
    draw_eyes(layer, pal, cx - eye_dx, eye_y, pose.eyes)
    draw_eyes(layer, pal, cx + eye_dx, eye_y, pose.eyes)
    draw_mouth(layer, pal, cx, cy + ry * 0.40, pose.mouth)

    if pose.blush:
        fill_ellipse(layer, cx - rx * 0.68, cy + ry * 0.28, 1.8, 1.0, pal.blush)
        fill_ellipse(layer, cx + rx * 0.68, cy + ry * 0.28, 1.8, 1.0, pal.blush)

    # ---- aura for the final form, drawn behind everything ----
    if stage_idx == 3:
        ring(c, cx, cy, 10.4, with_alpha(pal.accent, 70))
        ring(c, cx, cy, 11.3, with_alpha(pal.accent, 40))

    add_outline(c, layer, pal.outline)
    composite(c, layer)

    draw_extras(c, pal, cx, cy, rx, ry, pose.extras)


def ring(c: Canvas, cx: float, cy: float, r: float, col: Color) -> None:
    steps = int(2 * math.pi * r * 2)
    for i in range(steps):
        ang = 2 * math.pi * i / steps
        px(c, int(round(cx + math.cos(ang) * r)), int(round(cy + math.sin(ang) * r)), col)


DARK = hex_rgba("#1B2B2A")


def draw_eyes(c: Canvas, pal: Palette, ex: float, ey: float, style: int) -> None:
    x = int(round(ex))
    y = int(round(ey))
    if style == EYE_OPEN:
        fill_rect(c, x - 1, y - 1, 2, 3, DARK)
        fill_rect(c, x - 1, y - 1, 2, 1, pal.outline)
        px(c, x - 1, y - 1, hex_rgba("#FFFFFF"))
    elif style == EYE_BLINK:
        fill_rect(c, x - 1, y, 2, 1, DARK)
    elif style == EYE_HAPPY:
        px(c, x - 1, y + 1, DARK)
        px(c, x, y, DARK)
        px(c, x + 1, y + 1, DARK)
    elif style == EYE_BIG:
        fill_rect(c, x - 1, y - 2, 3, 4, DARK)
        px(c, x - 1, y - 2, hex_rgba("#FFFFFF"))
        px(c, x, y - 2, hex_rgba("#FFFFFF"))
    elif style == EYE_HALF:
        fill_rect(c, x - 1, y, 2, 1, DARK)
        fill_rect(c, x - 1, y - 1, 2, 1, pal.body)
        px(c, x - 1, y - 1, DARK)
    elif style == EYE_SAD:
        px(c, x - 1, y - 1, DARK)
        fill_rect(c, x - 1, y, 2, 1, DARK)
    elif style == EYE_CLOSED:
        fill_rect(c, x - 1, y, 3, 1, DARK)


def draw_mouth(c: Canvas, pal: Palette, mx: float, my: float, style: int) -> None:
    x = int(round(mx))
    y = int(round(my))
    if style == MOUTH_NONE:
        return
    if style == MOUTH_SMILE:
        px(c, x - 1, y, DARK)
        px(c, x, y + 1, DARK)
        px(c, x + 1, y, DARK)
    elif style == MOUTH_OPEN:
        fill_ellipse(c, x, y + 0.5, 1.6, 1.5, hex_rgba("#8C4A56"))
        px(c, x, y + 1, hex_rgba("#D97A88"))
    elif style == MOUTH_SMALL:
        px(c, x, y, DARK)
        px(c, x, y + 1, DARK)
    elif style == MOUTH_FROWN:
        px(c, x - 1, y + 1, DARK)
        px(c, x, y, DARK)
        px(c, x + 1, y + 1, DARK)
    elif style == MOUTH_WAVE:
        px(c, x - 1, y, DARK)
        px(c, x, y + 1, DARK)
        px(c, x + 1, y, DARK)
        px(c, x + 2, y + 1, DARK)


def draw_extras(c: Canvas, pal: Palette, cx, cy, rx, ry, extras) -> None:
    for extra in extras:
        if extra == "sparkle":
            for (sx, sy) in ((-9, -10), (9, -12), (11, -4)):
                x, y = int(cx + sx), int(cy + sy)
                col = hex_rgba("#FFF3B0")
                px(c, x, y, col)
                px(c, x - 1, y, col)
                px(c, x + 1, y, col)
                px(c, x, y - 1, col)
                px(c, x, y + 1, col)
        elif extra == "zzz":
            for (dx, dy, s) in ((9, -12, 1), (12, -15, 0), (14, -17, 0)):
                x, y = int(cx + dx), int(cy + dy)
                if s:
                    fill_rect(c, x, y, 3, 1, hex_rgba("#CFE6FF"))
                    px(c, x + 2, y + 1, hex_rgba("#CFE6FF"))
                    px(c, x + 1, y + 2, hex_rgba("#CFE6FF"))
                    px(c, x, y + 2, hex_rgba("#CFE6FF"))
                else:
                    fill_rect(c, x, y, 2, 1, hex_rgba("#CFE6FF"))
                    px(c, x + 1, y + 1, hex_rgba("#CFE6FF"))
                    px(c, x, y + 1, hex_rgba("#CFE6FF"))
        elif extra == "heart":
            for (hx, hy) in ((10, -12), (-11, -10)):
                x, y = int(cx + hx), int(cy + hy)
                col = hex_rgba("#F58AA8")
                fill_rect(c, x, y, 3, 2, col)
                px(c, x + 1, y + 2, col)
                px(c, x, y + 2, col)
                px(c, x + 2, y + 2, col)
        elif extra == "crumbs":
            for (px_, py_) in ((-7, 8), (0, 10), (7, 8)):
                px(c, int(cx + px_), int(cy + py_), hex_rgba("#E3B778"))
        elif extra == "confetti":
            colors = ["#F58AA8", "#FFD37A", "#8FD6F0", "#B7E88F"]
            for i, (dx, dy) in enumerate(((-10, -11), (-4, -14), (4, -14), (10, -11), (11, -3), (-11, -3))):
                col = hex_rgba(colors[i % len(colors)])
                fill_rect(c, int(cx + dx), int(cy + dy), 2, 1, col)
        elif extra == "exclaim":
            x, y = int(cx + 9), int(cy - 14)
            fill_rect(c, x, y, 2, 4, hex_rgba("#FFD37A"))
            fill_rect(c, x, y + 5, 2, 1, hex_rgba("#FFD37A"))
        elif extra == "dust":
            for (dx, dy) in ((-10, 6), (-8, 8), (-12, 8)):
                px(c, int(cx + dx), int(cy + dy), hex_rgba("#D8CBB0", 150))
        elif extra == "sweat":
            x, y = int(cx + rx + 1), int(cy - ry + 2)
            fill_rect(c, x, y, 1, 2, hex_rgba("#9FD8F0"))


# --------------------------------------------------------------------------- #
# Animation recipes
# --------------------------------------------------------------------------- #


def frames_for(state: str) -> List[Pose]:
    """Returns one Pose per frame. Frame counts must match BehaviorState.frameCount."""
    if state == "idle":
        return [
            Pose(dy=0.0, squash=1.00),
            Pose(dy=-0.6, squash=0.98, stretch=1.01),
            Pose(dy=-0.3, squash=1.00, eyes=EYE_BLINK),
            Pose(dy=0.2, squash=1.02),
        ]
    if state == "walk":
        return [
            Pose(dy=0.0, lean=0.4, tail_lift=0.4),
            Pose(dy=-0.8, lean=0.8, stretch=1.02, tail_lift=0.8),
            Pose(dy=0.0, lean=1.2, tail_lift=0.4),
            Pose(dy=0.0, lean=0.4, tail_lift=0.4, eyes=EYE_HALF),
            Pose(dy=-0.8, lean=0.8, stretch=1.02, tail_lift=0.8),
            Pose(dy=0.0, lean=1.2, tail_lift=0.4),
        ]
    if state == "run":
        return [
            Pose(dy=-0.4, lean=1.6, squash=0.96, mouth=MOUTH_OPEN, extras=("dust",)),
            Pose(dy=-1.6, lean=2.2, stretch=1.06, mouth=MOUTH_OPEN, extras=("dust",)),
            Pose(dy=-0.4, lean=2.6, squash=0.98, mouth=MOUTH_OPEN, eyes=EYE_HAPPY),
            Pose(dy=-0.4, lean=1.6, squash=0.96, mouth=MOUTH_OPEN, extras=("dust",)),
            Pose(dy=-1.6, lean=2.2, stretch=1.06, mouth=MOUTH_OPEN, extras=("dust",)),
            Pose(dy=-0.4, lean=2.6, squash=0.98, mouth=MOUTH_OPEN, eyes=EYE_HAPPY),
        ]
    if state == "sleep":
        return [
            Pose(dy=1.4, squash=0.86, stretch=1.08, eyes=EYE_CLOSED, mouth=MOUTH_NONE, extras=("zzz",)),
            Pose(dy=2.0, squash=0.80, stretch=1.12, eyes=EYE_CLOSED, mouth=MOUTH_NONE, extras=("zzz",)),
            Pose(dy=1.4, squash=0.86, stretch=1.08, eyes=EYE_CLOSED, mouth=MOUTH_NONE),
        ]
    if state == "wake":
        return [
            Pose(dy=1.0, squash=0.92, eyes=EYE_BLINK, mouth=MOUTH_SMALL),
            Pose(dy=-0.4, squash=1.02, eyes=EYE_HALF, mouth=MOUTH_SMALL),
            Pose(dy=-0.8, squash=1.04, eyes=EYE_OPEN, mouth=MOUTH_SMALL),
        ]
    if state == "happy":
        return [
            Pose(dy=-0.6, eyes=EYE_HAPPY, mouth=MOUTH_SMILE, blush=True),
            Pose(dy=-2.0, squash=0.94, eyes=EYE_HAPPY, mouth=MOUTH_OPEN, blush=True, extras=("sparkle",)),
            Pose(dy=-0.6, eyes=EYE_HAPPY, mouth=MOUTH_SMILE, blush=True),
            Pose(dy=0.4, squash=1.06, eyes=EYE_HAPPY, mouth=MOUTH_SMILE, blush=True),
        ]
    if state == "curious":
        return [
            Pose(dx=-0.8, dy=-0.4, lean=-0.8, eyes=EYE_BIG, mouth=MOUTH_SMALL),
            Pose(dx=-1.2, dy=-0.8, lean=-1.4, eyes=EYE_BIG, mouth=MOUTH_SMALL, tail_lift=0.8),
            Pose(dx=-0.4, dy=-0.4, lean=-0.6, eyes=EYE_OPEN, mouth=MOUTH_SMALL),
        ]
    if state == "sad":
        return [
            Pose(dy=1.0, squash=0.92, eyes=EYE_SAD, mouth=MOUTH_FROWN, tail_lift=-1.2),
            Pose(dy=1.4, squash=0.88, eyes=EYE_SAD, mouth=MOUTH_FROWN, tail_lift=-1.6),
            Pose(dy=1.0, squash=0.92, eyes=EYE_HALF, mouth=MOUTH_FROWN, tail_lift=-1.2),
        ]
    if state == "eat":
        return [
            Pose(dy=0.4, eyes=EYE_OPEN, mouth=MOUTH_OPEN, extras=("crumbs",)),
            Pose(dy=0.8, squash=0.96, eyes=EYE_HAPPY, mouth=MOUTH_NONE, extras=("crumbs",)),
            Pose(dy=0.4, eyes=EYE_OPEN, mouth=MOUTH_OPEN, extras=("crumbs",)),
            Pose(dy=0.8, squash=0.96, eyes=EYE_HAPPY, mouth=MOUTH_SMILE, blush=True),
        ]
    if state == "play":
        return [
            Pose(dy=0.6, squash=1.08, eyes=EYE_HAPPY, mouth=MOUTH_OPEN),
            Pose(dy=-2.4, squash=0.94, stretch=1.04, eyes=EYE_HAPPY, mouth=MOUTH_OPEN, extras=("sparkle",)),
            Pose(dy=-1.0, squash=1.0, eyes=EYE_HAPPY, mouth=MOUTH_SMILE, tail_lift=1.0),
            Pose(dy=0.6, squash=1.08, eyes=EYE_HAPPY, mouth=MOUTH_OPEN, blush=True),
        ]
    if state == "pet":
        return [
            Pose(dy=0.6, squash=1.10, stretch=1.04, eyes=EYE_HAPPY, mouth=MOUTH_SMILE, blush=True),
            Pose(dy=1.0, squash=1.16, stretch=1.06, eyes=EYE_CLOSED, mouth=MOUTH_SMILE, blush=True, extras=("heart",)),
            Pose(dy=0.6, squash=1.10, stretch=1.04, eyes=EYE_HAPPY, mouth=MOUTH_SMILE, blush=True),
            Pose(dy=0.2, squash=1.04, eyes=EYE_HAPPY, mouth=MOUTH_SMILE, blush=True, extras=("heart",)),
        ]
    if state == "surprise":
        return [
            Pose(dy=-1.0, squash=0.92, eyes=EYE_BIG, mouth=MOUTH_OPEN, extras=("exclaim",)),
            Pose(dy=-2.6, squash=0.88, stretch=1.06, eyes=EYE_BIG, mouth=MOUTH_OPEN, extras=("exclaim",)),
            Pose(dy=-1.2, squash=0.98, eyes=EYE_BIG, mouth=MOUTH_SMALL, extras=("sweat",)),
        ]
    if state == "explore":
        return [
            Pose(dx=-0.6, dy=-0.2, lean=0.6, eyes=EYE_OPEN, mouth=MOUTH_SMALL, extras=("dust",)),
            Pose(dx=0.4, dy=-1.0, lean=1.0, eyes=EYE_BIG, mouth=MOUTH_SMALL, tail_lift=0.8),
            Pose(dx=0.0, dy=-0.2, lean=0.2, eyes=EYE_BIG, mouth=MOUTH_SMALL, extras=("dust",)),
            Pose(dx=-0.4, dy=-0.6, lean=-0.6, eyes=EYE_OPEN, mouth=MOUTH_SMILE, tail_lift=0.4),
        ]
    if state == "celebrate":
        return [
            Pose(dy=0.4, squash=1.06, eyes=EYE_HAPPY, mouth=MOUTH_OPEN),
            Pose(dy=-2.8, squash=0.92, stretch=1.06, eyes=EYE_HAPPY, mouth=MOUTH_OPEN, extras=("confetti",)),
            Pose(dy=-1.0, eyes=EYE_HAPPY, mouth=MOUTH_SMILE, blush=True, extras=("sparkle",)),
            Pose(dy=-2.8, squash=0.92, stretch=1.06, eyes=EYE_HAPPY, mouth=MOUTH_OPEN, extras=("confetti",)),
            Pose(dy=0.4, squash=1.06, eyes=EYE_HAPPY, mouth=MOUTH_SMILE, blush=True),
        ]
    raise ValueError(f"unknown state {state}")


STATES = [
    "idle", "walk", "run", "sleep", "wake", "happy", "curious",
    "sad", "eat", "play", "pet", "surprise", "explore", "celebrate",
]


def build_strip(stage_idx: int, state: str) -> Canvas:
    poses = frames_for(state)
    width = FRAME * len(poses)
    strip = new_canvas(width, FRAME)
    pal = PALETTES[STAGE_NAMES[stage_idx]]
    for i, pose in enumerate(poses):
        frame = new_canvas()
        draw_creature(frame, pal, stage_idx, pose)
        for y in range(FRAME):
            for x in range(FRAME):
                strip[y][i * FRAME + x] = frame[y][x]
    return strip


# --------------------------------------------------------------------------- #
# Scene backgrounds
# --------------------------------------------------------------------------- #

BG_W, BG_H = 96, 64


def build_background(kind: str) -> Canvas:
    c = new_canvas(BG_W, BG_H)
    if kind == "meadow":
        bands = ["#CFE9D8", "#DCEFDD", "#E8F4E2", "#F2F7E8"]
        for i, col in enumerate(bands):
            fill_rect(c, 0, i * 10, BG_W, 10, hex_rgba(col))
        fill_rect(c, 0, 44, BG_W, 20, hex_rgba("#9CC98A"))
        fill_rect(c, 0, 44, BG_W, 2, hex_rgba("#7FAF6E"))
        for x in range(3, BG_W, 11):
            fill_rect(c, x, 48, 1, 3, hex_rgba("#7FAF6E"))
            fill_rect(c, x + 4, 52, 1, 2, hex_rgba("#8FBF7C"))
        # distant hills + tree
        fill_ellipse(c, 24, 46, 18, 8, hex_rgba("#B6D8A6"))
        fill_ellipse(c, 74, 47, 22, 9, hex_rgba("#A8CE98"))
        fill_rect(c, 68, 26, 4, 18, hex_rgba("#8A6B52"))
        fill_ellipse(c, 70, 22, 11, 9, hex_rgba("#8FC47F"))
    elif kind == "cavern":
        fill_rect(c, 0, 0, BG_W, BG_H, hex_rgba("#1B2233"))
        for i in range(10):
            y = 6 + i * 5
            fill_rect(c, 0, y, BG_W, 1, hex_rgba("#232C42"))
        fill_rect(c, 0, 46, BG_W, 18, hex_rgba("#2A3450"))
        for x in range(4, BG_W, 13):
            fill_ellipse(c, x, 8, 1.2, 2.5, hex_rgba("#5FE0C8", 200))
            fill_ellipse(c, x, 8, 2.6, 3.6, hex_rgba("#5FE0C8", 40))
        for x in range(9, BG_W, 17):
            fill_ellipse(c, x, 52, 2.0, 1.2, hex_rgba("#7FD8C4", 120))
    else:  # sky
        bands = ["#BBD9F5", "#CBE4F8", "#DCF0FB", "#EEF8FE"]
        for i, col in enumerate(bands):
            fill_rect(c, 0, i * 11, BG_W, 11, hex_rgba(col))
        for (x, y, r) in ((18, 20, 8), (48, 14, 10), (78, 24, 7)):
            fill_ellipse(c, x, y, r, r * 0.6, hex_rgba("#FFFFFF", 220))
            fill_ellipse(c, x + r * 0.7, y + 1, r * 0.6, r * 0.45, hex_rgba("#FFFFFF", 200))
        fill_rect(c, 0, 46, BG_W, 18, hex_rgba("#D8E8F5"))
    return c


def build_icon() -> Canvas:
    """1024x1024 app icon: the creature on a soft gradient, nearest-neighbour upscaled."""
    size = 1024
    base = new_canvas(64, 64)
    for y in range(64):
        t = y / 63
        col = (
            int(206 + (150 - 206) * t),
            int(238 + (196 - 238) * t),
            int(228 + (246 - 228) * t),
            255,
        )
        for x in range(64):
            base[y][x] = col
    frame = new_canvas(64, 64)
    pal = PALETTES["dewdrop"]
    # draw at 2x scale into the 64 grid
    inner = new_canvas(FRAME, FRAME)
    draw_creature(inner, pal, 1, Pose(eyes=EYE_HAPPY, mouth=MOUTH_SMILE, blush=True, extras=("sparkle",)))
    for y in range(FRAME):
        for x in range(FRAME):
            col = inner[y][x]
            if col[3] == 0:
                continue
            for dy in range(2):
                for dx in range(2):
                    nx, ny = 16 + x * 2 + dx, 16 + y * 2 + dy
                    if 0 <= nx < 64 and 0 <= ny < 64:
                        base[ny][nx] = col
    out = new_canvas(size, size)
    scale = size // 64
    for y in range(size):
        for x in range(size):
            out[y][x] = base[y // scale][x // scale]
    return out


# --------------------------------------------------------------------------- #
# Asset catalogue emission
# --------------------------------------------------------------------------- #

CONTENTS_INFO = {"author": "xcode", "version": 1}


def write_imageset(root: Path, name: str, png: Path) -> None:
    folder = root / f"{name}.imageset"
    folder.mkdir(parents=True, exist_ok=True)
    (folder / png.name).write_bytes(png.read_bytes())
    contents = {
        "images": [{"filename": png.name, "idiom": "universal"}],
        "info": CONTENTS_INFO,
    }
    (folder / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")


def write_colorset(root: Path, name: str, hex_value: str) -> None:
    folder = root / f"{name}.colorset"
    folder.mkdir(parents=True, exist_ok=True)
    v = hex_value.lstrip("#")
    rgb = (int(v[0:2], 16) / 255.0, int(v[2:4], 16) / 255.0, int(v[4:6], 16) / 255.0)
    contents = {
        "colors": [
            {
                "color": {
                    "color-space": "srgb",
                    "components": {
                        "alpha": "1.000",
                        "blue": f"{rgb[2]:.3f}",
                        "green": f"{rgb[1]:.3f}",
                        "red": f"{rgb[0]:.3f}",
                    },
                },
                "idiom": "universal",
            }
        ],
        "info": CONTENTS_INFO,
    }
    (folder / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")


def write_appicon(root: Path, png: Path) -> None:
    folder = root / "AppIcon.appiconset"
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "icon-1024.png").write_bytes(png.read_bytes())
    contents = {
        "images": [{"filename": "icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
        "info": CONTENTS_INFO,
    }
    (folder / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--out",
        default=str(Path(__file__).resolve().parent.parent / "Resources" / "Assets.xcassets"),
    )
    parser.add_argument("--png-out", default=None, help="optional raw PNG dump for inspection")
    args = parser.parse_args()

    root = Path(args.out)
    root.mkdir(parents=True, exist_ok=True)
    (root / "Contents.json").write_text(json.dumps(CONTENTS_INFO, indent=2) + "\n")

    tmp = root / "_raw"
    tmp.mkdir(exist_ok=True)

    count = 0
    for idx, stage in enumerate(STAGE_NAMES):
        for state in STATES:
            strip = build_strip(idx, state)
            png = tmp / f"pet_{stage}_{state}.png"
            write_png(png, strip)
            write_imageset(root, f"pet_{stage}_{state}", png)
            count += 1

    # Single-frame posters: widgets and Live Activities cannot crop a sprite
    # sheet, so each growth form also ships one still frame.
    for idx, stage in enumerate(STAGE_NAMES):
        strip = build_strip(idx, "idle")
        single = new_canvas()
        offset = FRAME  # second frame of idle reads more "alive" than the first
        for y in range(FRAME):
            for x in range(FRAME):
                single[y][x] = strip[y][offset + x]
        png = tmp / f"poster_{stage}.png"
        write_png(png, single)
        write_imageset(root, f"poster_{stage}", png)

    # Single-frame posters: widgets and Live Activities cannot crop a sprite
    # sheet, so each growth form also ships one still frame.
    for idx, stage in enumerate(STAGE_NAMES):
        strip = build_strip(idx, "idle")
        single = new_canvas()
        offset = FRAME  # second frame of idle reads more "alive" than the first
        for y in range(FRAME):
            for x in range(FRAME):
                single[y][x] = strip[y][offset + x]
        png = tmp / f"poster_{stage}.png"
        write_png(png, single)
        write_imageset(root, f"poster_{stage}", png)

    for kind in ("meadow", "cavern", "sky"):
        png = tmp / f"bg_{kind}.png"
        write_png(png, build_background(kind))
        write_imageset(root, f"bg_{kind}", png)

    icon_png = tmp / "icon-1024.png"
    write_png(icon_png, build_icon())
    write_appicon(root, icon_png)

    write_colorset(root, "AccentColor", "#7FD8C4")
    write_colorset(root, "LaunchBackground", "#EAF6F1")

    # keep the raw PNGs for debugging but out of the compiled catalogue
    import shutil

    shutil.rmtree(tmp, ignore_errors=True)

    if args.png_out:
        dump = Path(args.png_out)
        for idx, stage in enumerate(STAGE_NAMES):
            for state in STATES:
                write_png(dump / f"pet_{stage}_{state}.png", build_strip(idx, state))

    print(f"generated {count} sprite sheets, 3 backgrounds, 1 icon into {root}")


if __name__ == "__main__":
    main()
