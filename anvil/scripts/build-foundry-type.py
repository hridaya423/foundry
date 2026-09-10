import json
from pathlib import Path
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
from fontTools.pens.basePen import BasePen
from fontTools.ttLib.removeOverlaps import removeOverlaps

source = next(p for p in Path('.next/static/media').glob('*.woff2') if TTFont(p)['name'].getDebugName(1) == 'Geist' and 65 in TTFont(p).getBestCmap())
font = instantiateVariableFont(TTFont(source), {'wght': 750}, inplace=False)
removeOverlaps(font)
glyphs = font.getGlyphSet()
class OutlinePen(BasePen):
    def __init__(self):
        super().__init__(glyphs)
        self.commands = []
    def add(self, command, *points):
        self.commands.append(command)
        self.commands.extend(str(round(v, 2)) for p in points for v in p)
    def _moveTo(self, p): self.add('m', p)
    def _lineTo(self, p): self.add('l', p)
    def _qCurveToOne(self, c, p): self.add('q', p, c)
    def _curveToOne(self, c1, c2, p): self.add('b', p, c1, c2)
    def _closePath(self): pass
    def _endPath(self): pass

out = {}
for char, name in font.getBestCmap().items():
    if char < 32: continue
    pen = OutlinePen()
    glyphs[name].draw(pen)
    out[chr(char)] = {'ha': glyphs[name].width, 'x_min': 0, 'x_max': glyphs[name].width, 'o': ' '.join(pen.commands)}
result = {'glyphs': out, 'familyName': 'Geist', 'ascender': font['hhea'].ascent, 'descender': font['hhea'].descent, 'underlinePosition': -100, 'underlineThickness': 50, 'boundingBox': {'yMin': font['head'].yMin, 'yMax': font['head'].yMax, 'xMin': font['head'].xMin, 'xMax': font['head'].xMax}, 'resolution': font['head'].unitsPerEm, 'original_font_information': {'source': str(source), 'weight': '750'}}
Path('public/assets/foundry/story/tools/geist-bold.json').write_text(json.dumps(result, separators=(',', ':')))
print(source, len(out), 'glyphs')
