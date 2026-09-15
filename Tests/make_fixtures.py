"""Generate minimal OOXML test archives with non-matching slide/notes filenames.
These are parser fixtures, not presentation deliverables.
"""
from pathlib import Path
from zipfile import ZipFile
import sys

out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)
ns = 'http://schemas.openxmlformats.org/presentationml/2006/main'
rel = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'

def notes(text, extra=''):
    return f'''<p:notes xmlns:p="{ns}" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><p:cSld><p:spTree><p:sp><p:nvSpPr><p:nvPr><p:ph type="body"/></p:nvPr></p:nvSpPr><p:txBody>{text}</p:txBody></p:sp>{extra}</p:spTree></p:cSld></p:notes>'''

def write_fixture(name, broken=False, all_notes=False):
    with ZipFile(out / name, 'w') as z:
        z.writestr('ppt/presentation.xml', f'<p:presentation xmlns:p="{ns}" xmlns:r="{rel}"><p:sldIdLst><p:sldId id="400" r:id="r9"/><p:sldId id="256" r:id="r1"/><p:sldId id="900" r:id="r2"/></p:sldIdLst></p:presentation>')
        items = '' if broken else f'<Relationship Id="r9" Type="{rel}/slide" Target="slides/slide9.xml"/>'
        items += f'<Relationship Id="r1" Type="{rel}/slide" Target="slides/slide1.xml"/><Relationship Id="r2" Type="{rel}/slide" Target="slides/slide2.xml"/>'
        z.writestr('ppt/_rels/presentation.xml.rels', f'<Relationships>{items}</Relationships>')
        for slide, note in [(9, 7), (2, 19)] + ([(1, 42)] if all_notes else []):
            z.writestr(f'ppt/slides/_rels/slide{slide}.xml.rels', f'<Relationships><Relationship Id="n1" Type="{rel}/notesSlide" Target="../notesSlides/notesSlide{note}.xml"/></Relationships>')
        extra = '<p:sp><p:nvSpPr><p:nvPr><p:ph type="sldNum"/></p:nvPr></p:nvSpPr><p:txBody><a:p><a:r><a:t>999</a:t></a:r></a:p></p:txBody></p:sp>'
        z.writestr('ppt/notesSlides/notesSlide7.xml', notes('<a:p><a:r><a:t>最初の原稿</a:t></a:r></a:p><a:p><a:r><a:t>二行目 &amp; 続き</a:t></a:r></a:p>', extra))
        z.writestr('ppt/notesSlides/notesSlide19.xml', notes('<a:p><a:r><a:t>最後の原稿</a:t></a:r></a:p>'))
        if all_notes:
            z.writestr('ppt/notesSlides/notesSlide42.xml', notes('<a:p><a:r><a:t>二枚目</a:t></a:r></a:p>'))

write_fixture('reordered.pptx')
write_fixture('broken.pptx', broken=True)
write_fixture('sample.pptx', all_notes=True)
