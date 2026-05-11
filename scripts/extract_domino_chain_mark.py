#!/usr/bin/env python3
"""
Extract the Domino Chain logo mark from a full design sheet (grid / variants).

Uses hue/saturation heuristics to build a mask, then keeps the largest connected
component (the main hero glyph). Output is a tight PNG crop with transparency.

Example:
  python3 scripts/extract_domino_chain_mark.py \\
    --input path/to/full-sheet.png \\
    --output backend/app/assets/images/domino-chain-mark-extracted.png
"""

from __future__ import annotations

import argparse
from collections import deque

from PIL import Image
import numpy as np


def largest_component_bbox(mask: np.ndarray) -> tuple[int, int, int, int] | None:
    h, w = mask.shape
    seen = np.zeros((h, w), dtype=bool)
    best = (0, 0, 0, 0, 0)  # area, y0, y1, x0, x1

    for y in range(h):
        row = mask[y]
        xs = np.flatnonzero(row & ~seen[y])
        for x0 in xs:
            if seen[y, x0] or not mask[y, x0]:
                continue
            q = deque([(y, x0)])
            seen[y, x0] = True
            mn_y = mx_y = y
            mn_x = mx_x = x0
            cnt = 0
            while q:
                cy, cx = q.popleft()
                cnt += 1
                if cy < mn_y:
                    mn_y = cy
                if cy > mx_y:
                    mx_y = cy
                if cx < mn_x:
                    mn_x = cx
                if cx > mx_x:
                    mx_x = cx
                for ny, nx in ((cy + 1, cx), (cy - 1, cx), (cy, cx + 1), (cy, cx - 1)):
                    if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        q.append((ny, nx))
            if cnt > best[0]:
                best = (cnt, mn_y, mx_y, mn_x, mx_x)

    if best[0] == 0:
        return None
    _, mn_y, mx_y, mn_x, mx_x = best
    return mn_x, mn_y, mx_x + 1, mx_y + 1


def build_logo_mask(rgb: np.ndarray) -> np.ndarray:
    r = rgb[:, :, 0].astype(np.float32)
    g = rgb[:, :, 1].astype(np.float32)
    b = rgb[:, :, 2].astype(np.float32)
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    sat = np.where(mx < 1e-3, 0.0, (mx - mn) / np.maximum(mx, 1e-3))
    cyanish = (g > r + 22.0) & (b > r + 12.0) & (sat > 0.14)
    purplish = (r > g + 18.0) & (b > g + 8.0) & (sat > 0.11)
    return (cyanish | purplish) & (sat > 0.08)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True, help="Full design sheet PNG")
    ap.add_argument("--output", required=True, help="Tight PNG crop of the logo mark")
    ap.add_argument("--pad", type=int, default=32, help="Padding around bbox")
    args = ap.parse_args()

    img = Image.open(args.input).convert("RGBA")
    arr = np.asarray(img)
    bbox = largest_component_bbox(build_logo_mask(arr[:, :, :3]))
    if bbox is None:
        raise SystemExit("Could not detect logo-colored region (adjust thresholds?).")

    xmin, ymin, xmax, ymax = bbox
    pad = args.pad
    h, w = arr.shape[0], arr.shape[1]
    xmin = max(0, xmin - pad)
    ymin = max(0, ymin - pad)
    xmax = min(w, xmax + pad)
    ymax = min(h, ymax + pad)

    cropped = img.crop((xmin, ymin, xmax, ymax))
    cropped.save(args.output)
    print(f"Wrote {args.output} ({cropped.size[0]}×{cropped.size[1]})")


if __name__ == "__main__":
    main()
