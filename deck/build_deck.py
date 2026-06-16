#!/usr/bin/env python3
"""
MedicoScope — finale pitch deck generator.
Theme: premium sakura (cherry-blossom) LIGHT theme.
Output: deck/MedicoScope_Aegis.pptx  (16:9, <=15 slides)

Run:  python deck/build_deck.py
"""
import math
from pptx import Presentation
from pptx.util import Inches, Pt, Emu
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR
from pptx.enum.shapes import MSO_SHAPE
from pptx.enum.text import MSO_AUTO_SIZE
from pptx.oxml.ns import qn

# ─────────────────────────────────────────────────────────────────────────────
# THEME — sakura light
# ─────────────────────────────────────────────────────────────────────────────
EMU_W, EMU_H = Inches(13.333), Inches(7.5)  # 16:9

# Palette
INK        = RGBColor(0x33, 0x2A, 0x2E)   # deep plum-charcoal text
INK_SOFT   = RGBColor(0x6E, 0x60, 0x66)   # secondary text
BG         = RGBColor(0xFF, 0xFB, 0xFC)   # near-white blush
BG_PANEL   = RGBColor(0xFF, 0xFF, 0xFF)   # card white
BLOSSOM    = RGBColor(0xF7, 0x9C, 0xB4)   # sakura pink (primary)
BLOSSOM_DK = RGBColor(0xE3, 0x6B, 0x8E)   # deep rose (accent)
BLUSH      = RGBColor(0xFC, 0xE4, 0xEC)   # pale petal fill
BLUSH_2    = RGBColor(0xFB, 0xD0, 0xDE)   # mid petal
LEAF       = RGBColor(0x7E, 0xA6, 0x8C)   # muted sage (success/secondary)
GOLD       = RGBColor(0xE8, 0xB4, 0x6B)   # warm amber (highlight)
SKY        = RGBColor(0x8F, 0xB8, 0xD6)   # soft sky (tech accent)
RED_SOFT   = RGBColor(0xE2, 0x6D, 0x6D)   # gentle red (RED-gate)
GREEN_SOFT = RGBColor(0x7E, 0xC0, 0x8F)
AMBER_SOFT = RGBColor(0xF0, 0xB4, 0x5C)
LINE       = RGBColor(0xF1, 0xD9, 0xE1)   # hairline divider

FONT_H = "Georgia"          # elegant serif for headings (sakura/editorial feel)
FONT_B = "Segoe UI"         # clean sans for body

prs = Presentation()
prs.slide_width = EMU_W
prs.slide_height = EMU_H
BLANK = prs.slide_layouts[6]


# ─────────────────────────────────────────────────────────────────────────────
# Low-level helpers
# ─────────────────────────────────────────────────────────────────────────────
def _solid(shape, color):
    shape.fill.solid()
    shape.fill.fore_color.rgb = color
    shape.line.fill.background()


def _noline(shape):
    shape.line.fill.background()


def _hex(c):
    return '%02X%02X%02X' % (c[0], c[1], c[2])


def grad_fill(sp, c1, c2, angle=90):
    """Schema-correct linear gradient via the shape's native gradient API,
    then recolour the two stops. Avoids hand-built XML ordering bugs."""
    try:
        sp.fill.gradient()
        stops = sp.fill.gradient_stops
        stops[0].position = 0.0
        stops[0].color.rgb = c1
        stops[1].position = 1.0
        stops[1].color.rgb = c2
        try:
            sp.fill.gradient_angle = angle
        except Exception:
            pass
    except Exception:
        sp.fill.solid()
        sp.fill.fore_color.rgb = c1
    sp.line.fill.background()
    sp.shadow.inherit = False


def slide(grad=False):
    s = prs.slides.add_slide(BLANK)
    bg = s.shapes.add_shape(MSO_SHAPE.RECTANGLE, 0, 0, EMU_W, EMU_H)
    if grad:
        grad_fill(bg, RGBColor(0xFF, 0xFF, 0xFF), RGBColor(0xFD, 0xF1, 0xF5), angle=120)
    else:
        _solid(bg, BG)
    bg.shadow.inherit = False
    return s


def rect(s, x, y, w, h, color, shape=MSO_SHAPE.ROUNDED_RECTANGLE, line=None, line_w=1.0):
    sp = s.shapes.add_shape(shape, Inches(x), Inches(y), Inches(w), Inches(h))
    sp.fill.solid()
    sp.fill.fore_color.rgb = color
    if line is None:
        sp.line.fill.background()
    else:
        sp.line.color.rgb = line
        sp.line.width = Pt(line_w)
    sp.shadow.inherit = False
    try:
        sp.adjustments[0] = 0.08
    except Exception:
        pass
    return sp


def soft_shadow(sp):
    """Apply a subtle drop shadow.

    NOTE: hand-injecting <a:effectLst> is what corrupted the file for
    PowerPoint (strict OOXML schema/ordering). We use python-pptx's native
    shadow object instead — it inserts the element in the schema-valid place.
    """
    try:
        sp.shadow.inherit = False
        from pptx.oxml.ns import qn as _qn
        el = sp._element.spPr
        # Remove any existing effectLst, then RE-APPEND it as the LAST child of
        # spPr. In CT_ShapeProperties the schema order is
        #   xfrm · geometry · fill · ln · effectLst · scene3d · sp3d · extLst
        # python-pptx never emits scene3d/sp3d/extLst on these shapes, so making
        # effectLst the final element is always schema-valid — regardless of
        # whether the fill is solidFill or gradFill. (The earlier addnext(ln)
        # approach mis-ordered gradient shapes → PowerPoint repair prompt.)
        for old in el.findall(_qn('a:effectLst')):
            el.remove(old)
        eff = el.makeelement(_qn('a:effectLst'), {})
        sh = eff.makeelement(_qn('a:outerShdw'), {
            'blurRad': '80000', 'dist': '30000', 'dir': '5400000', 'rotWithShape': '0'})
        clr = sh.makeelement(_qn('a:srgbClr'), {'val': 'E3A9BC'})
        alpha = clr.makeelement(_qn('a:alpha'), {'val': '32000'})
        clr.append(alpha); sh.append(clr); eff.append(sh)
        el.append(eff)  # guaranteed last → valid
    except Exception:
        pass  # decorative only — never break the build over a shadow


def card(s, x, y, w, h, color=BG_PANEL, shadow=True, line=LINE):
    sp = rect(s, x, y, w, h, color, MSO_SHAPE.ROUNDED_RECTANGLE, line=line, line_w=1.0)
    try:
        sp.adjustments[0] = 0.06
    except Exception:
        pass
    if shadow:
        soft_shadow(sp)
    return sp


def text(s, x, y, w, h, runs, align=PP_ALIGN.LEFT, anchor=MSO_ANCHOR.TOP,
         space_after=4, line_spacing=1.0):
    """runs: list of (string, size, color, bold, font) or list of paragraphs (each a list of runs)."""
    tb = s.shapes.add_textbox(Inches(x), Inches(y), Inches(w), Inches(h))
    tf = tb.text_frame
    tf.word_wrap = True
    tf.vertical_anchor = anchor
    tf.auto_size = MSO_AUTO_SIZE.NONE
    # Normalize: if first element is a tuple -> single paragraph
    paragraphs = runs if (runs and isinstance(runs[0], list)) else [runs]
    for i, para in enumerate(paragraphs):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.alignment = align
        p.space_after = Pt(space_after)
        p.line_spacing = line_spacing
        for (txt, size, color, bold, font) in para:
            r = p.add_run()
            r.text = txt
            r.font.size = Pt(size)
            r.font.color.rgb = color
            r.font.bold = bold
            r.font.name = font
    return tb


def R(txt, size, color=INK, bold=False, font=FONT_B):
    return (txt, size, color, bold, font)


# ── Premium diagram primitives ───────────────────────────────────────────────
def glass(s, x, y, w, h, tint=BG_PANEL, line=LINE, shadow=True, radius=0.06):
    """Glassmorphism panel — soft translucent-feel card."""
    sp = rect(s, x, y, w, h, tint, MSO_SHAPE.ROUNDED_RECTANGLE, line=line, line_w=1.0)
    try:
        sp.adjustments[0] = radius
    except Exception:
        pass
    if shadow:
        soft_shadow(sp)
    return sp


def grad_card(s, x, y, w, h, c1, c2, angle=120, shadow=True, radius=0.07):
    sp = s.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(x), Inches(y), Inches(w), Inches(h))
    grad_fill(sp, c1, c2, angle)
    try:
        sp.adjustments[0] = radius
    except Exception:
        pass
    if shadow:
        soft_shadow(sp)
    return sp


def status_pill(s, x, y, live=True, size=9):
    """Tiny LIVE / ROADMAP status pill — the honesty marker."""
    col = LEAF if live else INK_SOFT
    fill = RGBColor(0xE8, 0xF1, 0xEA) if live else RGBColor(0xF0, 0xEC, 0xEE)
    label = "● LIVE" if live else "○ ROADMAP"
    w = 0.85 if live else 1.15
    c = rect(s, x, y, w, 0.3, fill, MSO_SHAPE.ROUNDED_RECTANGLE)
    try:
        c.adjustments[0] = 0.5
    except Exception:
        pass
    text(s, x, y, w, 0.3, [R(label, size, col, True)], align=PP_ALIGN.CENTER, anchor=MSO_ANCHOR.MIDDLE)


def agent_node(s, cx, cy, d, label, sub, color, live=True, glyph=None):
    """A circular agent node for the ecosystem diagram."""
    node = s.shapes.add_shape(MSO_SHAPE.OVAL, Inches(cx - d / 2), Inches(cy - d / 2), Inches(d), Inches(d))
    if live:
        grad_fill(node, color, _tint(color, 0.35))
    else:
        _solid(node, RGBColor(0xF3, 0xEC, 0xEF))
        node.line.color.rgb = color
        node.line.width = Pt(1.5)
        node.line.dash_style = None
    node.shadow.inherit = False
    if live:
        soft_shadow(node)
    tcol = BG_PANEL if live else INK
    text(s, cx - d / 2, cy - d / 2 + 0.04, d, d,
         [[R(label, 10.5, tcol, True, FONT_B)], [R(sub, 8, (BLUSH if live else INK_SOFT))]],
         align=PP_ALIGN.CENTER, anchor=MSO_ANCHOR.MIDDLE, line_spacing=0.95, space_after=1)
    return (cx, cy)


def _tint(c, f):
    """Lighten color c toward white by fraction f."""
    return RGBColor(int(c[0] + (255 - c[0]) * f),
                    int(c[1] + (255 - c[1]) * f),
                    int(c[2] + (255 - c[2]) * f))


def connect(s, p1, p2, color=LINE, w=1.5):
    """Schema-safe line (rotated thin rectangle) between two (x,y) points in inches."""
    import math as _m
    (x1, y1), (x2, y2) = p1, p2
    midx, midy = (x1 + x2) / 2, (y1 + y2) / 2
    length = _m.hypot(x2 - x1, y2 - y1)
    ln = s.shapes.add_shape(MSO_SHAPE.RECTANGLE, Inches(midx - length / 2), Inches(midy - w / 144.0),
                            Inches(length), Inches(w / 72.0))
    _solid(ln, color)
    ln.rotation = _m.degrees(_m.atan2(y2 - y1, x2 - x1))
    ln.shadow.inherit = False
    # send to back so nodes sit on top
    sp = ln._element
    sp.getparent().remove(sp)
    s.shapes._spTree.insert(2, sp)
    return ln


def arrow(s, x, y, w, h, color=BLOSSOM, shape=MSO_SHAPE.RIGHT_ARROW):
    a = s.shapes.add_shape(shape, Inches(x), Inches(y), Inches(w), Inches(h))
    _solid(a, color)
    return a


def petal(s, cx, cy, size, color, rot=0):
    """A single cherry-blossom petal (teardrop) as a rotated oval-ish shape."""
    p = s.shapes.add_shape(MSO_SHAPE.TEAR, Inches(cx - size / 2), Inches(cy - size / 2),
                           Inches(size), Inches(size))
    _solid(p, color)
    p.shadow.inherit = False
    p.rotation = rot
    return p


def blossom(s, cx, cy, size, color=BLUSH_2, center=GOLD):
    """A 5-petal cherry blossom flower."""
    for k in range(5):
        petal(s, cx, cy, size, color, rot=k * 72)
    c = s.shapes.add_shape(MSO_SHAPE.OVAL, Inches(cx - size * 0.12), Inches(cy - size * 0.12),
                           Inches(size * 0.24), Inches(size * 0.24))
    _solid(c, center)
    c.shadow.inherit = False


def scatter_blossoms(s, specs):
    """specs: list of (cx, cy, size, color)."""
    for (cx, cy, sz, col) in specs:
        blossom(s, cx, cy, sz, col)


def branch_corner(s, corner="tr"):
    """A decorative blossom cluster in a corner — premium sakura accent."""
    if corner == "tr":
        scatter_blossoms(s, [
            (12.6, 0.4, 0.7, BLUSH_2), (12.0, 0.9, 0.5, BLUSH),
            (12.9, 1.2, 0.42, BLOSSOM), (11.5, 0.5, 0.34, BLUSH),
            (12.4, 1.7, 0.3, BLUSH_2),
        ])
    elif corner == "bl":
        scatter_blossoms(s, [
            (0.5, 7.05, 0.6, BLUSH_2), (1.1, 6.7, 0.42, BLUSH),
            (0.3, 6.4, 0.32, BLOSSOM), (1.5, 7.15, 0.3, BLUSH_2),
        ])


def chip(s, x, y, w, label, color=BLUSH, txt_color=BLOSSOM_DK, size=11, h=0.42):
    c = rect(s, x, y, w, h, color, MSO_SHAPE.ROUNDED_RECTANGLE)
    try:
        c.adjustments[0] = 0.5
    except Exception:
        pass
    text(s, x, y, w, h, [R(label, size, txt_color, True)],
         align=PP_ALIGN.CENTER, anchor=MSO_ANCHOR.MIDDLE)
    return c


def kicker(s, x, y, txt, color=BLOSSOM_DK):
    """Small uppercase label above a heading."""
    text(s, x, y, 8, 0.3, [R(txt.upper(), 12, color, True, FONT_B)])


def page_num(s, n):
    text(s, 12.5, 7.05, 0.7, 0.3, [R(f"{n:02d} / 15", 9, INK_SOFT)], align=PP_ALIGN.RIGHT)
    # tiny brand mark
    text(s, 0.55, 7.04, 4, 0.3, [R("MedicoScope · Aegis", 9, INK_SOFT, True)])


def icon_badge(s, x, y, d, color, glyph, glyph_color=BG_PANEL, gsize=18):
    sp = s.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(x), Inches(y), Inches(d), Inches(d))
    _solid(sp, color)
    sp.shadow.inherit = False
    try:
        sp.adjustments[0] = 0.3
    except Exception:
        pass
    text(s, x, y, d, d, [R(glyph, gsize, glyph_color, True)],
         align=PP_ALIGN.CENTER, anchor=MSO_ANCHOR.MIDDLE)


def divider(s, x, y, w, color=BLOSSOM):
    ln = rect(s, x, y, w, 0.045, color, MSO_SHAPE.ROUNDED_RECTANGLE)
    return ln


# Placeholder for build-out (slides appended below in build_slides.py-style sections)
if __name__ == "__main__":
    # Slides are constructed in build_slides() imported lazily to keep this file
    # focused; if run directly we just emit the toolkit smoke-test deck.
    import os
    from deck_slides import build_all
    build_all(prs, globals())
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "MedicoScope_Aegis.pptx")
    prs.save(out)
    print("Saved", out, "with", len(prs.slides._sldIdLst), "slides")
