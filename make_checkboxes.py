"""
make_checkboxes.py
Replaces [ ], [~], [x] list markers in TESTING_CHECKLIST.docx
with real clickable Word checkbox content controls.
"""

import re
from lxml import etree
from docx import Document

DOCX_PATH = r'c:\dev\RestiView2\restiview\TESTING_CHECKLIST.docx'
OUT_PATH   = r'c:\dev\RestiView2\restiview\TESTING_CHECKLIST.docx'

W_NS  = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
W14_NS = 'http://schemas.microsoft.com/office/word/2010/wordml'

MARKER_RE = re.compile(r'^\s*\[([ ~xX])\]\s*')

# Pandoc strips [ ] markers and styles list items as 'Compact'
CHECKBOX_STYLES = {'Compact', 'List Paragraph', 'List Bullet'}


def make_checkbox_sdt(checked: bool) -> etree._Element:
    checked_val = '1' if checked else '0'
    char        = '\u2611' if checked else '\u2610'   # ☑ / ☐
    xml = (
        f'<w:sdt'
        f' xmlns:w="{W_NS}"'
        f' xmlns:w14="{W14_NS}">'
          f'<w:sdtPr>'
            f'<w14:checkbox>'
              f'<w14:checked w14:val="{checked_val}"/>'
              f'<w14:checkedState w14:val="2612" w14:font="MS Gothic"/>'
              f'<w14:uncheckedState w14:val="2610" w14:font="MS Gothic"/>'
            f'</w14:checkbox>'
          f'</w:sdtPr>'
          f'<w:sdtContent>'
            f'<w:r>'
              f'<w:rPr>'
                f'<w:rFonts w:ascii="MS Gothic" w:hAnsi="MS Gothic" w:hint="default"/>'
              f'</w:rPr>'
              f'<w:t>{char}</w:t>'
            f'</w:r>'
          f'</w:sdtContent>'
        f'</w:sdt>'
    )
    return etree.fromstring(xml)


def process_paragraph(para) -> None:
    """Insert an unchecked checkbox SDT at the start of the paragraph."""
    p_elem   = para._element
    checkbox = make_checkbox_sdt(checked=False)

    # Space run after the checkbox
    space_xml = (
        f'<w:r xmlns:w="{W_NS}">'
          f'<w:t xml:space="preserve"> </w:t>'
        f'</w:r>'
    )
    space_run = etree.fromstring(space_xml)

    # Insert before the first w:r / w:sdt / w:hyperlink child
    first_run = None
    for child in p_elem:
        if child.tag in (f'{{{W_NS}}}r', f'{{{W_NS}}}sdt', f'{{{W_NS}}}hyperlink'):
            first_run = child
            break

    if first_run is not None:
        idx = list(p_elem).index(first_run)
        p_elem.insert(idx, space_run)
        p_elem.insert(idx, checkbox)
    else:
        p_elem.append(checkbox)
        p_elem.append(space_run)


def main():
    doc = Document(DOCX_PATH)

    count = 0
    for para in doc.paragraphs:
        if para.style.name in CHECKBOX_STYLES and para.text.strip():
            process_paragraph(para)
            count += 1

    doc.save(OUT_PATH)
    print(f'Done — converted {count} paragraphs to checkboxes in {OUT_PATH}')


if __name__ == '__main__':
    main()
