"""The shared atlas must retain 64-pixel cells and resolve every HUD icon."""
from pathlib import Path
import re
import xml.etree.ElementTree as ET
root=Path(__file__).resolve().parents[1]
atlas=ET.parse(root/'assets/ui/parts_atlas.svg').getroot()
ns={'svg':'http://www.w3.org/2000/svg'}
width,height=int(atlas.attrib['width']),int(atlas.attrib['height'])
assert width==512 and height%64==0
assert atlas.attrib['viewBox']==f'0 0 {width} {height}'
cells=atlas.find('svg:g',ns).findall('svg:g',ns)
locations={g.attrib.get('transform') for g in cells}
indices=[int(i) for i in re.findall(r'"[a-z_]+": (\d+)', (root/'scripts/hud.gd').read_text(encoding='utf-8').split('const ICONS = ',1)[1].split('\n',1)[0])]
assert len(indices)==len(set(indices)), 'Atlas indices must remain unique'
for i in indices:
 assert i<width//64*(height//64),f'Icon {i} outside atlas'
 assert f'translate({i%8*64} {i//8*64})' in locations,f'Cell {i} missing'
assert all(len(list(g))>0 for g in cells),'Empty painted cell'
print(f'ATLAS_CHECKS: {len(indices)} routed icons in {width}x{height}; every cell present and in bounds')
