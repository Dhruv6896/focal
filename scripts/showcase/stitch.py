"""Stitches four 2x zoom tiles (top-left, top-right, bottom-left, bottom-right) of the
1200x675 showcase window into one 2400x1350 image.
Usage: python3 stitch.py tl.jpg tr.jpg bl.jpg br.jpg out.jpg"""
import sys
from PIL import Image

tl, tr, bl, br, out = sys.argv[1:6]
canvas = Image.new("RGB", (2400, 1350))
# Top tiles cover y 0..338 pt, bottom tiles 337..675 pt (2 px per pt).
canvas.paste(Image.open(tl).convert("RGB"), (0, 0))
canvas.paste(Image.open(tr).convert("RGB"), (1200, 0))
canvas.paste(Image.open(bl).convert("RGB"), (0, 674))
canvas.paste(Image.open(br).convert("RGB"), (1200, 674))
canvas.save(out, quality=92, optimize=True, progressive=True)
