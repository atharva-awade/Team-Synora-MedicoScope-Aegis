#!/usr/bin/env python3
"""Render each slide of keynote.html to a 1280x720 PNG via headless Edge,
then assemble a full-bleed .pptx. Produces deck/MedicoScope_Aegis.pptx."""
import os, re, subprocess, glob, time, sys

HERE = os.path.dirname(os.path.abspath(__file__))
EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
SHOTS = os.path.join(HERE, "shots")
os.makedirs(SHOTS, exist_ok=True)

html = open(os.path.join(HERE, "keynote.html"), encoding="utf-8").read()

# Extract shared <head> (style + fonts) and the petal <svg defs>.
head = re.search(r"<head>(.*?)</head>", html, re.S).group(1)
defs = re.search(r'(<svg width="0".*?</svg>)', html, re.S).group(1)

# Each slide is a top-level <div class="slide" ...>...</div>. Split robustly by
# locating slide starts and matching to the page-number marker at the end.
slides = re.findall(r'(<div class="slide".*?</div>\s*</div>)\s*(?=<div class="slide"|</body>)', html, re.S)
# Fallback: simpler split if the above under-matches
if len(slides) < 15:
    # split on the slide opening, then trim at next slide opening
    parts = html.split('<div class="slide"')
    slides = []
    for p in parts[1:]:
        body = '<div class="slide"' + p
        # cut at the next slide or </body>
        slides.append(body)
    # re-clean: keep up to the matching close — use the pagenum as anchor
    cleaned = []
    for sdiv in slides:
        m = re.search(r'(<div class="slide".*?<div class="pagenum">\d+ / 15</div>\s*</div>)', sdiv, re.S)
        if m:
            cleaned.append(m.group(1))
    slides = cleaned

print("Found", len(slides), "slides")
if len(slides) != 15:
    print("WARN: expected 15 slides, got", len(slides))

PAGE = """<!DOCTYPE html><html><head>{head}</head><body style="margin:0;background:#fff">
{defs}
{slide}
</body></html>"""

shot_files = []
for i, sl in enumerate(slides, 1):
    page_html = PAGE.format(head=head, defs=defs, slide=sl)
    fpath = os.path.join(SHOTS, f"slide_{i:02d}.html")
    open(fpath, "w", encoding="utf-8").write(page_html)
    png = os.path.join(SHOTS, f"slide_{i:02d}.png")
    cmd = [EDGE, "--headless=new", "--disable-gpu", "--hide-scrollbars",
           "--force-device-scale-factor=2",        # 2x = crisp retina render
           f"--window-size=1280,720",
           f"--screenshot={png}",
           "--default-background-color=00FFFFFF",
           "file:///" + fpath.replace("\\", "/")]
    subprocess.run(cmd, capture_output=True, timeout=90)
    if os.path.exists(png) and os.path.getsize(png) > 5000:
        shot_files.append(png)
        print(f"  rendered slide {i:02d} ({os.path.getsize(png)//1024} KB)")
    else:
        print(f"  FAILED slide {i:02d}")

# ── assemble pptx ────────────────────────────────────────────────────────────
from pptx import Presentation
from pptx.util import Inches
prs = Presentation()
prs.slide_width = Inches(13.333)
prs.slide_height = Inches(7.5)
blank = prs.slide_layouts[6]
for png in sorted(shot_files):
    s = prs.slides.add_slide(blank)
    s.shapes.add_picture(png, 0, 0, width=prs.slide_width, height=prs.slide_height)
out = os.path.join(HERE, "MedicoScope_Aegis.pptx")
prs.save(out)
print("Saved", out, "with", len(prs.slides._sldIdLst), "slides")
