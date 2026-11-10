#!/usr/bin/env python3
"""Download source WEBP resources, extract each 36x36 icon as PNG, and create CSS using local PNG files.
Requires: python -m pip install pillow requests
Run in the same folder as icons.json: python extract_png.py
"""
import json, pathlib, requests, io
from PIL import Image
root=pathlib.Path(__file__).resolve().parent
items=json.loads((root/'icons.json').read_text(encoding='utf8'))
folder=root/'png';folder.mkdir(exist_ok=True)
images={}
css=['/* Standalone locally hosted icons */','.fb-icon {display:inline-block;width:36px;height:36px;flex:0 0 36px;background-repeat:no-repeat;vertical-align:middle;}']
for it in items:
    url=it['url']
    if url not in images:
        response=requests.get(url, timeout=30, headers={'User-Agent':'Mozilla/5.0'})
        response.raise_for_status()
        images[url]=Image.open(io.BytesIO(response.content)).convert('RGBA')
    source=images[url]
    if it['type']=='sprite':
        parts=it['position'].replace('px','').split()
        x,y=[int(float(v)) for v in parts[:2]]
        # CSS background-position offsets the sprite; crop from -x, -y.
        icon=source.crop((-x,-y,-x+36,-y+36))
    else:
        icon=source.resize((36,36),Image.Resampling.LANCZOS) if source.size!=(36,36) else source
    icon.save(folder/(it['slug']+'.png'))
    css.append(f'.fb-icon--{it["slug"]} {{background-image:url("png/{it["slug"]}.png");}}')
(root/'icons-local.css').write_text('\n'.join(css)+'\n',encoding='utf8')
print(f'Extracted {len(items)} icons into {folder}; use icons-local.css.')
