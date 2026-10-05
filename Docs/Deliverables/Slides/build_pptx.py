# Builds Sentinel_Presentation.pptx. Run make_backdrops.py and make_equations.py first.
import os
from pptx import Presentation
from pptx.util import Inches, Pt
from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_SHAPE, MSO_CONNECTOR
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR
from pptx.chart.data import CategoryChartData
from pptx.enum.chart import XL_CHART_TYPE
from pptx.oxml.ns import qn
from lxml import etree
from PIL import Image, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
IMG = os.path.join(HERE, 'images') + '/'
EQ = os.path.join(HERE, 'equation_images') + '/'
BD = os.path.join(HERE, 'backdrops') + '/'
INK = RGBColor(0x1E, 0x29, 0x3B); TEAL = RGBColor(0x0F, 0x8F, 0x85); MINT = RGBColor(0xE6, 0xF4, 0xF2)
BRIGHT = RGBColor(0x2D, 0xD4, 0xBF); AMBER = RGBColor(0xF5, 0x9E, 0x0B); SLATE = RGBColor(0x64, 0x74, 0x8B)
WHITE = RGBColor(255, 255, 255); HAIR = RGBColor(0xDD, 0xE5, 0xEE); LIGHT = RGBColor(0xC7, 0xD2, 0xE0)
FONT = 'Calibri'; HEAD = 'Georgia'
SIZES = {l.split()[0]: (float(l.split()[1]), float(l.split()[2])) for l in open(EQ + 'sizes.txt').read().splitlines()}
EQ_SCALE = 1.5  # natural equation images are 14 pt; 1.5 makes them read as about 21 pt
MET = lambda pt, b=False: ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial Bold.ttf' if b else '/System/Library/Fonts/Supplemental/Arial.ttf', int(pt * 10))
warnings = []

prs = Presentation(); prs.slide_width = Inches(13.333); prs.slide_height = Inches(7.5)
blank = prs.slide_layouts[6]
count = [0]


def est_lines(text, w_in, pt, bold=False):
    f = MET(pt, bold); maxw = w_in * 72 * 10; lines = 0
    for para in text.split('\n'):
        cur = ''; n = 1
        for wd in para.split(' '):
            t = (cur + ' ' + wd).strip()
            if f.getlength(t) > maxw * 0.93 and cur: n += 1; cur = wd
            else: cur = t
        lines += n
    return lines


def shadow(shape, blur=9, dist=2, alpha=16):
    spPr = shape._element.spPr
    for e in spPr.findall(qn('a:effectLst')): spPr.remove(e)
    eff = etree.SubElement(spPr, qn('a:effectLst'))
    sh = etree.SubElement(eff, qn('a:outerShdw'), blurRad=str(int(Pt(blur))), dist=str(int(Pt(dist))), dir='5400000', algn='t', rotWithShape='0')
    c = etree.SubElement(sh, qn('a:srgbClr'), val='0B1220'); etree.SubElement(c, qn('a:alpha'), val=str(alpha * 1000))


def textbox(slide, x, y, w, h, paras, size=18, color=INK, bold=False, align=PP_ALIGN.LEFT, font=FONT, anchor=MSO_ANCHOR.TOP, bullets=False, space=4, italic=False, line=1.0, check=True):
    tb = slide.shapes.add_textbox(Inches(x), Inches(y), Inches(w), Inches(h)); tf = tb.text_frame
    tf.word_wrap = True; tf.margin_left = tf.margin_right = Inches(0.04); tf.margin_top = tf.margin_bottom = Inches(0.02); tf.vertical_anchor = anchor
    total = 0
    for i, p in enumerate(paras):
        para = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        para.alignment = align; para.space_after = Pt(space); para.line_spacing = line
        runs = [(p, {})] if isinstance(p, str) else p
        plain = ''
        for t, o in runs:
            r = para.add_run(); r.text = t; plain += t
            r.font.name = o.get('font', font); r.font.size = Pt(o.get('size', size)); r.font.bold = o.get('bold', bold); r.font.italic = o.get('italic', italic)
            r.font.color.rgb = o.get('color', color)
        if bullets:
            pPr = para._p.get_or_add_pPr(); pPr.set('marL', str(int(Inches(0.3)))); pPr.set('indent', str(-int(Inches(0.3))))
            bc = etree.SubElement(pPr, qn('a:buClr')); etree.SubElement(bc, qn('a:srgbClr'), val='0F8F85')
            etree.SubElement(pPr, qn('a:buChar'), char='▪')
        total += est_lines(plain, w - 0.1 - (0.3 if bullets else 0), size, bold) * size * 1.2 * line / 72 + space / 72
    if check and total > h + 0.05: warnings.append(f'slide {count[0]}: overflow {total:.2f}>{h:.2f} :: {str(paras)[:40]}')
    return tb


def rect(slide, x, y, w, h, fill=MINT, line=None, shape=MSO_SHAPE.ROUNDED_RECTANGLE, radius=0.06, shadowed=False):
    s = slide.shapes.add_shape(shape, Inches(x), Inches(y), Inches(w), Inches(h))
    s.fill.solid(); s.fill.fore_color.rgb = fill
    if line is None: s.line.fill.background()
    else: s.line.color.rgb = line; s.line.width = Pt(0.75)
    if shape == MSO_SHAPE.ROUNDED_RECTANGLE: s.adjustments[0] = radius
    if shadowed: shadow(s)
    else: s.shadow.inherit = False
    return s


def picture(slide, path, x, y, w=None, h=None, border=True, shadowed=False):
    im = Image.open(path); ar = im.size[1] / im.size[0]
    if w is not None and h is None: h = w * ar
    elif h is not None and w is None: w = h / ar
    p = slide.shapes.add_picture(path, Inches(x), Inches(y), Inches(w), Inches(h))
    if border: p.line.color.rgb = RGBColor(255, 255, 255); p.line.width = Pt(2.25)
    if shadowed: shadow(p, blur=10, dist=3, alpha=24)
    return p, w, h


def eq(slide, name, x, y, boxw, boxh=None, scale=EQ_SCALE, align='center'):
    """Place an equation at its natural size times scale, shrunk to fit boxw (and boxh); returns the drawn height."""
    w0, h0 = SIZES[name]; w, h = w0 * scale, h0 * scale
    k = min(1.0, boxw / w, (boxh / h) if boxh else 1.0); w, h = w * k, h * k
    xx = x + (boxw - w) / 2 if align == 'center' else x
    slide.shapes.add_picture(EQ + name + '.png', Inches(xx), Inches(y), Inches(w), Inches(h))
    return h


def panel(slide, x, y, w, h, label=None, accent=TEAL):
    rect(slide, x, y, w, h, fill=WHITE, line=HAIR, shadowed=True, radius=0.04)
    rect(slide, x, y + 0.12, 0.07, h - 0.24, fill=accent, shape=MSO_SHAPE.RECTANGLE)
    if label: textbox(slide, x + 0.25, y + 0.1, w - 0.4, 0.38, [label.upper()], size=12, bold=True, color=TEAL, check=False)


def eq_panel(slide, x, y, w, h, label, names, note=None, scale=None, gap=0.12, maxscale=2.5):
    """A card with a small label, equations scaled to fill the width (never above maxscale, never taller than the card), and an optional note."""
    panel(slide, x, y, w, h, label)
    top = y + 0.5; bottom = y + h - (0.7 if note else 0.12)
    avail = bottom - top
    scales = [min(maxscale, (w - 0.7) / SIZES[n][0]) for n in names]
    tall = sum(SIZES[n][1] * sc for n, sc in zip(names, scales)) + gap * (len(names) - 1)
    k = min(1.0, avail / tall)
    cy = top + max(0, (avail - tall * k) / 2)
    for n, sc in zip(names, scales):
        dh = eq(slide, n, x + 0.2, cy, w - 0.4, scale=sc * k); cy += dh + gap * k
    if note: textbox(slide, x + 0.25, y + h - 0.66, w - 0.4, 0.62, note.split('\n'), size=13, color=SLATE, anchor=MSO_ANCHOR.MIDDLE, space=1, check=False)


def card(slide, x, y, w, h, title, body, size=16, bullets=True):
    panel(slide, x, y, w, h, title)
    textbox(slide, x + 0.25, y + 0.5, w - 0.4, h - 0.58, body, size=size, bullets=bullets, space=3)


def new_slide(title=None):
    count[0] += 1
    s = prs.slides.add_slide(blank)
    s.shapes.add_picture(BD + 'content.jpg', 0, 0, prs.slide_width, prs.slide_height)
    if title is not None:
        s.shapes.add_picture(BD + 'header.jpg', 0, 0, prs.slide_width, Inches(0.95))
        rect(s, 0, 0.95, 13.333, 0.045, fill=BRIGHT, shape=MSO_SHAPE.RECTANGLE)
        rect(s, 0.55, 0.3, 0.1, 0.38, fill=AMBER, shape=MSO_SHAPE.RECTANGLE)
        textbox(s, 0.8, 0.13, 11.5, 0.7, [title], size=30, color=WHITE, bold=True, font=HEAD, anchor=MSO_ANCHOR.MIDDLE, check=False)
        textbox(s, 0.6, 7.1, 6, 0.3, ['Sentinel  ·  CSE 4102  ·  KUET'], size=10, color=SLATE, check=False)
        textbox(s, 11.8, 7.1, 1.3, 0.3, [f'{count[0]} / 10'], size=11, color=SLATE, align=PP_ALIGN.RIGHT, check=False)
    return s


def arrow(slide, x1, y1, x2, y2, color=TEAL, width=2):
    c = slide.shapes.add_connector(MSO_CONNECTOR.STRAIGHT, Inches(x1), Inches(y1), Inches(x2), Inches(y2))
    c.line.color.rgb = color; c.line.width = Pt(width)
    etree.SubElement(c.line._get_or_add_ln(), qn('a:tailEnd'), type='triangle')


def chevrons(slide, labels, x, y, w, h, size=13):
    n = len(labels); step = (w + 0.15 * (n - 1)) / n
    for i, t in enumerate(labels):
        s = slide.shapes.add_shape(MSO_SHAPE.PENTAGON if i == 0 else MSO_SHAPE.CHEVRON, Inches(x + i * (step - 0.15)), Inches(y), Inches(step), Inches(h))
        s.fill.solid(); s.fill.fore_color.rgb = MINT if i % 2 == 0 else RGBColor(0xCC, 0xEA, 0xE6); s.line.color.rgb = TEAL; s.line.width = Pt(1)
        s.adjustments[0] = 0.28; shadow(s, blur=5, dist=1, alpha=12)
        textbox(slide, x + i * (step - 0.15) + (0.1 if i == 0 else 0.28), y, step - 0.4, h, t.split('\n'), size=size, align=PP_ALIGN.CENTER, anchor=MSO_ANCHOR.MIDDLE, space=0, check=False, bold=True, color=INK)


def caption(slide, x, y, w, text):
    textbox(slide, x, y, w, 0.3, [text], size=12, color=SLATE, italic=True, align=PP_ALIGN.CENTER, check=False)


# ================= 1 cover
count[0] += 1
s = prs.slides.add_slide(blank)
s.shapes.add_picture(BD + 'cover.jpg', 0, 0, prs.slide_width, prs.slide_height)
textbox(s, 1.0, 0.75, 10.5, 0.4, ['KHULNA UNIVERSITY OF ENGINEERING & TECHNOLOGY   ·   CSE 4102'], size=13, color=LIGHT, check=False)
rect(s, 1.05, 1.25, 0.9, 0.05, fill=AMBER, shape=MSO_SHAPE.RECTANGLE)
textbox(s, 1.0, 1.55, 11, 1.6, ['Sentinel'], size=88, bold=True, color=WHITE, font=HEAD, check=False)
textbox(s, 1.0, 3.2, 11, 1.2, ['A Fully Procedural Game Engine', 'and Open-World Military Shooter'], size=30, color=RGBColor(0xE6, 0xFB, 0xF8), space=0, check=False)
textbox(s, 1.0, 4.55, 9, 0.9, ['Nothing is loaded from a model, image or sound file:', 'everything is generated from code and a seed.'], size=18, color=BRIGHT, italic=True, space=0, check=False)
textbox(s, 1.0, 6.45, 5.5, 0.8, [[('Md. Shifat Hasan', {'bold': True, 'color': WHITE, 'size': 19})], [('Roll 2107067  ·  4th Year 1st Term', {'color': LIGHT, 'size': 13})]], size=14, space=1, check=False)
textbox(s, 6.6, 6.45, 6.0, 0.8, [[('Instructors: Md Tajmilur Rahman, Md. Mubtashim Abrar Nihal', {'size': 13, 'color': LIGHT})], [('Computer Graphics and Image Processing Laboratory  ·  October 7, 2026', {'size': 13, 'color': LIGHT})]], size=13, align=PP_ALIGN.RIGHT, space=1, check=False)

# ================= 2 outline
s = new_slide('Outline')
items = ['Problem, objectives and architecture', 'Procedural shapes and textures', 'Transformations: creating and combining objects', 'Illumination models and light sources', 'The rendering pipeline: shadows, ambient, tone map', 'Results, verification and a bug fixed', 'Video tour of the project']
y = 1.4
for i, t in enumerate(items):
    rect(s, 0.7, y, 0.52, 0.52, fill=TEAL, shape=MSO_SHAPE.OVAL, shadowed=True)
    textbox(s, 0.7, y, 0.52, 0.52, [str(i + 1)], size=18, bold=True, color=WHITE, align=PP_ALIGN.CENTER, anchor=MSO_ANCHOR.MIDDLE, check=False)
    textbox(s, 1.45, y, 6.4, 0.52, [t], size=21, anchor=MSO_ANCHOR.MIDDLE, check=False)
    y += 0.79
p, w, h = picture(s, IMG + 'models.jpg', 8.0, 1.75, w=4.8, shadowed=True)
caption(s, 8.0, 1.75 + h + 0.08, 4.8, 'Six illumination models, one sphere each')
p, w2, h2 = picture(s, IMG + 'tank.jpg', 8.0, 1.75 + h + 0.55, w=2.3, shadowed=True)
p, w3, h3 = picture(s, IMG + 'truck.jpg', 10.5, 1.75 + h + 0.55, w=2.3, shadowed=True)
caption(s, 8.0, 1.75 + h + 0.55 + h2 + 0.08, 4.8, 'Objects are transformed primitives')

# ================= 3 problem + architecture
s = new_slide('1. Problem, objectives and architecture')
textbox(s, 0.6, 1.15, 6.6, 0.95, ['Can a complete, playable 3D game be made by code alone on a student laptop?'], size=21, bold=True)
card(s, 0.6, 2.15, 6.6, 1.35, 'Two hard limits', ['No model, image or precomputed data file', 'macOS OpenGL 4.1: no compute shaders'], size=17)
card(s, 0.6, 3.65, 6.6, 2.0, 'Objectives', ['Layered engine, downward dependencies', 'All content from code and seeds', 'Modern renderer and a playable game', 'Verified by tests and a 16.7 ms budget'], size=16)
panel(s, 0.6, 5.8, 12.2, 1.05, accent=AMBER)
textbox(s, 0.9, 5.88, 11.7, 0.9, [[('The game: ', {'bold': True, 'color': TEAL}), ('jeep, truck, carrier, tank and a helicopter you can drive; ladders and doors; stealth enemies; a five-objective mission (hack, destroy, rescue, extract); all sounds synthesised.', {})]], size=16)
layers = [('Game', 'mission, AI, vehicles, sound'), ('Render', 'deferred, lights, sky, post'), ('World', 'collision, terrain'), ('Procedural', 'noise, textures'), ('GPU', 'shaders, buffers'), ('Platform', 'window, input')]
y = 1.2
for i, (a, b) in enumerate(layers):
    shade = RGBColor(0xE8 - i * 14, 0xF7 - i * 9, 0xF4 - i * 8)
    r = rect(s, 7.7, y, 4.6, 0.62, fill=shade, line=TEAL, shadowed=True, radius=0.12)
    textbox(s, 7.85, y, 4.4, 0.62, [[(a + '  ', {'bold': True, 'color': TEAL}), (b, {})]], size=15, anchor=MSO_ANCHOR.MIDDLE, check=False)
    y += 0.7
arrow(s, 12.6, 1.25, 12.6, 5.2)
textbox(s, 7.5, 5.38, 5.2, 0.35, ['A lower layer never knows a higher one.'], size=13, color=SLATE, italic=True, align=PP_ALIGN.CENTER, check=False)

# ================= 4 procedural
s = new_slide('2. Procedural shapes and textures')
p, w, h = picture(s, IMG + 'noise_stages.png', 1.9, 1.15, w=9.5, shadowed=True, border=False)
caption(s, 1.9, 1.15 + h + 0.04, 9.5, 'gradient, fractal, warped, ridged and cellular noise')
y0 = 1.15 + h + 0.5
eq_panel(s, 0.6, y0, 6.0, 2.05, 'Fractal noise (tiles exactly)', ['fractal'], scale=1.45)
eq_panel(s, 0.6, y0 + 2.2, 6.0, 6.95 - (y0 + 2.2), 'Vertex push by a noise deformer', ['push'], scale=1.3)
textbox(s, 6.95, y0 + 0.1, 5.9, 3.7, ['18 recipes → 22 materials, baked once at 1024²', 'Scharr filter turns height into bumps; crevices darken', 'Objects are tables of primitives plus noise deformers', 'Soldiers: skeletons with two-bone IK legs'], size=20, bullets=True, space=11)

# ================= 5 transformations
s = new_slide('3. Transformations: creating and combining objects')
chevrons(s, ['Primitive\nmesh', 'Deformers\n(own space)', 'M_part\nscale, turn, move', 'Merge by\nmaterial', 'M_world\ninstances', 'V then P\nto screen'], 0.6, 1.15, 12.2, 0.85, size=14)
eq_panel(s, 0.6, 2.2, 6.2, 2.4, 'One part: scale, then turn, then move', ['mpart'], note='Right to left: stretched, turned about its own centre, moved last.\nExample: (1,0,0) → S(2,1,1) → R_y 90° → T(5,0,0) = (5, 0, −2)', scale=1.6)
eq_panel(s, 0.6, 4.75, 6.2, 2.2, 'Normals use the inverse transpose', ['nmat'], note='S = diag(2,1,1): correct (0.447, 0.894, 0); naive (0.894, 0.447, 0) is wrong', scale=1.5)
eq_panel(s, 7.05, 2.2, 5.75, 1.95, 'Rotation about y', ['ry'], scale=1.55)
eq_panel(s, 7.05, 4.3, 5.75, 1.3, 'Hierarchy: products down the chain', ['mgun'], scale=1.4)
eq_panel(s, 7.05, 5.75, 5.75, 1.2, 'World to screen', ['clip'], scale=1.5)

# ================= 6 illumination
s = new_slide('4. Illumination models and light sources')
eq_panel(s, 0.6, 1.1, 8.8, 1.3, 'Direct light + ambient + emission', ['sum'])
textbox(s, 9.6, 1.35, 3.3, 0.9, ['f = illumination model','att = falloff   sh = shadow'], size=13, color=SLATE, italic=True, space=0, check=False)
panel(s, 0.6, 2.55, 7.0, 4.4)
rows = [('Lambert', 'lambert'), ('Phong', 'phong'), ('Blinn–Phong', 'blinn'), ('Oren–Nayar', 'oren'), ('Cook–Torrance', 'ct2'), ('Subsurface', 'sss')]
y = 2.62
for i, (name, img) in enumerate(rows):
    textbox(s, 0.85, y + 0.06, 2.1, 0.55, [name], size=16, bold=True, color=TEAL, anchor=MSO_ANCHOR.MIDDLE, check=False)
    eq(s, img, 3.0, y + 0.05, 4.4, 0.58, scale=2.0, align='left')
    if i < len(rows) - 1:
        rect(s, 0.85, y + 0.69, 6.5, 0.012, fill=HAIR, shape=MSO_SHAPE.RECTANGLE)
    y += 0.71
p, w, h = picture(s, IMG + 'models.jpg', 7.9, 2.55, w=4.9, shadowed=True)
caption(s, 7.9, 2.55 + h + 0.03, 4.9, 'Lambert · Phong · Blinn–Phong · Oren–Nayar · Cook–Torrance · Subsurface')
y2 = 2.55 + h + 0.42
panel(s, 7.9, y2, 4.9, 6.95 - y2, 'Light sources')
textbox(s, 8.15, y2 + 0.48, 4.5, 1.45, ['Directional: sun, moon', 'Point: lamps, flashes', 'Spot: floodlights (cone)', 'Area: 4×4 point samples'], size=15, bullets=True, space=2)
eq(s, 'att', 8.0, 6.95 - 0.85, 4.7, 0.75, scale=2.0)

# ================= 7 rendering pipeline
s = new_slide('5. The rendering pipeline: shadows, ambient, tone map')
chevrons(s, ['Sky\ntable', 'Shadows\n3 cascades', 'Geometry\nG-buffer', 'SSAO', 'Lighting,\nreflect, fog', 'Smoke,\nfire', 'Bloom, ACES,\nFXAA'], 0.6, 1.15, 12.2, 0.85, size=13)
textbox(s, 0.6, 2.2, 6.9, 0.9, [[('Deferred shading: ', {'bold': True, 'color': TEAL}), ('store colour, normal, shininess and depth first, then light each pixel once.', {})]], size=17)
eq_panel(s, 0.6, 3.15, 6.9, 1.9, 'Cascaded shadow maps  (λ = 0.75, N = 3, n = 0.1 m, r = 100 m)', ['csm'], note='Cuts at 9.1, 24.2, 100 m · normal-offset lookup · 8 rotated PCF taps', scale=1.45)
eq_panel(s, 0.6, 5.2, 6.9, 1.75, 'Fog and tone map', ['fog', 'aces'], scale=1.2, gap=0.1)
p, w, h = picture(s, IMG + 'dusk.jpg', 7.85, 2.2, w=5.0, shadowed=True)
caption(s, 7.85, 2.2 + h + 0.06, 5.0, 'Dusk: sun, sky, haze, shadows')
textbox(s, 7.85, 2.2 + h + 0.55, 5.0, 1.5, ['Sun, moon, lamps, cascaded shadows, SSAO, screen-space reflections, bloom and FXAA. Ambient = sky diffuse + split-sum specular, times SSAO.'], size=15)

# ================= 8 results + challenge
s = new_slide('6. Results, verification and a bug fixed')
panel(s, 0.6, 1.15, 6.3, 3.05)
cd = CategoryChartData(); cd.categories = ['Sky table', 'Post', 'SSAO', 'Shadows', 'Lighting', 'Geometry']
cd.add_series('GPU ms', (0.02, 1.21, 1.20, 1.58, 2.79, 4.11))
gf = s.shapes.add_chart(XL_CHART_TYPE.BAR_CLUSTERED, Inches(0.8), Inches(1.2), Inches(6.0), Inches(2.95), cd); ch = gf.chart
ch.has_legend = False; ch.has_title = True; ch.chart_title.text_frame.text = 'GPU time per pass (ms)'
r0 = ch.chart_title.text_frame.paragraphs[0].runs[0]; r0.font.size = Pt(13); r0.font.bold = True; r0.font.color.rgb = INK
pl = ch.plots[0]; pl.gap_width = 50; pl.has_data_labels = True; pl.data_labels.font.size = Pt(11); pl.data_labels.number_format = '0.00'; pl.data_labels.number_format_is_linked = False
pl.series[0].format.fill.solid(); pl.series[0].format.fill.fore_color.rgb = TEAL
ch.category_axis.tick_labels.font.size = Pt(12); ch.value_axis.tick_labels.font.size = Pt(10); ch.value_axis.has_major_gridlines = False
textbox(s, 0.6, 4.3, 6.3, 0.45, [[('10.9 ms', {'bold': True, 'color': TEAL}), (' of the 16.7 ms budget at 1080p', {})]], size=19)
rows = [('Verification', 'Count'), ('Unit tests (13 packages)', '281'), ('TextureCheck (exact tiling)', '8,318'), ('RenderCheck (lighting probes)', '318,567'), ('GpuCheck', '30'), ('Playthroughs, 5/5 objectives', '2')]
tshape = s.shapes.add_table(len(rows), 2, Inches(0.6), Inches(4.85), Inches(6.3), Inches(2.1))
tbl = tshape.table
tbl.columns[0].width = Inches(4.7); tbl.columns[1].width = Inches(1.6)
for r, (a_, b_) in enumerate(rows):
    for c, t in enumerate((a_, b_)):
        cell = tbl.cell(r, c); cell.text = t; para = cell.text_frame.paragraphs[0]; para.runs[0].font.size = Pt(14); para.runs[0].font.name = FONT
        para.alignment = PP_ALIGN.RIGHT if c == 1 else PP_ALIGN.LEFT
        cell.margin_top = cell.margin_bottom = Inches(0.02)
        cell.fill.solid(); cell.fill.fore_color.rgb = TEAL if r == 0 else (MINT if r % 2 == 0 else WHITE)
        para.runs[0].font.color.rgb = WHITE if r == 0 else INK; para.runs[0].font.bold = (r == 0)
    tbl.rows[r].height = Inches(0.35)
textbox(s, 7.2, 1.15, 5.6, 1.05, [[('Bug: a vertical line at night. ', {'bold': True, 'color': TEAL}), ('Fog sampled the whole sky, so one horizon star streaked a column. Fix: fog uses the smooth atmosphere only.', {})]], size=15)
p, w, h = picture(s, IMG + 'gate_night_bug.jpg', 7.2, 2.3, w=2.72, shadowed=True)
p, w, h = picture(s, IMG + 'gate_night.jpg', 10.08, 2.3, w=2.72, shadowed=True)
caption(s, 7.2, 2.3 + h + 0.04, 2.72, 'Before'); caption(s, 10.08, 2.3 + h + 0.04, 2.72, 'After')
card(s, 7.2, 4.5, 5.6, 2.45, 'Limits and future work', ['Blocky primitive models; no true global illumination; lumpy foliage', 'Leaf cards, screen-space GI, point-light shadows, multiplayer', 'Take-away: most "art" is a few simple ideas, applied consistently and tested'], size=14)

# ================= 9 video (empty on purpose)
s = new_slide('7. Video tour of the project')

# ================= 10 references + thanks
s = new_slide('References')
refs = ['[1] K. Perlin, "Improving noise," ACM TOG, 21(3), 2002.', '[2] S. Worley, "A cellular texture basis function," SIGGRAPH, 1996.', '[3] R. Cook, K. Torrance, "A reflectance model for computer graphics," ACM TOG, 1(1), 1982.', '[4] B. Walter et al., "Microfacet models for refraction through rough surfaces," EGSR, 2007.', '[5] B. Karis, "Real shading in Unreal Engine 4," SIGGRAPH Course, 2013.', '[6] S. Hillaire, "A scalable and production ready sky and atmosphere rendering technique," CGF, 39(4), 2020.', '[7] R. Dimitrov, "Cascaded shadow maps," NVIDIA, 2007.', '[8] M. Oren, S. Nayar, "Generalization of Lambert\'s reflectance model," SIGGRAPH, 1994.',
        '[9] K. Narkowicz, "ACES filmic tone mapping curve," 2016.', '[10] J. Jimenez, "Next generation post processing in Call of Duty: Advanced Warfare," SIGGRAPH, 2014.', '[11] T. Lottes, "FXAA," NVIDIA, 2009.', '[12] M. Segal, K. Akeley, The OpenGL Graphics System, v4.1, Khronos, 2010.', '[13] I. Quilez, "Domain warping," iquilezles.org.', '[14] S. Hargreaves, M. Harris, "Deferred shading," NVIDIA, GDC 2004.', '[15] H. Scharr, "Optimal operators in digital image processing," Ph.D., Heidelberg, 2000.', '[16] T. Akenine-Möller et al., Real-Time Rendering, 4th ed., CRC Press, 2018.']
textbox(s, 0.6, 1.15, 6.0, 5.0, refs[:8], size=16, space=6)
textbox(s, 6.85, 1.15, 6.0, 5.0, refs[8:], size=16, space=6)
s.shapes.add_picture(BD + 'band.jpg', 0, Inches(6.25), prs.slide_width, Inches(1.25))
rect(s, 0.7, 6.4, 0.08, 0.9, fill=AMBER, shape=MSO_SHAPE.RECTANGLE)
textbox(s, 0.95, 6.4, 5, 0.9, ['Thank you'], size=40, bold=True, color=WHITE, font=HEAD, anchor=MSO_ANCHOR.MIDDLE, check=False)
textbox(s, 6.0, 6.4, 6.9, 0.9, ['Questions are welcome', 'Md. Shifat Hasan  ·  Roll 2107067'], size=18, color=LIGHT, align=PP_ALIGN.RIGHT, anchor=MSO_ANCHOR.MIDDLE, space=2, check=False)

out = os.path.join(HERE, 'Sentinel_Presentation.pptx')
prs.save(out); print('saved', out, len(prs.slides._sldIdLst), 'slides'); print('\n'.join(warnings) or 'no overflow warnings')
