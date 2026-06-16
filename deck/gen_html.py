#!/usr/bin/env python3
"""Generate the 15-slide premium HTML keynote (injects into keynote.html)."""
import math, os, re

HERE = os.path.dirname(os.path.abspath(__file__))

# ── reusable component helpers ───────────────────────────────────────────────
def petals(specs):
    out = []
    for (l, t, sz, col, op, rot) in specs:
        out.append(f'<div class="petal" style="left:{l}px;top:{t}px;width:{sz}px;height:{sz}px;'
                   f'color:{col};opacity:{op};transform:rotate({rot}deg)"><svg><use href="#blossom"/></svg></div>')
    return '<div class="petals">' + ''.join(out) + '</div>'

def glow(x, y, d, col, op=.5):
    return f'<div class="glow" style="left:{x}px;top:{y}px;width:{d}px;height:{d}px;background:{col};opacity:{op}"></div>'

def page(n, brand="MedicoScope · Aegis"):
    return f'<div class="brand">{brand}</div><div class="pagenum">{n:02d} / 15</div>'

def icon(svg_inner, bg):
    return f'<div class="iconbox" style="background:{bg}">{svg_inner}</div>'

# tiny inline SVG glyphs (stroke = white)
def gi(path, sw=2.2, fill="none", color="#fff"):
    return (f'<svg width="26" height="26" viewBox="0 0 24 24" fill="{fill}" stroke="{color}" '
            f'stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round">{path}</svg>')

IC = {
  "shield": '<path d="M12 3l7 3v5c0 4.5-3 7.5-7 9-4-1.5-7-4.5-7-9V6l7-3z"/>',
  "scan":   '<path d="M4 8V5a1 1 0 011-1h3M16 4h3a1 1 0 011 1v3M20 16v3a1 1 0 01-1 1h-3M8 20H5a1 1 0 01-1-1v-3"/><circle cx="12" cy="12" r="3"/>',
  "chain":  '<path d="M9 12h6M8 8a4 4 0 000 8h2M16 8h-2M16 16a4 4 0 000-8"/>',
  "brain":  '<path d="M9 8a3 3 0 00-3 3 3 3 0 000 4 3 3 0 003 3M15 8a3 3 0 013 3 3 3 0 010 4 3 3 0 01-3 3M9 8a3 3 0 013-3 3 3 0 013 3M9 19a3 3 0 003 1 3 3 0 003-1M12 5v15"/>',
  "pulse":  '<path d="M3 12h4l2-6 4 12 2-6h6"/>',
  "leaf":   '<path d="M11 20A7 7 0 014 13c0-5 4-9 9-9 4 0 7 2 7 6a8 8 0 01-9 10zM11 20c0-5 2-9 6-11"/>',
  "spark":  '<path d="M12 3l2 5 5 2-5 2-2 5-2-5-5-2 5-2z"/>',
  "eye":    '<path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7-10-7-10-7z"/><circle cx="12" cy="12" r="3"/>',
  "arrow":  '<path d="M5 12h14M13 6l6 6-6 6"/>',
  "alert":  '<path d="M12 9v4M12 17h.01M10.3 4l-7 12a2 2 0 001.7 3h14a2 2 0 001.7-3l-7-12a2 2 0 00-3.4 0z"/>',
  "check":  '<path d="M5 13l4 4L19 7"/>',
}

def colstop(c1, c2, a=135):
    return f"linear-gradient({a}deg,{c1},{c2})"

# ── 15 slides ────────────────────────────────────────────────────────────────
S = []

# 1 · VISION
S.append(f'''
<div class="slide">
  {glow(980,-120,420,"#FAD3E0",.7)}{glow(-120,640,380,"#FBE0EA",.6)}
  {petals([(1080,40,70,"#FBD0DE",.7,10),(1010,150,46,"#F79CB4",.6,200),(1150,200,40,"#FCE4EC",.8,120),(70,90,42,"#FBD0DE",.5,40)])}
  <div class="pad col" style="justify-content:center">
    <div style="position:absolute;left:0;top:0;bottom:0;width:520px;background:linear-gradient(180deg,#FCE4EC 0%,#FDEFF4 100%);opacity:.7"></div>
    <div style="position:relative">
      <div class="kicker">Autonomous Healthcare Intelligence</div>
      <h1 style="font-size:84px;margin-top:14px">MedicoScope<br><span class="grad-text">Aegis</span></h1>
      <div class="divider" style="margin:26px 0 22px"></div>
      <div class="lead" style="max-width:560px;font-size:21px">A multi-agent health platform that <b style="color:var(--ink)">observes, reasons, acts</b> — and knows when to stop.</div>
      <div class="chip" style="margin-top:30px">Theme · AI Agents &amp; Autonomous Systems</div>
    </div>
    <div class="glass col" style="position:absolute;right:72px;top:150px;width:430px;height:400px;padding:34px;gap:6px">
      <div class="kicker" style="font-size:12px">The system, at a glance</div>
      <div style="margin-top:10px">
        {''.join(f'<div class="flex" style="align-items:baseline;gap:16px;padding:14px 0;border-bottom:1px solid var(--line)"><div style="font-family:var(--serif);font-weight:800;font-size:30px;width:120px;color:{c}">{b}</div><div style="color:var(--ink2);font-size:14px;font-weight:500">{l}</div></div>' for b,l,c in [("9","autonomous screening modalities","#C9527A"),("3-tier","safety gate · fail-closed","#5E8A6E"),("100%","decisions in a tamper-evident ledger","#6C9BC0"),("0","fabricated readings — by design","#E8B46B")])}
      </div>
    </div>
  </div>
  {page(1)}
</div>''')

# 2 · PROBLEM MAGNITUDE
def stat_card(big, lbl, c1, c2, txt):
    return f'''<div class="card col" style="flex:1;padding:34px;background:{colstop(c1,c2)};border:none">
      <div style="font-family:var(--serif);font-weight:800;font-size:58px;color:{txt}">{big}</div>
      <div style="color:var(--ink2);font-size:15px;font-weight:600;margin-top:8px;line-height:1.4">{lbl}</div></div>'''
S.append(f'''
<div class="slide">
  {petals([(1120,46,60,"#FBD0DE",.55,20)])}
  <div class="pad col">
    <div class="kicker">The Problem · at scale</div>
    <h1 style="font-size:44px;margin-top:12px">Billions need screening.<br>Care can't reach them.</h1>
    <div class="flex gap24" style="margin-top:40px">
      {stat_card("1.4B","live with hypertension —<br>roughly half undiagnosed","#FCE4EC","#FBD0DE","#C9527A")}
      {stat_card("50%","of diabetes in India<br>goes undetected","#E9F2EC","#D8EADF","#5E8A6E")}
      {stat_card("1:1000+","doctor-to-patient gap<br>in rural regions","#E7F0F7","#D4E6F1","#6C9BC0")}
    </div>
    <div class="glass flex center" style="margin-top:34px;padding:26px 36px">
      <div style="font-size:18px;color:var(--ink2)">The bottleneck isn't the will to screen — it's <b class="grad-text" style="font-weight:800">access, speed, and trust.</b></div>
    </div>
  </div>
  {page(2)}
</div>''')

# 3 · WHY HEALTH AI FAILS
def listcol(title, color, items, good):
    mark = IC["check"] if good else '<path d="M6 6l12 12M18 6L6 18"/>'
    rows = ''.join(f'''<div class="flex" style="align-items:center;gap:14px;padding:15px 0;border-bottom:1px solid var(--line)">
      <div style="width:30px;height:30px;border-radius:9px;flex:none;display:flex;align-items:center;justify-content:center;background:{'#E8F3EC' if good else '#FBE7E7'}">
        <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="{color}" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round">{mark}</svg></div>
      <div style="font-size:15.5px;color:var(--ink);font-weight:500">{t}</div></div>''' for t in items)
    return rows
S.append(f'''
<div class="slide">
  {glow(900,560,360,"#E9F2EC",.5)}
  <div class="pad col">
    <div class="kicker">Why Most Health AI Fails</div>
    <h1 style="font-size:46px;margin-top:12px">Confident — and unaccountable.</h1>
    <div class="flex gap24" style="margin-top:34px">
      <div class="card col" style="flex:1;padding:30px 34px">
        <div class="chip" style="background:#FBE7E7;color:#C0392B">Typical health AI</div>
        <div style="margin-top:10px">{listcol("",[],["Outputs a diagnosis with no calibrated doubt","Acts on a single, easily-wrong signal","No record of what it did or why","No human brake on serious actions"], False).replace("{color}","#E26D6D")}</div>
      </div>
      <div class="card col" style="flex:1;padding:30px 34px;background:{colstop('#EAF4EE','#DCEEE3')};border:none">
        <div class="chip pill-live">MedicoScope Aegis</div>
        <div style="margin-top:10px">{listcol("",[],["Calibrated confidence — refuses to score noise","Fuses independent modalities (concordance)","Tamper-evident ledger on every decision","Gate escalates anything serious to a human"], True).replace("{color}","#5E8A6E")}</div>
      </div>
    </div>
  </div>
  {page(3)}
</div>''')

# 4 · SOLUTION — the gate
def gate_card(tag, col, light, title, body):
    return f'''<div class="card col" style="flex:1;padding:28px;background:{colstop(light,'#fff')};position:relative;overflow:hidden">
      <div style="position:absolute;top:0;left:0;right:0;height:6px;background:{col}"></div>
      <div class="chip" style="background:{col};color:#fff;align-self:flex-start;margin-top:6px">{tag}</div>
      <div style="font-family:var(--serif);font-weight:700;font-size:24px;margin-top:14px">{title}</div>
      <div style="color:var(--ink2);font-size:14.5px;margin-top:8px;line-height:1.5">{body}</div></div>'''
S.append(f'''
<div class="slide">
  {glow(1000,-100,380,"#FAD3E0",.6)}
  {petals([(60,560,52,"#FBD0DE",.5,30),(150,610,40,"#F79CB4",.5,160)])}
  <div class="pad col">
    <div class="kicker">The Solution</div>
    <h1 style="font-size:46px;margin-top:12px">An agent with a <span class="grad-text">safety gate</span> at its core.</h1>
    <div class="flex gap24" style="margin-top:36px">
      {gate_card("GREEN","#7EC08F","#EAF6EE","Act","Reversible, low-risk actions run autonomously.")}
      {gate_card("AMBER","#F0B45C","#FCF1E0","Act + notify","Run the safe half, alert the clinician.")}
      {gate_card("RED","#E26D6D","#FBE9E9","Stop · escalate","Block the action; open a human-gated case.")}
    </div>
    <div class="glass flex center" style="margin-top:32px;padding:24px">
      <div style="font-size:19px"><b style="font-family:var(--serif)">The agent proposes.</b> &nbsp;<b class="grad-text" style="font-family:var(--serif);font-weight:800">The gate disposes.</b> &nbsp;<span style="color:var(--ink2)">Every decision is provable.</span></div>
    </div>
  </div>
  {page(4)}
</div>''')

# 5 · AGENT ECOSYSTEM (LIVE vs ROADMAP) — radial SVG
def ecosystem_svg():
    cx, cy = 640, 330
    agents = [("Diagnosis","multi-modal","#5E8A6E",True),("Memory","episodic+LT","#6C9BC0",True),
              ("Concordance","evidence fusion","#E8B46B",True),("Triage","plan + route","#E36B8E",True),
              ("Treatment","guideline-based","#9A8B91",False),("Emergency","red-flag SLA","#E26D6D",False),
              ("Predictive","risk forecast","#9A8B91",False),("AR Assist","guided capture","#9A8B91",False)]
    rx, ry = 360, 210
    parts = ['<svg width="1136" height="470" viewBox="0 0 1280 560">']
    # connectors first
    for i,(lbl,sb,col,live) in enumerate(agents):
        ang = -90 + i*(360/len(agents))
        nx = cx+rx*math.cos(math.radians(ang)); ny = cy+ry*math.sin(math.radians(ang))
        dash = '' if live else 'stroke-dasharray="5 6"'
        parts.append(f'<line x1="{cx}" y1="{cy}" x2="{nx:.0f}" y2="{ny:.0f}" stroke="{col if live else "#E6D4DC"}" stroke-width="{2.4 if live else 1.6}" {dash} opacity="{0.7 if live else 0.6}"/>')
    # nodes
    for i,(lbl,sb,col,live) in enumerate(agents):
        ang = -90 + i*(360/len(agents))
        nx = cx+rx*math.cos(math.radians(ang)); ny = cy+ry*math.sin(math.radians(ang))
        if live:
            parts.append(f'<circle cx="{nx:.0f}" cy="{ny:.0f}" r="58" fill="{col}"/>')
            parts.append(f'<circle cx="{nx:.0f}" cy="{ny:.0f}" r="58" fill="none" stroke="#fff" stroke-width="3" opacity=".5"/>')
            tc, sc = "#fff", "#ffffffcc"
        else:
            parts.append(f'<circle cx="{nx:.0f}" cy="{ny:.0f}" r="56" fill="#F6EEF2" stroke="{col}" stroke-width="2" stroke-dasharray="4 5"/>')
            tc, sc = "#6E6066", "#9A8B91"
        parts.append(f'<text x="{nx:.0f}" y="{ny-4:.0f}" text-anchor="middle" font-family="Inter" font-weight="700" font-size="16" fill="{tc}">{lbl}</text>')
        parts.append(f'<text x="{nx:.0f}" y="{ny+15:.0f}" text-anchor="middle" font-family="Inter" font-size="11.5" fill="{sc}">{sb}</text>')
    # hub
    parts.append(f'<circle cx="{cx}" cy="{cy}" r="86" fill="url(#hubg)"/>')
    parts.append(f'<text x="{cx}" y="{cy-8}" text-anchor="middle" font-family="Playfair Display" font-weight="800" font-size="22" fill="#fff">AEGIS</text>')
    parts.append(f'<text x="{cx}" y="{cy+14}" text-anchor="middle" font-family="Inter" font-size="12.5" fill="#ffffffdd">orchestrator</text>')
    parts.append(f'<text x="{cx}" y="{cy+32}" text-anchor="middle" font-family="Inter" font-size="11" fill="#ffffffbb">gate · ledger</text>')
    parts.append('<defs><radialGradient id="hubg"><stop offset="0%" stop-color="#E36B8E"/><stop offset="100%" stop-color="#C9527A"/></radialGradient></defs>')
    parts.append('</svg>')
    return ''.join(parts)
S.append(f'''
<div class="slide">
  {glow(620,300,520,"#FBE0EA",.45)}
  <div class="pad col" style="padding:48px 72px">
    <div class="kicker">Autonomous Agent Ecosystem</div>
    <h1 style="font-size:40px;margin-top:8px">One orchestrator. Many specialised agents.</h1>
    <div style="margin-top:2px">{ecosystem_svg()}</div>
    <div class="flex center gap16" style="position:absolute;bottom:54px;left:0;right:0">
      <div class="chip pill-live">● LIVE · built today</div>
      <div class="chip pill-road">○ ROADMAP · designed</div>
    </div>
  </div>
  {page(5)}
</div>''')

# 6 · REASONING LOOP
def loop_svg():
    cx, cy, r = 568, 250, 175
    steps=[("Observe","capture signals","#F79CB4"),("Reason","fuse + classify","#7EA68C"),
           ("Decide","gate verdict","#E8B46B"),("Act","or escalate","#8FB8D6"),("Learn","memory update","#E36B8E")]
    p=['<svg width="1136" height="430" viewBox="0 0 1136 500">']
    pts=[]
    for i in range(len(steps)):
        ang=-90+i*(360/len(steps)); nx=cx+r*math.cos(math.radians(ang)); ny=cy+r*math.sin(math.radians(ang)); pts.append((nx,ny))
    # curved-ish arcs as lines with arrowheads
    for i in range(len(steps)):
        a=pts[i]; b=pts[(i+1)%len(steps)]
        p.append(f'<line x1="{a[0]:.0f}" y1="{a[1]:.0f}" x2="{b[0]:.0f}" y2="{b[1]:.0f}" stroke="#FBD0DE" stroke-width="3"/>')
    for i,(t,sb,col) in enumerate(steps):
        nx,ny=pts[i]
        p.append(f'<circle cx="{nx:.0f}" cy="{ny:.0f}" r="62" fill="{col}"/>')
        p.append(f'<circle cx="{nx:.0f}" cy="{ny:.0f}" r="62" fill="none" stroke="#fff" stroke-width="3" opacity=".5"/>')
        p.append(f'<text x="{nx:.0f}" y="{ny-3:.0f}" text-anchor="middle" font-family="Inter" font-weight="700" font-size="16" fill="#fff">{t}</text>')
        p.append(f'<text x="{nx:.0f}" y="{ny+16:.0f}" text-anchor="middle" font-family="Inter" font-size="11" fill="#ffffffcc">{sb}</text>')
    p.append(f'<text x="{cx}" y="{cy-6}" text-anchor="middle" font-family="Inter" font-size="15" fill="#6E6066">continuous</text>')
    p.append(f'<text x="{cx}" y="{cy+16}" text-anchor="middle" font-family="Playfair Display" font-weight="800" font-size="20" fill="#C9527A">learning</text>')
    p.append('</svg>')
    return ''.join(p)
S.append(f'''
<div class="slide">
  {petals([(1110,60,56,"#FBD0DE",.5,15)])}
  <div class="pad col" style="padding:50px 72px">
    <div class="kicker">How an Agent Thinks</div>
    <h1 style="font-size:42px;margin-top:8px">A closed loop — every cycle, <span class="grad-text">smarter</span>.</h1>
    <div class="flex center" style="margin-top:6px">{loop_svg()}</div>
  </div>
  {page(6)}
</div>''')

# 7 · JOURNEY (Sankey-ish lanes)
def lane(t, b, col):
    return f'''<div class="card col" style="flex:1;padding:24px;position:relative;overflow:hidden">
      <div style="position:absolute;top:0;left:0;right:0;height:6px;background:{col}"></div>
      <div style="font-family:var(--serif);font-weight:700;font-size:21px;margin-top:6px">{t}</div>
      <div style="color:var(--ink2);font-size:13.5px;margin-top:8px;line-height:1.5">{b}</div></div>'''
def arrowsvg(col="#E36B8E"):
    return f'<div class="flex center" style="width:40px"><svg width="30" height="22" viewBox="0 0 24 24" fill="none" stroke="{col}" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M4 12h14M13 6l6 6-6 6"/></svg></div>'
S.append(f'''
<div class="slide">
  {glow(80,600,340,"#FCE4EC",.5)}
  <div class="pad col">
    <div class="kicker">End-to-End Journey</div>
    <h1 style="font-size:42px;margin-top:10px">From a phone in hand to a clinician's queue.</h1>
    <div class="flex" style="margin-top:40px;align-items:stretch">
      {lane("Patient","Opens app · captures a screening","#F79CB4")}{arrowsvg()}
      {lane("Agent","Plans · runs tools · fuses evidence","#7EA68C")}{arrowsvg()}
      {lane("Gate","GREEN / AMBER / RED verdict","#E8B46B")}{arrowsvg()}
      {lane("Outcome","Result · doctor alert · or RED case","#8FB8D6")}
    </div>
    <div class="glass col" style="margin-top:34px;padding:26px 34px">
      <div class="kicker" style="font-size:12px">Every step is logged</div>
      <div style="font-size:17px;margin-top:8px;color:var(--ink2)">Tamper-evident ledger + per-patient memory → <b style="color:var(--ink)">each visit makes the next one smarter and auditable.</b></div>
    </div>
  </div>
  {page(7)}
</div>''')

# 8 · ARCHITECTURE (layers)
def layer(tag, body, col, light):
    return f'''<div class="card flex" style="align-items:center;padding:22px 30px;background:{colstop(light,'#fff')};position:relative;overflow:hidden;gap:24px">
      <div style="position:absolute;left:0;top:0;bottom:0;width:7px;background:{col}"></div>
      <div style="font-family:var(--serif);font-weight:700;font-size:19px;width:230px;flex:none">{tag}</div>
      <div style="color:var(--ink2);font-size:14.5px;line-height:1.5">{body}</div></div>'''
S.append(f'''
<div class="slide">
  {petals([(60,70,46,"#FBD0DE",.5,200)])}
  <div class="pad col">
    <div class="kicker">Technical Architecture</div>
    <h1 style="font-size:42px;margin-top:10px">Three layers. One governed envelope.</h1>
    <div class="col gap16" style="margin-top:34px">
      {layer("Experience","Flutter · iOS / Android / Web · on-device DSP · camera · mic · wearables","#F79CB4","#FDEFF4")}
      {layer("Intelligence","Agent orchestrator (FastAPI) · Groq LLM · TFLite + MFCC · deterministic clinical rules","#7EA68C","#ECF4EF")}
      {layer("Governance &amp; Data","Aegis gate · classifier · hash-chained ledger · versioned KB · MongoDB","#8FB8D6","#EAF1F7")}
    </div>
    <div class="flex" style="margin-top:26px;gap:10px;align-items:center">
      <div class="chip">Standards as data</div>
      <div style="color:var(--ink2);font-size:15px">ADA · WHO · AHA/ACC · ICMR — update guidelines without shipping code.</div>
    </div>
  </div>
  {page(8)}
</div>''')

# 9 · AI DECISION FLOW
def fbox(t, b, col):
    return f'''<div class="card col" style="flex:1;padding:18px 16px;text-align:center;position:relative;overflow:hidden">
      <div style="position:absolute;top:0;left:0;right:0;height:5px;background:{col}"></div>
      <div style="font-family:var(--serif);font-weight:700;font-size:17px;margin-top:4px">{t}</div>
      <div style="color:var(--ink3);font-size:12px;margin-top:5px">{b}</div></div>'''
def outpill(t, col, light):
    return f'<div class="card flex center" style="flex:1;padding:16px;background:{colstop(light,"#fff")};font-weight:700;color:var(--ink);font-size:14.5px">{t}</div>'
S.append(f'''
<div class="slide">
  {glow(1000,-80,360,"#FAD3E0",.55)}
  <div class="pad col">
    <div class="kicker">AI Decision Flow</div>
    <h1 style="font-size:44px;margin-top:10px">It knows when <span class="grad-text">not</span> to act.</h1>
    <div class="flex center gap16" style="margin-top:34px">
      {fbox("Evidence","modalities","#F79CB4")}{arrowsvg()}{fbox("Red-flag scan","KB rules","#7EA68C")}{arrowsvg()}{fbox("Classify","risk × confidence","#E8B46B")}{arrowsvg()}{fbox("Verdict","G / A / R","#E36B8E")}
    </div>
    <div class="flex gap16" style="margin-top:22px">
      {outpill("GREEN → execute","#7EC08F","#EAF6EE")}{outpill("AMBER → notify doctor","#F0B45C","#FCF1E0")}{outpill("RED → block + clinician case","#E26D6D","#FBE9E9")}
    </div>
    <div class="flex center" style="margin-top:26px;padding:22px;border-radius:18px;background:#2A2025">
      <span class="mono" style="color:#7EC08F;font-weight:600;font-size:14px">fail-closed:&nbsp;</span>
      <span class="mono" style="color:#FBD0DE;font-size:13.5px">low confidence on a high-risk call escalates — never auto-approves.</span>
    </div>
  </div>
  {page(9)}
</div>''')

# 10 · LIVE DEMO FLOW
def demobox(t, b, col):
    return f'''<div class="card col" style="flex:1;padding:22px;position:relative;overflow:hidden">
      <div style="position:absolute;top:0;left:0;right:0;height:6px;background:{col}"></div>
      <div style="font-family:var(--serif);font-weight:700;font-size:19px;margin-top:6px">{t}</div>
      <div style="color:var(--ink2);font-size:13.5px;margin-top:7px;line-height:1.45">{b}</div></div>'''
S.append(f'''
<div class="slide">
  <div class="pad col">
    <div class="kicker">Live Demo Flow</div>
    <h1 style="font-size:40px;margin-top:10px">Governed autonomy — on stage, in 60 seconds.</h1>
    <div class="flex gap16" style="margin-top:30px">
      {demobox("1 · Trigger","Crisis-language check-in submitted","#F79CB4")}
      {demobox("2 · Gate","Classifies → RED · BLOCK","#E26D6D")}
      {demobox("3 · Escalate","Clinician case opens for review","#F0B45C")}
      {demobox("4 · Prove","Ledger shows chain · INTACT","#7EA68C")}
    </div>
    <div style="margin-top:26px;border-radius:18px;background:#241B20;padding:26px 30px;box-shadow:var(--shadow)">
      <div class="mono" style="color:#7EC08F;font-weight:600;font-size:14.5px">$ node aegis/demo-check.js</div>
      <div class="mono" style="color:#FBD0DE;font-size:13px;margin-top:10px;line-height:1.85">
        &nbsp;&nbsp;✓ KB has 8 red-flag rules &nbsp;&nbsp; ✓ Gate → RED/BLOCK on critical input<br>
        &nbsp;&nbsp;✓ RED submission opened a ClinicianCase<br>
        &nbsp;&nbsp;✓ Audit ledger wrote rows; hash chain INTACT</div>
      <div class="mono" style="color:#7EC08F;font-weight:600;font-size:14.5px;margin-top:10px">&nbsp;&nbsp;✅ GO — agentic / gate path working end-to-end.</div>
    </div>
  </div>
  {page(10)}
</div>''')

# 11 · COMPETITIVE MATRIX
def matrix():
    cols=["Symptom chatbots","Single-modal ML","MedicoScope Aegis"]
    rows=["Multi-modal evidence","Cross-modality concordance","Knows when NOT to act","Tamper-evident audit","Human-in-the-loop gate","Honest, calibrated confidence"]
    head='<div class="flex" style="gap:0"><div style="flex:1.6"></div>'
    for j,c in enumerate(cols):
        hl=(j==2)
        head+=f'<div class="flex center" style="flex:1;padding:14px 6px;text-align:center;font-weight:700;font-size:13.5px;border-radius:14px 14px 0 0;{"background:linear-gradient(135deg,#E36B8E,#C9527A);color:#fff" if hl else "color:var(--ink2)"}">{c}</div>'
    head+='</div>'
    body=''
    for i,rlabel in enumerate(rows):
        body+='<div class="flex" style="gap:0;align-items:stretch">'
        body+=f'<div class="flex" style="flex:1.6;align-items:center;font-weight:600;font-size:14.5px;padding:13px 4px;color:var(--ink)">{rlabel}</div>'
        for j in range(3):
            hl=(j==2)
            good=hl
            mark='<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#5E8A6E" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M5 13l4 4L19 7"/></svg>' if good else '<span style="color:#C8B8BF;font-size:18px">—</span>'
            bgc='background:#EAF4EE;' if hl else ''
            body+=f'<div class="flex center" style="flex:1;padding:11px;{bgc}border:1px solid var(--line);margin:2px;border-radius:10px">{mark}</div>'
        body+='</div>'
    return f'<div class="card" style="padding:18px 22px;margin-top:30px">{head}{body}</div>'
S.append(f'''
<div class="slide">
  {petals([(1120,50,54,"#FBD0DE",.5,40)])}
  <div class="pad col">
    <div class="kicker">Competitive Advantage</div>
    <h1 style="font-size:44px;margin-top:10px">Where we stand apart.</h1>
    {matrix()}
  </div>
  {page(11)}
</div>''')

# 12 · IMPACT & SCALABILITY
def tile(t, b, col, light, ic):
    return f'''<div class="card flex" style="flex:1;align-items:flex-start;gap:18px;padding:26px">
      {icon(gi(ic), colstop(col,'#fff'))}
      <div class="col"><div style="font-family:var(--serif);font-weight:700;font-size:19px">{t}</div>
      <div style="color:var(--ink2);font-size:14px;margin-top:6px;line-height:1.45">{b}</div></div></div>'''
S.append(f'''
<div class="slide">
  {glow(80,80,300,"#FCE4EC",.5)}
  <div class="pad col">
    <div class="kicker">Impact &amp; Scalability</div>
    <h1 style="font-size:44px;margin-top:10px">Reach more people, without adding risk.</h1>
    <div class="col gap16" style="margin-top:32px">
      <div class="flex gap16">{tile("Rural &amp; tele-health","First-line screening on one phone","#F79CB4","#FDEFF4",IC["pulse"])}{tile("Pluggable modalities","Register a tool → the gate wraps it","#7EA68C","#ECF4EF",IC["leaf"])}</div>
      <div class="flex gap16">{tile("Knowledge as data","Versioned KB — update without code","#8FB8D6","#EAF1F7",IC["brain"])}{tile("Roadmap slots ready","Radiology · ECG · genomics pre-wired","#E8B46B","#FCF3E4",IC["spark"])}</div>
    </div>
  </div>
  {page(12)}
</div>''')

# 13 · ENGINEERING QUALITY
def metric(big, lbl, col, light):
    return f'''<div class="card col center" style="flex:1;padding:26px 14px;text-align:center;background:{colstop(light,'#fff')}">
      <div style="font-family:var(--serif);font-weight:800;font-size:46px;color:{col}">{big}</div>
      <div style="color:var(--ink2);font-size:13px;margin-top:6px;font-weight:600">{lbl}</div></div>'''
S.append(f'''
<div class="slide">
  {petals([(60,580,48,"#FBD0DE",.5,120)])}
  <div class="pad col">
    <div class="kicker">Engineering Quality</div>
    <h1 style="font-size:44px;margin-top:10px">Verified. Audited. Honest about limits.</h1>
    <div class="flex gap16" style="margin-top:34px">
      {metric("57","server tests passing","#5E8A6E","#EAF4EE")}
      {metric("9","analyzer tests · honesty-checked","#C9527A","#FCE4EC")}
      {metric("34","security + persistence fixes","#6C9BC0","#EAF1F7")}
      {metric("0","fabricated readings shipped","#E8B46B","#FCF3E4")}
    </div>
    <div class="glass col" style="margin-top:30px;padding:26px 32px">
      <div class="kicker" style="font-size:12px">Hardened for the real world</div>
      <div class="flex" style="flex-wrap:wrap;gap:10px;margin-top:14px">
        {''.join(f'<div class="chip">{c}</div>' for c in ["Adversarial security audit","Atomic hash-chained ledger","All data in MongoDB","Role-based access","Fail-closed gate","Refusable confidence"])}
      </div>
    </div>
  </div>
  {page(13)}
</div>''')

# 14 · ROADMAP TIMELINE
def phase(t, b, col, live):
    pill=f'<div class="chip pill-live" style="margin-bottom:10px">● LIVE</div>' if live else '<div style="height:34px"></div>'
    return f'''<div class="col center" style="flex:1;text-align:center">
      {pill}
      <div style="font-family:var(--serif);font-weight:800;font-size:20px;color:{col}">{t}</div>
      <div style="width:22px;height:22px;border-radius:50%;background:{colstop(col,'#fff')};margin:14px 0;box-shadow:0 0 0 5px {col}22"></div>
      <div class="card" style="padding:18px;color:var(--ink2);font-size:13.5px;line-height:1.5">{b}</div></div>'''
S.append(f'''
<div class="slide">
  {glow(1000,560,340,"#FCE4EC",.5)}
  <div class="pad col">
    <div class="kicker">Roadmap</div>
    <h1 style="font-size:44px;margin-top:10px">From screening agent to <span class="grad-text">clinical co-pilot</span>.</h1>
    <div style="position:relative;margin-top:40px">
      <div style="position:absolute;left:8%;right:8%;top:80px;height:3px;background:var(--line)"></div>
      <div class="flex gap24" style="position:relative">
        {phase("NOW","9 modalities · gate · ledger · concordance","#C9527A",True)}
        {phase("NEXT","Trained models · device calibration","#F79CB4",False)}
        {phase("THEN","Radiology · ECG · genomics agents","#8FB8D6",False)}
        {phase("VISION","Wearable streaming · clinician co-pilot","#7EA68C",False)}
      </div>
    </div>
    <div class="flex center" style="margin-top:34px"><div style="font-size:17px;color:var(--ink)"><b>Autonomy grows. The safety envelope doesn't shrink.</b></div></div>
  </div>
  {page(14)}
</div>''')

# 15 · WHY WE WIN / CLOSE
def pillar(t, b, col):
    return f'''<div class="glass col center" style="flex:1;padding:26px;text-align:center">
      <div style="font-family:var(--serif);font-weight:700;font-size:21px;color:{col}">{t}</div>
      <div style="color:var(--ink2);font-size:13.5px;margin-top:6px">{b}</div></div>'''
S.append(f'''
<div class="slide" style="background:linear-gradient(135deg,#FDEFF4,#FBD9E4)">
  {petals([(70,70,64,"#FBD0DE",.7,10),(170,40,42,"#F79CB4",.6,150),(1120,560,64,"#FBD0DE",.7,30),(1040,620,42,"#F79CB4",.6,200),(60,600,44,"#FBD0DE",.6,90)])}
  <div class="pad col center" style="text-align:center">
    <h1 style="font-size:62px;margin-top:90px">Autonomy you can <span class="grad-text">trust.</span></h1>
    <div class="lead" style="font-size:21px;margin-top:18px;max-width:760px">A multi-modal health agent that acts — <b style="color:var(--ink)">and knows when to stop.</b></div>
    <div class="flex gap24" style="margin-top:44px;width:760px">
      {pillar("Innovation","governed autonomy","#C9527A")}
      {pillar("Trust","tamper-evident","#5E8A6E")}
      {pillar("Impact","screening at scale","#6C9BC0")}
    </div>
    <div style="margin-top:42px;color:var(--ink2);font-weight:700;font-size:14px;letter-spacing:.04em">MedicoScope Aegis · the future of autonomous healthcare</div>
    <div style="font-family:var(--serif);font-weight:700;font-size:20px;margin-top:14px">Thank you.</div>
  </div>
  {page(15)}
</div>''')

# ── inject into template ─────────────────────────────────────────────────────
tpl = open(os.path.join(HERE, "keynote.html"), encoding="utf-8").read()
out = tpl.replace("<!-- SLIDES_PLACEHOLDER -->", "\n".join(S))
open(os.path.join(HERE, "keynote.html"), "w", encoding="utf-8").write(out)
print("Injected", len(S), "slides into keynote.html")
