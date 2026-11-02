"""Generates the animated SVG illustrations used in README.md (python3 docs/make_media.py)."""
from pathlib import Path

OUT = Path(__file__).parent / "anim"
OUT.mkdir(exist_ok=True)
FONT = "-apple-system, BlinkMacSystemFont, 'SF Pro Rounded', 'Segoe UI', Helvetica, Arial, sans-serif"

DEFS = """
<defs>
  <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0" stop-color="#150C3D"/><stop offset="1" stop-color="#05122E"/>
  </linearGradient>
  <linearGradient id="pb" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0" stop-color="#8B5CFF"/><stop offset="1" stop-color="#3DA5FF"/>
  </linearGradient>
  <radialGradient id="glowP"><stop offset="0" stop-color="#8B5CFF" stop-opacity=".45"/><stop offset="1" stop-color="#8B5CFF" stop-opacity="0"/></radialGradient>
  <radialGradient id="glowB"><stop offset="0" stop-color="#3DA5FF" stop-opacity=".35"/><stop offset="1" stop-color="#3DA5FF" stop-opacity="0"/></radialGradient>
  <filter id="glow" x="-50%" y="-50%" width="200%" height="200%">
    <feGaussianBlur stdDeviation="4" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge>
  </filter>
</defs>"""


def watermark(w, h):
    """CDAV.IO in the bottom-right corner: CDAV. white, IO #FFD905."""
    return f"""<text x="{w - 26}" y="{h - 22}" text-anchor="end" font-family="{FONT}" font-size="{max(15, h * .042):.0f}" font-weight="800" opacity=".9"><tspan fill="#FFFFFF">CDAV.</tspan><tspan fill="#FFD905">IO</tspan></text>"""


def svg(w, h, label, body):
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}" role="img" aria-label="{label}">
<title>{label}</title>{DEFS}
<clipPath id="card"><rect width="{w}" height="{h}" rx="28"/></clipPath>
<g clip-path="url(#card)">
<rect width="{w}" height="{h}" fill="url(#bg)"/>
<circle cx="{w * .12}" cy="{h * .1}" r="{h * .9}" fill="url(#glowP)"/>
<circle cx="{w * .9}" cy="{h * .95}" r="{h * .9}" fill="url(#glowB)"/>
{body}
{watermark(w, h)}
</g>
</svg>
"""


def phone(x, y, s=1.0):
    return f"""<g transform="translate({x} {y}) scale({s})">
  <rect x="-17" y="-30" width="34" height="60" rx="8" fill="#1B1442" stroke="url(#pb)" stroke-width="2.5"/>
  <rect x="-12" y="-23" width="24" height="44" rx="4" fill="url(#pb)" opacity=".85"/>
  <rect x="-6" y="-27" width="12" height="2.5" rx="1.2" fill="#0B0820"/>
</g>"""


def laptop(x, y, s=1.0):
    return f"""<g transform="translate({x} {y}) scale({s})">
  <rect x="-30" y="-24" width="60" height="38" rx="5" fill="#1B1442" stroke="url(#pb)" stroke-width="2.5"/>
  <rect x="-25" y="-19" width="50" height="28" rx="2" fill="url(#pb)" opacity=".85"/>
  <path d="M-38 16 H38 L33 22 H-33 Z" fill="#8F86FF"/>
</g>"""


def waves(x, y, delay=0.0, r=70):
    rings = []
    for i in range(3):
        b = delay + i * 0.8
        rings.append(f"""<circle cx="{x}" cy="{y}" r="8" fill="none" stroke="#7E8CFF" stroke-width="2">
  <animate attributeName="r" values="8;{r}" dur="2.4s" begin="{b}s" repeatCount="indefinite"/>
  <animate attributeName="opacity" values=".9;0" dur="2.4s" begin="{b}s" repeatCount="indefinite"/>
</circle>""")
    return "\n".join(rings)


def bubble(path, text, dur=3.2, begin=0.0, width=64):
    return f"""<g filter="url(#glow)" opacity="0">
  <rect x="{-width / 2}" y="-13" width="{width}" height="26" rx="13" fill="url(#pb)"/>
  <text x="0" y="5" text-anchor="middle" font-family="{FONT}" font-size="13" font-weight="700" fill="#fff">{text}</text>
  <animateMotion path="{path}" dur="{dur}s" begin="{begin}s" repeatCount="indefinite" keyPoints="0;1;1" keyTimes="0;.75;1" calcMode="linear"/>
  <animate attributeName="opacity" values="0;1;1;0" keyTimes="0;.1;.8;1" dur="{dur}s" begin="{begin}s" repeatCount="indefinite"/>
</g>"""


def ticks(x, y, dur=3.2, begin=0.0):
    """Blue ✓✓ that appears when the bubble lands."""
    return f"""<text x="{x}" y="{y}" text-anchor="middle" font-family="{FONT}" font-size="16" font-weight="900" fill="#3DA5FF" opacity="0" filter="url(#glow)">✓✓
  <animate attributeName="opacity" values="0;0;1;0" keyTimes="0;.72;.8;1" dur="{dur}s" begin="{begin}s" repeatCount="indefinite"/>
</text>"""


def caption(w, h, text):
    return f"""<text x="{w / 2}" y="{h - 22}" text-anchor="middle" font-family="{FONT}" font-size="15" font-weight="600" fill="#C9C4FF" letter-spacing=".5">{text}</text>"""


def no_signal(x, y):
    return f"""<g transform="translate({x} {y})" opacity=".9">
  <rect x="0" y="12" width="5" height="6" rx="1" fill="#5A5480"/><rect x="8" y="8" width="5" height="10" rx="1" fill="#5A5480"/>
  <rect x="16" y="4" width="5" height="14" rx="1" fill="#5A5480"/><rect x="24" y="0" width="5" height="18" rx="1" fill="#5A5480"/>
  <path d="M-2 -2 L32 22" stroke="#FF5C7A" stroke-width="3" stroke-linecap="round"/>
</g>"""


W, H = 880, 360
scenes = {}

# 1 Highway: two cars, side by side
lanes = "".join(f'<rect x="{x}" y="196" width="50" height="5" rx="2" fill="#5A5480"><animate attributeName="x" values="{x};{x - 120}" dur="1s" repeatCount="indefinite"/></rect>' for x in range(0, 1000, 120))
def car(x, y, color):
    return f"""<g transform="translate({x} {y})">
  <rect x="-70" y="-24" width="140" height="48" rx="18" fill="{color}"/>
  <rect x="-30" y="-18" width="58" height="36" rx="10" fill="#0B0820" opacity=".55"/>
  <circle cx="-42" cy="26" r="11" fill="#0B0820"/><circle cx="42" cy="26" r="11" fill="#0B0820"/>
  <animateTransform attributeName="transform" type="translate" values="{x} {y};{x} {y - 3};{x} {y}" dur=".6s" repeatCount="indefinite"/>
</g>"""
scenes["01-highway"] = ("Two cars on the highway messaging over Bluetooth",
    f'<rect x="0" y="110" width="{W}" height="180" fill="#0E0A26"/><rect x="0" y="110" width="{W}" height="4" fill="#8F86FF" opacity=".5"/><rect x="0" y="286" width="{W}" height="4" fill="#8F86FF" opacity=".5"/>'
    + lanes + car(260, 155, "url(#pb)") + car(600, 245, "#8F86FF")
    + waves(270, 150) + phone(270, 150, .55) + phone(610, 240, .55)
    + bubble("M270 150 L610 240", "Exit 12?") + ticks(610, 205)
    + caption(W, H, "car to car · no signal needed"))

# 2 Airplane: seats far apart
seats = ""
for row in range(6):
    for col, cx in enumerate([180, 240, 330, 390, 480, 540, 630, 690]):
        seats += f'<rect x="{cx - 20 + (row * 0)}" y="{90 + row * 34}" width="40" height="26" rx="7" fill="#231A52" stroke="#3B2F78"/>'
scenes["02-airplane"] = ("Two seats apart on a plane, chatting in airplane mode",
    f'<rect x="120" y="60" width="640" height="240" rx="120" fill="#100B2C" stroke="#3B2F78" stroke-width="3"/>' + seats
    + phone(240, 133, .5) + phone(630, 235, .5) + waves(240, 133)
    + bubble("M240 133 L630 235", "Row 3? 👋") + ticks(630, 200)
    + f'<text x="800" y="70" font-size="34">✈️</text>'
    + caption(W, H, "airplane mode · bluetooth on"))

# 3 Festival: jammed network
crowd = "".join(f'<circle cx="{x}" cy="{250 + (x * 7) % 22}" r="13" fill="#2A2060"><animate attributeName="cy" values="{250 + (x * 7) % 22};{240 + (x * 7) % 22};{250 + (x * 7) % 22}" dur="{.5 + (x % 5) / 10}s" repeatCount="indefinite"/></circle>' for x in range(40, 860, 34))
scenes["03-festival"] = ("Messaging at a festival when the mobile network is jammed",
    f'<rect x="250" y="40" width="380" height="110" rx="10" fill="#1B1442" stroke="url(#pb)" stroke-width="3"/>'
    + "".join(f'<rect x="{280 + i * 60}" y="60" width="16" height="70" rx="3" fill="url(#pb)" opacity=".8"><animate attributeName="height" values="20;70;35;60;20" dur="{1 + i * .2}s" repeatCount="indefinite"/></rect>' for i in range(6))
    + crowd + phone(140, 210, .55) + phone(740, 205, .55) + waves(140, 210)
    + bubble("M140 210 Q440 120 740 205", "Front left!") + ticks(740, 170) + no_signal(800, 40)
    + caption(W, H, "network full · bluetooth still works"))

# 4 Mountains
scenes["04-mountains"] = ("Hiking in the mountains with zero signal",
    '<path d="M0 300 L170 120 L290 230 L430 70 L600 250 L720 150 L880 300 Z" fill="#1E1650"/>'
    '<path d="M430 70 L470 110 L450 105 L430 120 L410 104 L392 110 Z" fill="#E8E4FF"/>'
    '<path d="M170 120 L200 152 L170 145 L150 150 Z" fill="#E8E4FF"/>'
    + phone(250, 235, .5) + phone(610, 215, .5) + waves(250, 235)
    + bubble("M250 235 Q430 120 610 215", "Camp here ⛺") + ticks(610, 180) + no_signal(800, 40)
    + caption(W, H, "no towers · just bluetooth"))

# 5 Metro
cars = "".join(f'<rect x="{x}" y="140" width="190" height="100" rx="16" fill="#1B1442" stroke="url(#pb)" stroke-width="2"/>'
               + "".join(f'<rect x="{x + 20 + i * 40}" y="160" width="28" height="30" rx="4" fill="#3DA5FF" opacity=".35"/>' for i in range(4))
               for x in (120, 330, 540))
scenes["05-metro"] = ("Underground in the metro without signal",
    f'<path d="M40 300 Q440 20 840 300" fill="none" stroke="#3B2F78" stroke-width="40" opacity=".5"/>'
    f'<g>{cars}<animateTransform attributeName="transform" type="translate" values="0 0;-6 0;0 0" dur=".4s" repeatCount="indefinite"/></g>'
    '<rect x="80" y="244" width="720" height="6" fill="#5A5480"/>'
    + phone(215, 205, .45) + phone(635, 205, .45) + waves(215, 205)
    + bubble("M215 205 L635 205", "Next stop!") + ticks(635, 168) + no_signal(800, 40)
    + caption(W, H, "underground · still connected"))

# 6 Blackout / emergency
city = "".join(f'<rect x="{x}" y="{300 - hgt}" width="70" height="{hgt}" fill="#120D30" stroke="#2A2060"/>'
               for x, hgt in [(60, 140), (140, 200), (220, 110), (300, 170), (560, 190), (640, 120), (720, 210)])
scenes["06-blackout"] = ("Staying in touch during a blackout or emergency",
    '<circle cx="760" cy="70" r="28" fill="#E8E4FF" opacity=".85"/>' + city
    + phone(340, 250, .5) + phone(600, 250, .5) + waves(340, 250)
    + bubble("M340 250 Q470 160 600 250", "You OK? 🙏") + ticks(600, 215) + no_signal(60, 40)
    + caption(W, H, "network down · people nearby still reachable"))

# 7 Abroad / roaming
scenes["07-roaming"] = ("Abroad with no roaming costs",
    '<circle cx="440" cy="170" r="110" fill="#1B1442" stroke="url(#pb)" stroke-width="3"/>'
    '<ellipse cx="440" cy="170" rx="50" ry="110" fill="none" stroke="#3B2F78" stroke-width="2"/>'
    '<path d="M330 170 H550 M345 115 H535 M345 225 H535" stroke="#3B2F78" stroke-width="2"/>'
    '<g transform="translate(440 170)"><text x="0" y="12" text-anchor="middle" font-size="40" fill="#fff" font-family="sans-serif">€</text>'
    '<path d="M-28 -24 L28 30" stroke="#FF5C7A" stroke-width="5" stroke-linecap="round"/>'
    '<animateTransform attributeName="transform" type="rotate" values="0 0 0;8 0 0;0 0 0" additive="sum" dur="2s" repeatCount="indefinite"/></g>'
    + phone(180, 200, .55) + phone(700, 200, .55) + waves(180, 200)
    + bubble("M180 200 Q440 40 700 200", "0 € roaming") + ticks(700, 165)
    + caption(W, H, "no SIM · no data plan · free"))

# 8 Same building: office / school / campus
floors = "".join(f'<rect x="300" y="{60 + i * 60}" width="280" height="54" fill="#140F36" stroke="#2A2060"/>' for i in range(4))
scenes["08-building"] = ("Same building: office, school or campus",
    floors + phone(380, 117, .45) + laptop(510, 237, .9) + waves(380, 117)
    + bubble("M380 117 L510 230", "Lunch? 🍕", width=80) + ticks(560, 205)
    + caption(W, H, "phone ↔ mac · same floor or next room"))

# 9 Privacy: no servers
scenes["09-privacy"] = ("No servers, no account, no tracking",
    '<g transform="translate(440 110)" opacity=".9">'
    '<path d="M-70 20 Q-70 -20 -30 -20 Q-20 -55 20 -45 Q55 -60 65 -20 Q95 -15 90 20 Z" fill="#231A52" stroke="#3B2F78" stroke-width="3"/>'
    '<path d="M-60 -50 L80 40" stroke="#FF5C7A" stroke-width="6" stroke-linecap="round"/></g>'
    '<g transform="translate(440 250)" filter="url(#glow)"><rect x="-22" y="-10" width="44" height="34" rx="6" fill="url(#pb)"/>'
    '<path d="M-13 -10 V-20 A13 13 0 0 1 13 -20 V-10" fill="none" stroke="url(#pb)" stroke-width="5"/>'
    '<animateTransform attributeName="transform" type="scale" values="1;1.1;1" additive="sum" dur="1.6s" repeatCount="indefinite"/></g>'
    + phone(180, 240, .55) + phone(700, 240, .55) + waves(180, 240)
    + bubble("M180 240 L700 240", "🔒 E2E") + ticks(700, 205)
    + caption(W, H, "device to device · encrypted · nothing stored online"))

# 10 Sea / boat
water = "".join(f'<path d="M{x} 270 q30 -14 60 0 t60 0" fill="none" stroke="#3DA5FF" stroke-width="3" opacity=".5"><animateTransform attributeName="transform" type="translate" values="0 0;-40 0;0 0" dur="3s" repeatCount="indefinite"/></path>' for x in range(-40, 900, 120))
scenes["10-sea"] = ("At sea on a boat or ferry",
    '<g><path d="M160 210 H720 L660 270 H220 Z" fill="#1B1442" stroke="url(#pb)" stroke-width="3"/>'
    '<rect x="300" y="150" width="260" height="60" rx="8" fill="#231A52" stroke="#3B2F78"/>'
    '<rect x="420" y="100" width="20" height="50" fill="#3B2F78"/>'
    '<animateTransform attributeName="transform" type="rotate" values="-1.5 440 240;1.5 440 240;-1.5 440 240" dur="3s" repeatCount="indefinite"/></g>'
    + water + phone(330, 180, .45) + phone(560, 180, .45) + waves(330, 180)
    + bubble("M330 180 L560 180", "Deck 2 🌊", width=80) + ticks(560, 143) + no_signal(800, 40)
    + caption(W, H, "far from shore · still messaging"))

for name, (label, body) in scenes.items():
    (OUT / f"{name}.svg").write_text(svg(W, H, label, body))

# Hero: rotating radar + name
HW, HH = 1280, 440
cx, cy, r = 300, 220, 160
sweep = "".join(f'<path d="M{cx} {cy} L{cx} {cy - r} A{r} {r} 0 0 0 {cx - r * __import__("math").sin(i * .03):.1f} {cy - r * __import__("math").cos(i * .03):.1f} Z" fill="#3DA5FF" opacity="{.28 * (1 - i / 28):.3f}"/>' for i in range(1, 28))
hero = f"""
<g>
  <circle cx="{cx}" cy="{cy}" r="{r}" fill="#0B0824" stroke="url(#pb)" stroke-width="6" filter="url(#glow)"/>
  <circle cx="{cx}" cy="{cy}" r="{r * .66}" fill="none" stroke="#7E8CFF" stroke-opacity=".5" stroke-width="2"/>
  <circle cx="{cx}" cy="{cy}" r="{r * .33}" fill="none" stroke="#7E8CFF" stroke-opacity=".35" stroke-width="2"/>
  <g>{sweep}<path d="M{cx} {cy} L{cx} {cy - r}" stroke="#BFE3FF" stroke-width="4" filter="url(#glow)"/>
    <animateTransform attributeName="transform" type="rotate" from="0 {cx} {cy}" to="360 {cx} {cy}" dur="3s" repeatCount="indefinite"/></g>
  {waves(cx, cy, 0, r)}
  <circle cx="{cx}" cy="{cy}" r="12" fill="#fff" filter="url(#glow)"/>
  <g filter="url(#glow)"><circle cx="{cx + 85}" cy="{cy - 70}" r="10" fill="#E8E4FF"><animate attributeName="opacity" values=".2;1;.2" dur="3s" repeatCount="indefinite"/></circle>
  <circle cx="{cx - 60}" cy="{cy + 90}" r="9" fill="#E8E4FF"><animate attributeName="opacity" values="1;.2;1" dur="3s" repeatCount="indefinite"/></circle></g>
</g>
<text x="560" y="190" font-family="{FONT}" font-size="96" font-weight="800" fill="#fff">NonNet</text>
<text x="564" y="245" font-family="{FONT}" font-size="30" font-weight="600" fill="#C9C4FF">Offline Bluetooth Messenger</text>
<g font-family="{FONT}" font-size="18" font-weight="700" fill="#fff">
  <rect x="564" y="280" width="140" height="40" rx="20" fill="url(#pb)"/><text x="634" y="306" text-anchor="middle">No Wi-Fi</text>
  <rect x="716" y="280" width="160" height="40" rx="20" fill="url(#pb)"/><text x="796" y="306" text-anchor="middle">No Internet</text>
  <rect x="888" y="280" width="170" height="40" rx="20" fill="url(#pb)"/><text x="973" y="306" text-anchor="middle">No Account</text>
</g>
<text x="564" y="360" font-family="{FONT}" font-size="20" font-weight="600" fill="#8F86FF">iPhone · iPad · Mac · MacBook</text>
"""
(OUT / "hero.svg").write_text(svg(HW, HH, "NonNet offline Bluetooth messenger", hero))

# Footer: © 2026 CDAV.IO with CDAV. in white and IO in #FFD905
footer = f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 360 60" width="360" height="60" role="img" aria-label="© 2026 CDAV.IO">
<text x="180" y="40" text-anchor="middle" font-family="{FONT}" font-size="26" font-weight="800">
<tspan fill="#9A96B8">© 2026 </tspan><tspan fill="#FFFFFF">CDAV.</tspan><tspan fill="#FFD905">IO</tspan></text>
</svg>
"""
(OUT / "footer.svg").write_text(footer)
print("wrote", len(scenes) + 2, "files to", OUT)
