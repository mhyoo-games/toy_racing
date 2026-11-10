"""아이콘(assets/icon.png)을 코드로 그린다.  python3 tools/art/icon.py  (pillow 필요)"""
import os
from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'assets', 'icon.png')
im = Image.new('RGBA', (64, 64), (0, 0, 0, 0))
d = ImageDraw.Draw(im)
d.rounded_rectangle([2, 2, 62, 62], 14, fill=(95, 156, 69, 255))
d.rounded_rectangle([12, 26, 52, 44], 6, fill=(200, 135, 63, 255), outline=(60, 40, 25, 255), width=2)
d.rectangle([24, 18, 40, 30], fill=(255, 241, 214, 255), outline=(60, 40, 25, 255), width=2)
for x in (16, 48):
    d.ellipse([x - 6, 40, x + 6, 52], fill=(40, 38, 42, 255))
im.save(OUT)
