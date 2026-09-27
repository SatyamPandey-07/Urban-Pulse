#!/usr/bin/env python3
"""Draws the Urban Pulse launcher icon for Connect IQ.

The app mark is the same one the phone draws in
`urbanpulse_flutter/lib/widgets/urbanpulse_logo.dart`: a shield/leaf silhouette
carrying a pulse waveform. It is redrawn here rather than exported from the phone
so the two stay in step, and because a watch icon needs far heavier strokes than
the phone's vector to survive being 65 px wide.

    python3 tools/make_launcher_icon.py

Writes resources/drawables/launcher.png.
"""

import os

from PIL import Image, ImageDraw

# The fr965 launcher icon is 65 x 65. Everything is drawn at SCALE times that and
# downsampled, which is what gives the curves and the waveform clean edges.
SIZE = 65
SCALE = 16
S = SIZE * SCALE

SHIELD = (0x1E, 0x29, 0x3B, 255)   # slate-800, the logo's foundation
EDGE = (0x33, 0x41, 0x55, 255)     # slate-700 rim
PULSE = (0x10, 0xB9, 0x81, 255)    # emerald, the "pulse"
MINT = (0x34, 0xD3, 0x99, 255)     # soft mint, the beacon


def u(v: float) -> float:
    """Logo-space (0-120, matching the phone's viewport) to pixels."""
    return v / 120.0 * S


def shield_path():
    """The rounded shield, as a polygon approximating the phone's cubics."""
    import math

    pts = []
    # Top arc: a wide dome from the left shoulder to the right.
    for i in range(61):
        a = math.pi * (1 + i / 60.0)
        pts.append((60 + 36 * math.cos(a), 58 + 36 * math.sin(a)))
    # Down to the point, mirroring the phone's cubic control points.
    pts += [(96, 66), (92, 78), (78, 92), (60, 103),
            (42, 92), (28, 78), (24, 66)]
    return [(u(x), u(y)) for x, y in pts]


def main() -> None:
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # A faint emerald halo, so the mark reads on both black and white watch faces.
    d.ellipse([u(8), u(8), u(112), u(112)], fill=(0x10, 0xB9, 0x81, 0x22))

    shield = shield_path()
    d.polygon(shield, fill=SHIELD)
    d.line(shield + [shield[0]], fill=EDGE, width=int(u(2.5)), joint="curve")

    # The pulse waveform: flat, up, down hard, up, flat - a heartbeat across the
    # shield. Heavier than the phone's stroke so it survives the downsample.
    wave = [(32, 62), (44, 62), (50, 44), (58, 78), (66, 54), (72, 62), (88, 62)]
    d.line([(u(x), u(y)) for x, y in wave],
           fill=PULSE, width=int(u(6)), joint="curve")

    # The beacon: a dot at the waveform's peak, the "you are here" of the mark.
    d.ellipse([u(50 - 5), u(44 - 5), u(50 + 5), u(44 + 5)], fill=MINT)

    out = img.resize((SIZE, SIZE), Image.LANCZOS)
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    path = os.path.join(here, "resources", "drawables", "launcher.png")
    out.save(path, "PNG", optimize=True)
    print("wrote", path, out.size)


if __name__ == "__main__":
    main()
