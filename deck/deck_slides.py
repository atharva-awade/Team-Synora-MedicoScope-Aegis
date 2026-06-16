"""15 keynote-grade slides for MedicoScope — sakura light theme.
Rule: concise + visual. Short kicker + headline + infographic. No paragraphs.
Agent ecosystem is split honestly: LIVE (built) vs ROADMAP (designed)."""
import math
from pptx.util import Inches, Pt
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR
from pptx.enum.shapes import MSO_SHAPE


def build_all(prs, T):
    g = T  # toolkit namespace
    slide=g["slide"]; rect=g["rect"]; card=g["card"]; glass=g["glass"]; grad_card=g["grad_card"]
    grad_fill=g["grad_fill"]; text=g["text"]; R=g["R"]; chip=g["chip"]; kicker=g["kicker"]
    page_num=g["page_num"]; divider=g["divider"]; icon_badge=g["icon_badge"]; blossom=g["blossom"]
    branch_corner=g["branch_corner"]; scatter_blossoms=g["scatter_blossoms"]; soft_shadow=g["soft_shadow"]
    status_pill=g["status_pill"]; agent_node=g["agent_node"]; connect=g["connect"]; arrow=g["arrow"]
    _tint=g["_tint"]
    INK=g["INK"]; INK_SOFT=g["INK_SOFT"]; BG=g["BG"]; BG_PANEL=g["BG_PANEL"]; BLOSSOM=g["BLOSSOM"]
    BLOSSOM_DK=g["BLOSSOM_DK"]; BLUSH=g["BLUSH"]; BLUSH_2=g["BLUSH_2"]; LEAF=g["LEAF"]; GOLD=g["GOLD"]
    SKY=g["SKY"]; RED_SOFT=g["RED_SOFT"]; GREEN_SOFT=g["GREEN_SOFT"]; AMBER_SOFT=g["AMBER_SOFT"]
    LINE=g["LINE"]; FONT_H=g["FONT_H"]; FONT_B=g["FONT_B"]
    from pptx.dml.color import RGBColor

    def H(s, x, y, txt, size=30, w=11.6, color=INK):
        text(s, x, y, w, 1.0, [R(txt, size, color, True, FONT_H)])

    def sub(s, x, y, txt, w=11.6, color=INK_SOFT, size=14):
        text(s, x, y, w, 0.6, [R(txt, size, color)])

    # ── 1 · VISION (cover) ───────────────────────────────────────────────────
    s = slide(grad=True)
    rect(s, -0.6, -0.6, 6.6, 8.7, BLUSH, MSO_SHAPE.RECTANGLE)
    branch_corner(s, "tr")
    scatter_blossoms(s, [(5.0,5.4,0.85,BLUSH_2),(4.4,6.2,0.55,BLOSSOM),(5.5,6.5,0.42,BLUSH_2),(0.7,1.0,0.5,BLUSH_2)])
    text(s, 0.9, 1.35, 6.4, 0.4, [R("AUTONOMOUS HEALTHCARE INTELLIGENCE", 12.5, BLOSSOM_DK, True)])
    text(s, 0.85, 1.8, 7.6, 2.0, [[R("MedicoScope", 58, INK, True, FONT_H)],[R("Aegis", 58, BLOSSOM_DK, True, FONT_H)]], line_spacing=0.95)
    divider(s, 0.95, 3.75, 1.6)
    text(s, 0.95, 3.95, 6.7, 1.0,
         [R("A multi-agent health platform that ", 16, INK_SOFT),
          R("observes, reasons, acts — and knows when to stop.", 16, INK, True)], line_spacing=1.2)
    # right glass metric stack
    gc = glass(s, 8.5, 1.95, 4.2, 3.6)
    text(s, 8.85, 2.2, 3.6, 0.4, [R("THE SYSTEM, AT A GLANCE", 10.5, BLOSSOM_DK, True)])
    rows=[("9","autonomous screening modalities",BLOSSOM_DK),("3-tier","safety gate · fail-closed",LEAF),
          ("100%","decisions in a tamper-evident ledger",SKY),("0","fabricated readings — honest by design",GOLD)]
    yy=2.75
    for big,lbl,col in rows:
        text(s,8.85,yy,1.7,0.55,[R(big,24,col,True,FONT_H)],anchor=MSO_ANCHOR.MIDDLE)
        text(s,10.55,yy,2.0,0.55,[R(lbl,10.5,INK_SOFT)],anchor=MSO_ANCHOR.MIDDLE,line_spacing=0.95)
        yy+=0.68
    text(s, 0.95, 6.6, 8, 0.4, [R("Theme · AI Agents & Autonomous Systems", 12, INK_SOFT, True)])
    page_num(s,1)

    # ── 2 · PROBLEM MAGNITUDE ────────────────────────────────────────────────
    s = slide(); branch_corner(s,"tr")
    kicker(s,0.9,0.7,"The Problem · at scale")
    H(s,0.85,1.05,"Billions need screening. Care can't reach them.",27)
    stats=[("1.4B","live with hypertension —\n~half undiagnosed",BLOSSOM_DK),
           ("50%","of diabetes in India\ngoes undetected",LEAF),
           ("1:1000+","doctor-to-patient gap\nin rural regions",SKY)]
    x=0.9
    for big,lbl,col in stats:
        grad_card(s,x,2.4,3.78,2.5,_tint(col,0.86),_tint(col,0.7))
        text(s,x+0.4,2.75,3.0,0.9,[R(big,40,col,True,FONT_H)])
        text(s,x+0.42,3.75,3.0,1.0,[R(lbl,13,INK_SOFT)],line_spacing=1.1)
        x+=4.0
    glass(s,0.9,5.3,11.5,1.15,BLUSH,shadow=False,line=None)
    text(s,1.2,5.3,11.0,1.15,
         [R("The bottleneck isn't desire to screen — it's ",14,INK_SOFT),
          R("access, speed, and trust.",14,BLOSSOM_DK,True)],anchor=MSO_ANCHOR.MIDDLE)
    page_num(s,2)

    # ── 3 · WHY HEALTHCARE AI FAILS (comparison) ─────────────────────────────
    s = slide(); branch_corner(s,"bl")
    kicker(s,0.9,0.7,"Why Most Health AI Fails")
    H(s,0.85,1.05,"Confident — and unaccountable.",28)
    # two columns: failure modes vs our answer
    glass(s,0.9,2.3,5.55,4.0)
    text(s,1.25,2.55,4.9,0.4,[R("TYPICAL HEALTH AI",12,RED_SOFT,True)])
    fails=["Outputs a diagnosis with no calibrated doubt","Acts on a single, easily-wrong signal",
           "No record of what it did or why","No human brake on consequential actions"]
    yy=3.1
    for f in fails:
        text(s,1.3,yy,0.4,0.4,[R("✗",14,RED_SOFT,True)],anchor=MSO_ANCHOR.MIDDLE)
        text(s,1.7,yy,4.5,0.5,[R(f,12.5,INK)],anchor=MSO_ANCHOR.MIDDLE,line_spacing=1.0)
        yy+=0.75
    gc=grad_card(s,6.85,2.3,5.55,4.0,_tint(LEAF,0.85),_tint(LEAF,0.62))
    text(s,7.2,2.55,4.9,0.4,[R("MEDICOSCOPE AEGIS",12,LEAF,True)])
    wins=["Calibrated confidence — refuses to score noise","Fuses independent modalities (concordance)",
          "Tamper-evident ledger on every decision","Gate escalates anything serious to a human"]
    yy=3.1
    for w_ in wins:
        text(s,7.25,yy,0.4,0.4,[R("✓",14,LEAF,True)],anchor=MSO_ANCHOR.MIDDLE)
        text(s,7.65,yy,4.5,0.5,[R(w_,12.5,INK)],anchor=MSO_ANCHOR.MIDDLE,line_spacing=1.0)
        yy+=0.75
    page_num(s,3)

    # ── 4 · SOLUTION OVERVIEW (the gate) ─────────────────────────────────────
    s = slide(grad=True); branch_corner(s,"tr")
    kicker(s,0.9,0.7,"The Solution")
    H(s,0.85,1.05,"An agent with a safety gate at its core.",27)
    gate=[("GREEN",GREEN_SOFT,"Act","Reversible, low-risk\nactions run autonomously."),
          ("AMBER",AMBER_SOFT,"Act + notify","Run the safe half,\nalert the clinician."),
          ("RED",RED_SOFT,"Stop · escalate","Block · open a\nhuman-gated case.")]
    x=0.9
    for tag,col,title,body in gate:
        grad_card(s,x,2.4,3.78,2.7,_tint(col,0.9),_tint(col,0.72))
        rect(s,x,2.4,3.78,0.16,col,MSO_SHAPE.ROUNDED_RECTANGLE)
        chip(s,x+0.35,2.75,1.4,tag,color=col,txt_color=BG_PANEL,size=12)
        text(s,x+0.35,3.4,3.1,0.5,[R(title,17,INK,True,FONT_H)])
        text(s,x+0.35,3.95,3.1,1.0,[R(body,12.5,INK_SOFT)],line_spacing=1.15)
        x+=4.0
    glass(s,0.9,5.4,11.5,1.0,BLUSH,shadow=False,line=None)
    text(s,1.2,5.4,11.0,1.0,
         [R("The agent proposes.  ",15,INK,True,FONT_H),R("The gate disposes.  ",15,BLOSSOM_DK,True,FONT_H),
          R("Every decision is provable.",13.5,INK_SOFT)],anchor=MSO_ANCHOR.MIDDLE)
    page_num(s,4)

    # ── 5 · AUTONOMOUS AGENT ECOSYSTEM (LIVE vs ROADMAP) — showpiece ─────────
    s = slide()
    kicker(s,0.9,0.55,"Autonomous Agent Ecosystem")
    H(s,0.85,0.9,"One orchestrator. Many specialised agents.",24)
    # central orchestrator
    cx,cy=6.66,4.2
    hub=s.shapes.add_shape(MSO_SHAPE.OVAL,Inches(cx-1.0),Inches(cy-1.0),Inches(2.0),Inches(2.0))
    grad_fill(hub,BLOSSOM_DK,BLOSSOM); soft_shadow(hub)
    text(s,cx-1.0,cy-1.0,2.0,2.0,[[R("AEGIS",13,BG_PANEL,True,FONT_H)],[R("orchestrator",10,BLUSH)],[R("+ gate · ledger",9,BLUSH)]],
         align=PP_ALIGN.CENTER,anchor=MSO_ANCHOR.MIDDLE,line_spacing=0.95,space_after=1)
    # agents: (label, sub, color, live)
    agents=[("Diagnosis","multi-modal",LEAF,True),("Memory","episodic+LT",SKY,True),
            ("Concordance","evidence fusion",GOLD,True),("Triage","plan+route",BLOSSOM,True),
            ("Treatment Rec","guideline-based",INK_SOFT,False),("Emergency","red-flag SLA",RED_SOFT,False),
            ("Predictive","risk forecast",INK_SOFT,False),("AR Assist","guided capture",INK_SOFT,False)]
    n=len(agents); rx,ry=4.55,2.55
    for i,(lbl,sb,col,live) in enumerate(agents):
        ang=-90+i*(360/n)
        nx=cx+rx*math.cos(math.radians(ang)); ny=cy+ry*math.sin(math.radians(ang))
        connect(s,(cx,cy),(nx,ny),(_tint(col,0.4) if live else LINE),1.5)
        agent_node(s,nx,ny,1.35,lbl,sb,col,live=live)
    # legend
    status_pill(s,4.7,6.75,live=True); status_pill(s,5.75,6.75,live=False)
    text(s,7.0,6.73,5.0,0.35,[R("built today  ·  designed roadmap",10.5,INK_SOFT)],anchor=MSO_ANCHOR.MIDDLE)
    page_num(s,5)

    # ── 6 · AGENT REASONING LOOP (Observe→Reason→Decide→Act→Learn) ───────────
    s = slide(grad=True); branch_corner(s,"tr")
    kicker(s,0.9,0.7,"How an Agent Thinks")
    H(s,0.85,1.05,"A closed loop — every cycle, smarter.",26)
    steps=[("Observe","capture signals",BLOSSOM),("Reason","fuse + classify",LEAF),
           ("Decide","gate verdict",GOLD),("Act","or escalate",SKY),("Learn","memory update",BLOSSOM_DK)]
    cx,cy=6.66,4.4; rad=1.95
    pts=[]
    for i,(t,b,col) in enumerate(steps):
        ang=-90+i*(360/len(steps))
        nx=cx+rad*math.cos(math.radians(ang)); ny=cy+ry if False else cy+rad*math.sin(math.radians(ang))
        pts.append((nx,ny,t,b,col))
    # arc connectors (straight, schema-safe) around the circle
    for i in range(len(pts)):
        a=pts[i]; b=pts[(i+1)%len(pts)]
        connect(s,(a[0],a[1]),(b[0],b[1]),BLUSH_2,2.0)
    for (nx,ny,t,b,col) in pts:
        node=s.shapes.add_shape(MSO_SHAPE.OVAL,Inches(nx-0.72),Inches(ny-0.72),Inches(1.44),Inches(1.44))
        grad_fill(node,col,_tint(col,0.4)); soft_shadow(node)
        text(s,nx-0.72,ny-0.72,1.44,1.44,[[R(t,12,BG_PANEL,True,FONT_B)],[R(b,8.5,BLUSH)]],
             align=PP_ALIGN.CENTER,anchor=MSO_ANCHOR.MIDDLE,line_spacing=0.95,space_after=1)
    text(s,cx-1.1,cy-0.4,2.2,0.8,[[R("continuous",12,INK_SOFT,True)],[R("learning",12,BLOSSOM_DK,True,FONT_H)]],
         align=PP_ALIGN.CENTER,anchor=MSO_ANCHOR.MIDDLE)
    page_num(s,6)

    # ── 7 · END-TO-END PATIENT JOURNEY (Sankey-ish flow) ─────────────────────
    s = slide(); branch_corner(s,"bl")
    kicker(s,0.9,0.7,"End-to-End Journey")
    H(s,0.85,1.05,"From a phone in hand to a clinician's queue.",24)
    lanes=[("Patient","opens app · captures\na screening",BLOSSOM),
           ("Agent","plans · runs tools ·\nfuses evidence",LEAF),
           ("Gate","GREEN / AMBER / RED\nverdict",GOLD),
           ("Outcome","result · doctor alert ·\nor RED case",SKY)]
    x=0.9; w=2.78
    centers=[]
    for i,(t,b,col) in enumerate(lanes):
        glass(s,x,2.5,w,2.0)
        rect(s,x,2.5,w,0.16,col,MSO_SHAPE.ROUNDED_RECTANGLE)
        text(s,x+0.3,2.78,w-0.5,0.5,[R(t,15,INK,True,FONT_H)])
        text(s,x+0.3,3.35,w-0.5,1.1,[R(b,12,INK_SOFT)],line_spacing=1.12)
        centers.append((x+w,3.5)); x+=w+0.45
        if i<len(lanes)-1:
            arrow(s,x-0.43,3.38,0.4,0.24,BLOSSOM)
    glass(s,0.9,4.9,11.5,1.4,BLUSH,shadow=False,line=None)
    text(s,1.2,5.0,11.0,0.4,[R("EVERY STEP IS LOGGED",11,BLOSSOM_DK,True)])
    text(s,1.2,5.45,11.0,0.8,
         [R("Tamper-evident ledger + per-patient memory → ",13,INK_SOFT),
          R("each visit makes the next one smarter and auditable.",13,INK,True)],line_spacing=1.1)
    page_num(s,7)

    # ── 8 · TECHNICAL ARCHITECTURE (layered) ─────────────────────────────────
    s = slide(); branch_corner(s,"tr")
    kicker(s,0.9,0.6,"Technical Architecture")
    H(s,0.85,0.95,"Three layers. One governed envelope.",24)
    layers=[("EXPERIENCE","Flutter · iOS / Android / Web · on-device DSP · camera · mic · wearables",BLOSSOM),
            ("INTELLIGENCE","Agent orchestrator (FastAPI) · Groq LLM · TFLite + MFCC · deterministic clinical rules",LEAF),
            ("GOVERNANCE & DATA","Aegis gate · classifier · hash-chained ledger · versioned KB · MongoDB",SKY)]
    y=2.1
    for tag,body,col in layers:
        grad_card(s,0.9,y,11.5,1.35,_tint(col,0.9),_tint(col,0.74))
        rect(s,0.9,y,0.18,1.35,col,MSO_SHAPE.ROUNDED_RECTANGLE)
        text(s,1.3,y+0.18,4.0,0.5,[R(tag,15,INK,True,FONT_H)])
        text(s,1.3,y+0.72,10.8,0.5,[R(body,12.5,INK_SOFT)])
        y+=1.55
    glass(s,0.9,6.85,11.5,0.0,shadow=False,line=None)  # spacer (no-op visual)
    text(s,0.9,6.55,11.5,0.4,
         [R("Standards as data: ",12,INK,True),R("ADA · WHO · AHA/ACC · ICMR — update guidelines without shipping code.",12,INK_SOFT)])
    page_num(s,8)

    # ── 9 · AI DECISION FLOW (the gate, deep) ────────────────────────────────
    s = slide(grad=True)
    kicker(s,0.9,0.6,"AI Decision Flow")
    H(s,0.85,0.95,"It knows when NOT to act.",26)
    # pipeline
    chain=[("Evidence","modalities",BLOSSOM),("Red-flag scan","KB rules",LEAF),
           ("Classify","risk × confidence",GOLD),("Verdict","G / A / R",BLOSSOM_DK)]
    x=0.9; w=2.5
    for i,(t,b,col) in enumerate(chain):
        glass(s,x,2.1,w,1.4); rect(s,x,2.1,w,0.14,col,MSO_SHAPE.ROUNDED_RECTANGLE)
        text(s,x,2.35,w,0.5,[R(t,13.5,INK,True,FONT_H)],align=PP_ALIGN.CENTER)
        text(s,x,2.9,w,0.5,[R(b,11,INK_SOFT)],align=PP_ALIGN.CENTER)
        x+=w+0.37
        if i<len(chain)-1: arrow(s,x-0.36,2.62,0.34,0.22,BLOSSOM)
    # outcomes row
    outs=[("GREEN → execute",GREEN_SOFT),("AMBER → notify doctor",AMBER_SOFT),("RED → block + clinician case",RED_SOFT)]
    x=0.9
    for t,col in outs:
        grad_card(s,x,3.9,3.78,1.0,_tint(col,0.88),_tint(col,0.7))
        text(s,x,3.9,3.78,1.0,[R(t,13,INK,True)],align=PP_ALIGN.CENTER,anchor=MSO_ANCHOR.MIDDLE)
        x+=4.0
    glass(s,0.9,5.25,11.5,1.1,INK,shadow=True,line=None)
    text(s,1.2,5.4,11.0,0.85,
         [[R("Fail-closed: ",13,GREEN_SOFT,True,"Consolas"),R("low confidence on a high-risk call escalates — never auto-approves.",12,BLUSH,False,"Consolas")]],
         anchor=MSO_ANCHOR.MIDDLE,line_spacing=1.1)
    page_num(s,9)

    # ── 10 · LIVE DEMO FLOW (money shot + proof) ─────────────────────────────
    s = slide()
    kicker(s,0.9,0.6,"Live Demo Flow")
    H(s,0.85,0.95,"Governed autonomy — on stage, in 60 seconds.",23)
    flow=[("1 · Trigger","crisis-language\ncheck-in",BLOSSOM),("2 · Gate","classifies\nRED · BLOCK",RED_SOFT),
          ("3 · Escalate","clinician case\nopens",AMBER_SOFT),("4 · Prove","ledger chain\nINTACT",LEAF)]
    x=0.9
    for t,b,col in flow:
        glass(s,x,2.0,2.78,2.0); rect(s,x,2.0,2.78,0.16,col,MSO_SHAPE.ROUNDED_RECTANGLE)
        text(s,x+0.3,2.28,2.2,0.5,[R(t,14.5,INK,True,FONT_H)])
        text(s,x+0.3,2.85,2.25,1.0,[R(b,12,INK_SOFT)],line_spacing=1.12)
        x+=2.92
    term=glass(s,0.9,4.45,11.5,1.95,INK,shadow=True,line=None)
    text(s,1.25,4.62,11.0,1.7,
         [[R("$ node aegis/demo-check.js",12.5,GREEN_SOFT,True,"Consolas")],
          [R("  ✓ KB has 8 red-flag rules    ✓ Gate → RED/BLOCK on critical input",11,BLUSH,False,"Consolas")],
          [R("  ✓ RED submission opened a ClinicianCase",11,BLUSH,False,"Consolas")],
          [R("  ✓ Audit ledger wrote rows; hash chain INTACT",11,BLUSH,False,"Consolas")],
          [R("  ✅ GO — agentic / gate path working end-to-end.",12.5,GREEN_SOFT,True,"Consolas")]],
         line_spacing=1.22,anchor=MSO_ANCHOR.MIDDLE)
    page_num(s,10)

    # ── 11 · COMPETITIVE ADVANTAGE MATRIX ────────────────────────────────────
    s = slide(); branch_corner(s,"tr")
    kicker(s,0.9,0.7,"Competitive Advantage")
    H(s,0.85,1.05,"Where we stand apart.",27)
    cols=["Symptom\nchatbots","Single-modal\nML apps","MedicoScope\nAegis"]
    rows=[("Multi-modal evidence",False,False,True),("Cross-modality concordance",False,False,True),
          ("Knows when NOT to act",False,False,True),("Tamper-evident audit",False,False,True),
          ("Human-in-the-loop gate",False,False,True),("Honest, calibrated confidence",False,False,True)]
    # header
    x0,y0=0.9,2.35; lw=5.0; cw=2.05
    for j,c in enumerate(cols):
        cx=x0+lw+j*cw
        hl= (j==2)
        grad_card(s,cx,y0,cw-0.12,0.8,(BLOSSOM_DK if hl else _tint(INK_SOFT,0.85)),(BLOSSOM if hl else _tint(INK_SOFT,0.75))) if hl else card(s,cx,y0,cw-0.12,0.8,BG_PANEL)
        text(s,cx,y0,cw-0.12,0.8,[R(c,11,(BG_PANEL if hl else INK),True)],align=PP_ALIGN.CENTER,anchor=MSO_ANCHOR.MIDDLE,line_spacing=0.95)
    y=y0+0.95
    for r in rows:
        label=r[0]; vals=r[1:]
        text(s,x0,y,lw-0.2,0.55,[R(label,12.5,INK,True)],anchor=MSO_ANCHOR.MIDDLE)
        for j,v in enumerate(vals):
            cx=x0+lw+j*cw
            glyph="✓" if v else "—"
            col=LEAF if v else INK_SOFT
            fill=_tint(LEAF,0.86) if (v and j==2) else BG_PANEL
            cellbg=rect(s,cx,y,cw-0.12,0.55,fill,MSO_SHAPE.ROUNDED_RECTANGLE,line=LINE)
            text(s,cx,y,cw-0.12,0.55,[R(glyph,14,col,True)],align=PP_ALIGN.CENTER,anchor=MSO_ANCHOR.MIDDLE)
        y+=0.63
    page_num(s,11)

    # ── 12 · IMPACT + SCALABILITY (dashboard) ────────────────────────────────
    s = slide(grad=True); branch_corner(s,"bl")
    kicker(s,0.9,0.7,"Impact & Scalability")
    H(s,0.85,1.05,"Reach more people, without adding risk.",25)
    # impact tiles
    tiles=[("Rural & tele-health","first-line screening on one phone",BLOSSOM),
           ("Pluggable modalities","register a tool → gate wraps it",LEAF),
           ("Knowledge as data","versioned KB, update without code",SKY),
           ("Roadmap slots ready","radiology · ECG · genomics pre-wired",GOLD)]
    x0,y0=0.9,2.4
    for i,(t,b,col) in enumerate(tiles):
        cx=x0+(i%2)*5.9; cy=y0+(i//2)*1.85
        glass(s,cx,cy,5.6,1.65)
        icon_badge(s,cx+0.3,cy+0.32,0.62,col,"↗",gsize=18)
        text(s,cx+1.1,cy+0.28,4.3,0.5,[R(t,15,INK,True,FONT_H)],anchor=MSO_ANCHOR.MIDDLE)
        text(s,cx+1.1,cy+0.85,4.3,0.7,[R(b,12,INK_SOFT)],line_spacing=1.05)
    page_num(s,12)

    # ── 13 · ENGINEERING QUALITY ─────────────────────────────────────────────
    s = slide(); branch_corner(s,"tr")
    kicker(s,0.9,0.7,"Engineering Quality")
    H(s,0.85,1.05,"Verified. Audited. Honest about limits.",25)
    metrics=[("57","server tests passing",LEAF),("9","analyzer tests (honesty-checked)",BLOSSOM),
             ("34","security + persistence fixes",SKY),("0","fabricated readings shipped",GOLD)]
    x=0.9
    for big,lbl,col in metrics:
        grad_card(s,x,2.45,2.78,1.7,_tint(col,0.88),_tint(col,0.7))
        text(s,x,2.6,2.78,0.7,[R(big,32,col,True,FONT_H)],align=PP_ALIGN.CENTER)
        text(s,x+0.2,3.4,2.4,0.7,[R(lbl,11,INK_SOFT)],align=PP_ALIGN.CENTER,line_spacing=1.0)
        x+=2.92
    glass(s,0.9,4.45,11.5,1.8)
    text(s,1.25,4.65,11.0,0.4,[R("HARDENED FOR THE REAL WORLD",11.5,BLOSSOM_DK,True)])
    chips=["Adversarial security audit","Atomic hash-chained ledger","All data in MongoDB","Role-based access","Fail-closed gate","Refusable confidence"]
    cxp=1.25; cyp=5.15
    for ch in chips:
        wch=0.18+len(ch)*0.085
        chip(s,cxp,cyp,wch,ch,color=BLUSH,txt_color=BLOSSOM_DK,size=10.5)
        cxp+=wch+0.2
        if cxp>10.8: cxp=1.25; cyp+=0.55
    page_num(s,13)

    # ── 14 · FUTURE / ROADMAP TIMELINE ───────────────────────────────────────
    s = slide(grad=True); branch_corner(s,"bl")
    kicker(s,0.9,0.7,"Roadmap")
    H(s,0.85,1.05,"From screening agent to clinical co-pilot.",26)
    phases=[("NOW","9 modalities · gate ·\nledger · concordance",BLOSSOM_DK,True),
            ("NEXT","trained models ·\ndevice calibration",BLOSSOM,False),
            ("THEN","radiology · ECG ·\ngenomics agents",SKY,False),
            ("VISION","wearable streaming ·\nclinician co-pilot",LEAF,False)]
    rect(s,1.3,3.5,10.7,0.05,LINE,MSO_SHAPE.ROUNDED_RECTANGLE)
    for i,(t,b,col,live) in enumerate(phases):
        cxp=1.9+i*3.0
        dot=s.shapes.add_shape(MSO_SHAPE.OVAL,Inches(cxp-0.16),Inches(3.37),Inches(0.32),Inches(0.32))
        grad_fill(dot,col,_tint(col,0.4)); soft_shadow(dot)
        text(s,cxp-1.3,2.65,2.6,0.5,[R(t,15,col,True,FONT_H)],align=PP_ALIGN.CENTER)
        if live: status_pill(s,cxp-0.45,2.25,live=True)
        glass(s,cxp-1.35,3.9,2.7,1.7)
        text(s,cxp-1.15,4.1,2.3,1.4,[R(b,12,INK_SOFT)],align=PP_ALIGN.CENTER,line_spacing=1.12)
    text(s,0.9,5.9,11.5,0.5,
         [R("Autonomy grows. The safety envelope doesn't shrink.",13.5,INK,True)],align=PP_ALIGN.CENTER)
    page_num(s,14)

    # ── 15 · WHY WE WIN / CLOSE ──────────────────────────────────────────────
    s = slide()
    rect(s,-0.6,-0.6,14.6,8.7,BLUSH,MSO_SHAPE.RECTANGLE)
    scatter_blossoms(s,[(1.2,1.0,0.85,BLUSH_2),(2.1,0.6,0.5,BLOSSOM),(11.9,6.7,0.85,BLUSH_2),
                        (12.7,6.1,0.5,BLOSSOM),(0.7,6.6,0.55,BLUSH_2),(13.0,1.3,0.5,BLUSH_2)])
    text(s,1.5,2.0,10.3,1.0,[R("Autonomy you can trust.",46,INK,True,FONT_H)],align=PP_ALIGN.CENTER)
    text(s,1.5,3.15,10.3,0.6,
         [R("A multi-modal health agent that acts — ",17,INK_SOFT),R("and knows when to stop.",17,BLOSSOM_DK,True)],align=PP_ALIGN.CENTER)
    # three pillars
    pills=[("Innovation","governed autonomy",BLOSSOM_DK),("Trust","tamper-evident",LEAF),("Impact","screening at scale",SKY)]
    x=2.4
    for t,b,col in pills:
        glass(s,x,4.1,2.7,1.3,BG_PANEL)
        text(s,x,4.25,2.7,0.5,[R(t,15,col,True,FONT_H)],align=PP_ALIGN.CENTER)
        text(s,x,4.78,2.7,0.5,[R(b,11.5,INK_SOFT)],align=PP_ALIGN.CENTER)
        x+=2.95
    text(s,1.5,5.75,10.3,0.4,[R("MedicoScope Aegis · the future of autonomous healthcare",12.5,INK_SOFT,True)],align=PP_ALIGN.CENTER)
    text(s,1.5,6.25,10.3,0.4,[R("Thank you.",15,INK,True,FONT_H)],align=PP_ALIGN.CENTER)
    page_num(s,15)
