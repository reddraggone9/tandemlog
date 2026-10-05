"""Only crop native pixels and center Before/After labels; no other added text."""
from pathlib import Path
import json
from PIL import Image, ImageDraw, ImageFont
ROOT=Path(__file__).resolve().parent
FONT='/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
CASES=[
 ('historical-time-fields','historical-before','historical-after'),
 ('normal-width','normal-before','normal-after'),
 ('enlarged-width','enlarged-before','enlarged-after'),
]
for name,before,after in CASES:
 if not all((ROOT/'raw'/f'{phase}-geometry.json').exists() for phase in [before,after]):continue
 crops=[]
 for phase in [before,after]:
  geometry=json.loads((ROOT/'raw'/f'{phase}-geometry.json').read_text())
  crop=Image.open(ROOT/'raw'/f'{phase}-raw.png').convert('RGB').crop(tuple(int(x) for x in geometry['crop']))
  crop.save(ROOT/'raw'/f'{phase}-crop.png');crops.append(crop)
 pad,gap,header=10,20,42
 width=sum(im.width for im in crops)+pad*2+gap
 height=max(im.height for im in crops)+header+10
 output=Image.new('RGB',(width,height),'white');draw=ImageDraw.Draw(output)
 font=ImageFont.truetype(FONT,20)
 x=pad
 for label,im in zip(['Before','After'],crops):
  draw.text((x+im.width/2,21),label,fill='#202020',font=font,anchor='mm')
  output.paste(im,(x,header));x+=im.width+gap
 output.save(ROOT/'proposed'/f'{name}.png')
