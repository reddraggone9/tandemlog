"""Crop actual native screenshots by captured geometry; add report labels only."""
from pathlib import Path
import json
from PIL import Image, ImageDraw, ImageFont
ROOT = Path(__file__).resolve().parent
FONT = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'

def compare(output_name, phases, scene, labels, details, footer):
    crops = []
    for phase in phases:
        geometry = json.loads((ROOT / f'{phase}-{scene}-geometry.json').read_text())
        raw = Image.open(ROOT / f'{phase}-{scene}-raw.png').convert('RGB')
        crop = raw.crop(tuple(int(x) for x in geometry['crop']))
        crop.save(ROOT / f'{phase}-{scene}-crop.png')
        crops.append(crop)
    pad, gap, header, bottom = 20, 24, 76, 35
    output = Image.new('RGB', (sum(im.width for im in crops) + pad*2 + gap,
                              max(im.height for im in crops) + header + bottom), 'white')
    draw = ImageDraw.Draw(output)
    title = ImageFont.truetype(FONT, 20)
    detail = ImageFont.truetype(FONT, 13)
    x = pad
    for label, text, im in zip(labels, details, crops):
        draw.text((x,13), label, fill='#173c32', font=title)
        draw.text((x,43), text, fill='#46564f', font=detail)
        output.paste(im, (x,header))
        x += im.width + gap
    draw.text((pad,output.height-24),footer,fill='#46564f',font=detail)
    output.save(ROOT / output_name)

compare('primary-build43-to-build44.png', ['rc43','rc44'], '390-1x',
        ['Before · Build 43','After · Build 44'],
        ['Add time button · 390px · 100% text','Time field · 390px · 100% text'],
        'Actual native Linux · same dates, blank times and light theme · already shipped build44 change')
compare('secondary-build44-to-candidate.png',['rc44','candidate'],'520-2x',
        ['Before · Build 44','Candidate · Experiment'],
        ['Stacked controls · 520px · 200% text','Measured row fit · 520px · 200% text'],
        'Actual native Linux · same dates, blank times and light theme · isolated candidate, unpublished')
