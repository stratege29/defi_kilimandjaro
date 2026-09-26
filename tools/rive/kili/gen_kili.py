#!/usr/bin/env python3
"""Générateur du rig Rive de Kili (margouillat) → `scene.rml` + textures.

Pourquoi un générateur plutôt que du RML écrit à la main : le skinning d'une
image (maillage triangulé, poids packés par sommet, pose de bind de chaque os)
est illisible et intenable à la main. Ici tout part de coordonnées pixel dans
`assets/kili/kili.png` (1024×757) — la même source que la version pur Flutter.

Usage (depuis la racine du repo) :
    python3 tools/rive/kili/gen_kili.py
    rive tools/rive/kili --once          # → tools/rive/kili/build/kili.riv
    cp tools/rive/kili/build/kili.riv assets/kili/kili.riv

Structure produite :
- calques : ombre, queue (maillage, derrière), corps (maillage), tête
  (image rigide sur l'os Head), paupières (vectorielles, clippées), « Zzz » ;
- os : Ground (pieds, fixe), Body → Neck → Head, Tail0..Tail5 (enfant de Body) ;
- view model `Kili` : `mood` (0 idle, 1 joie, 2 triste, 3 dort) + triggers
  `nod` (hochement / pompes du margouillat) et `cheer` (saut de victoire) ;
- state machine à 2 couches : Body (humeurs + one-shots) et Eyes (clignements).
"""

from __future__ import annotations

import base64
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = Path(__file__).resolve().parent
ASSETS = HERE.parents[2] / "assets" / "kili"

W, H = 1024, 757          # canvas source
TOP = 90                  # marge au-dessus de la tête (saut de victoire)
AW, AH = W, H + TOP       # artboard
PIVOT = (512.0, 718.0 + TOP)   # pieds : pivot squash & stretch du nœud racine
STEP = 18                 # pas de la grille du maillage (px)

# ---------------------------------------------------------------------------
# Squelette — coordonnées pixel de l'image source (y sans la marge TOP)
# ---------------------------------------------------------------------------
BONE_BODY = ((610, 520), (360, 450))
BONE_NECK = ((360, 450), (330, 350))
BONE_HEAD = ((330, 350), (300, 150))
TAIL_PTS = [(640, 410), (730, 500), (840, 505), (885, 395),
            (840, 295), (745, 280), (668, 335)]
GROUND = (512, 718)

# Polygone de la queue (pixels attribués à la texture « tail »).
TAIL_POLY = [(655, 225), (970, 225), (970, 660), (706, 660),
             (706, 560), (690, 482), (645, 398), (655, 382)]
BASE_BLEND = 44.0  # px : fondu corps↔queue à la racine de la queue

# Yeux (repère image) : centre, largeur, hauteur de l'ouverture.
EYES = {
    "L": ((158, 169), 58, 100),
    "R": ((392, 184), 112, 108),
}
LID_TOP = "FFA93A21"
LID_BOTTOM = "FFD8441E"
LASH = "FF4E2423"


def w(p):
    """Image → monde (artboard)."""
    return (float(p[0]), float(p[1]) + TOP)


def ang(a, b):
    return math.atan2(b[1] - a[1], b[0] - a[0])


def dist(a, b):
    return math.hypot(b[0] - a[0], b[1] - a[1])


def fmt(v):
    s = f"{v:.4f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


# ---------------------------------------------------------------------------
# Ids
# ---------------------------------------------------------------------------
_next = [100]


def nid():
    _next[0] += 1
    return f"0:{_next[0]}"


# ---------------------------------------------------------------------------
# Os : pose monde (pour les binds) + transform locale (pour le RML)
# ---------------------------------------------------------------------------
class Bone:
    def __init__(self, name, start, end, parent=None, root=False):
        self.name, self.parent, self.root = name, parent, root
        self.id = nid()
        self.start, self.end = w(start), w(end)
        self.length = dist(self.start, self.end)
        self.world_rot = ang(self.start, self.end)
        self.children = []
        if parent:
            parent.children.append(self)

    @property
    def local_rot(self):
        return self.world_rot - (self.parent.world_rot if self.parent else 0.0)

    def local_pos(self):
        """Position d'un RootBone dans l'espace de son parent."""
        if self.parent is None:
            return (self.start[0] - PIVOT[0], self.start[1] - PIVOT[1])
        # RootBone imbriqué dans un Bone : repère = origine de l'os parent,
        # axe x le long de l'os.
        px, py = self.parent.start
        dx, dy = self.start[0] - px, self.start[1] - py
        c, s = math.cos(-self.parent.world_rot), math.sin(-self.parent.world_rot)
        return (dx * c - dy * s, dx * s + dy * c)

    def bind(self):
        c, s = math.cos(self.world_rot), math.sin(self.world_rot)
        return c, s, -s, c, self.start[0], self.start[1]

    def to_local(self, p):
        """Monde → repère de l'os (pour les formes enfants)."""
        dx, dy = p[0] - self.start[0], p[1] - self.start[1]
        c, s = math.cos(-self.world_rot), math.sin(-self.world_rot)
        return (dx * c - dy * s, dx * s + dy * c)


ground = Bone("Ground", GROUND, (GROUND[0] + 40, GROUND[1]), root=True)
body = Bone("Body", *BONE_BODY, root=True)
neck = Bone("Neck", *BONE_NECK, parent=body)
head = Bone("Head", *BONE_HEAD, parent=neck)
tails = []
_parent = body
for i in range(len(TAIL_PTS) - 1):
    b = Bone(f"Tail{i}", TAIL_PTS[i], TAIL_PTS[i + 1], parent=_parent, root=(i == 0))
    tails.append(b)
    _parent = b

ALL_BONES = [ground, body, neck, head, *tails]
TENDON_INDEX = {b.name: i for i, b in enumerate(ALL_BONES)}


# ---------------------------------------------------------------------------
# Textures : découpe corps / queue
# ---------------------------------------------------------------------------
src = Image.open(ASSETS / "kili.png").convert("RGBA")
head_src = Image.open(ASSETS / "kili_head.png").convert("RGBA")
assert src.size == (W, H) and head_src.size == (W, H)

poly_mask = Image.new("L", (W, H), 0)
ImageDraw.Draw(poly_mask).polygon(TAIL_POLY, fill=255)
poly = np.asarray(poly_mask).astype(np.float32) / 255.0

# Profondeur dans le polygone (distance approx. au bord gauche), via flous
# successifs : 0 au bord, 1 à BASE_BLEND px à l'intérieur.
depth = np.asarray(poly_mask.filter(ImageFilter.BoxBlur(BASE_BLEND / 2))).astype(np.float32) / 255.0
depth = np.clip((depth - 0.5) * 2.0, 0, 1) * poly

src_a = np.asarray(src).astype(np.float32)
alpha = src_a[..., 3] / 255.0

# Queue : pixels du polygone. Corps : le reste, avec la racine de la queue
# conservée en fondu (les deux maillages y ont les mêmes poids → pas de couture).
tail_rgba = src_a.copy()
tail_rgba[..., 3] = src_a[..., 3] * poly
# La tête reste AUSSI dans le corps, pondérée 100 % sur l'os Head (voir
# body_weights) : les deux copies bougent ensemble, et le corps sert de filet
# si la texture tête n'est pas encore décodée au premier rendu.
body_rgba = src_a.copy()
body_rgba[..., 3] = src_a[..., 3] * (1.0 - depth)
Image.fromarray(tail_rgba.astype(np.uint8)).save(HERE / "tail.png", optimize=True)
Image.fromarray(body_rgba.astype(np.uint8)).save(HERE / "body.png", optimize=True)
head_src.save(HERE / "head.png", optimize=True)

head_alpha = np.asarray(
    Image.fromarray((np.asarray(head_src)[..., 3]).astype(np.uint8)).filter(ImageFilter.GaussianBlur(4))
).astype(np.float32) / 255.0


# Sommets juste HORS de la silhouette de tête : sans ça, leurs triangles
# (à cheval sur le bord) traînent derrière la tête quand elle pivote → bord
# dentelé. On dilate donc le masque tête de ~1 maille, mais seulement
# au-dessus du menton (y < 280) : plus bas, le sac à dos et le cou doivent
# rester sur le corps.
_solid = Image.fromarray(((np.asarray(head_src)[..., 3] > 240) * 255).astype(np.uint8))
head_dilated = np.asarray(_solid.filter(ImageFilter.MaxFilter(2 * STEP + 7))).astype(np.float32) / 255.0
head_dilated[280:, :] = 0.0


def sample(arr, x, y):
    xi = int(min(max(round(x), 0), W - 1))
    yi = int(min(max(round(y), 0), H - 1))
    return float(arr[yi, xi])


def smoothstep(a, b, x):
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def seg_dist(p, a, b):
    ax, ay = a
    bx, by = b
    dx, dy = bx - ax, by - ay
    t = ((p[0] - ax) * dx + (p[1] - ay) * dy) / (dx * dx + dy * dy)
    t = min(max(t, 0.0), 1.0)
    return math.hypot(p[0] - (ax + t * dx), p[1] - (ay + t * dy))


def tail_weights(x, y):
    p = (x, y)
    ds = [(seg_dist(p, TAIL_PTS[i], TAIL_PTS[i + 1]), f"Tail{i}") for i in range(len(tails))]
    ds.sort()
    raw = [(1.0 / (d + 10.0) ** 3, n) for d, n in ds[:2]]
    tot = sum(v for v, _ in raw)
    return {n: v / tot for v, n in raw}


def body_weights(x, y):
    """Poids « corps » (hors queue) — fonction continue de la position."""
    wts = {}
    h = max(smoothstep(0.1, 0.6, sample(head_alpha, x, y)), sample(head_dilated, x, y))
    rest = 1.0 - h
    if h > 0:
        wts["Head"] = h
    g = smoothstep(610, 705, y)
    n = (1.0 - smoothstep(360, 470, y)) * (1.0 - smoothstep(470, 560, x))
    wts["Ground"] = rest * g
    wts["Neck"] = rest * (1 - g) * n
    wts["Body"] = rest * (1 - g) * (1 - n)
    return wts


def weights_at(x, y, mesh):
    s = sample(depth, x, y)
    if mesh == "tail" and s <= 0 and sample(poly, x, y) > 0:
        s = 1.0
    bw = body_weights(x, y)
    tw = tail_weights(x, y)
    out = {}
    for k, v in bw.items():
        out[k] = out.get(k, 0) + v * (1 - s)
    for k, v in tw.items():
        out[k] = out.get(k, 0) + v * s
    return out


def pack(wts):
    items = sorted(((v, k) for k, v in wts.items() if v > 0.004), reverse=True)[:4]
    tot = sum(v for v, _ in items)
    vals = [int(round(255 * v / tot)) for v, _ in items]
    vals[0] += 255 - sum(vals)
    idx = values = 0
    for slot, ((_, k), v) in enumerate(zip(items, vals)):
        idx |= (TENDON_INDEX[k] + 1) << (8 * slot)
        values |= v << (8 * slot)
    return values, idx


def varuint(n):
    out = bytearray()
    while True:
        b = n & 0x7F
        n >>= 7
        out.append(b | 0x80 if n else b)
        if not n:
            return bytes(out)


def build_mesh(alpha_img, mesh_name, bbox):
    """Grille régulière, cellules vides (alpha nul, dilaté) éliminées."""
    a = np.asarray(Image.fromarray((alpha_img * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(7)))
    x0, y0, x1, y1 = bbox
    xs = list(range(x0, x1, STEP)) + [x1]
    ys = list(range(y0, y1, STEP)) + [y1]
    verts, index, tris = [], {}, []

    def vid(i, j):
        key = (i, j)
        if key not in index:
            index[key] = len(verts)
            verts.append((xs[i], ys[j]))
        return index[key]

    for j in range(len(ys) - 1):
        for i in range(len(xs) - 1):
            cell = a[ys[j]:ys[j + 1] + 1, xs[i]:xs[i + 1] + 1]
            if cell.size == 0 or cell.max() < 8:
                continue
            v00, v10 = vid(i, j), vid(i + 1, j)
            v11, v01 = vid(i + 1, j + 1), vid(i, j + 1)
            tris += [v00, v10, v11, v00, v11, v01]
    tb = base64.b64encode(b"".join(varuint(t) for t in tris)).decode()
    lines = [f'<Mesh triangleIndexBytes="{tb}" name="{mesh_name}">']
    for x, y in verts:
        wx, wy = w((x, y))
        values, idx = pack(weights_at(x, y, "tail" if "Tail" in mesh_name else "body"))
        lines.append(
            f'  <MeshVertex x="{fmt(x)}" y="{fmt(y)}" u="{fmt(x / W)}" v="{fmt(y / H)}">'
            f'<Weight values="{values}" indices="{idx}"/></MeshVertex>'
        )
    lines.append(f'  <Skin tx="0" ty="{TOP}" name="Skin">')
    for b in ALL_BONES:
        xx, xy, yx, yy, tx, ty = b.bind()
        lines.append(
            f'    <Tendon boneId="{b.id}" xx="{fmt(xx)}" xy="{fmt(xy)}" yx="{fmt(yx)}" '
            f'yy="{fmt(yy)}" tx="{fmt(tx)}" ty="{fmt(ty)}" name="{b.name}"/>'
        )
    lines.append("  </Skin>")
    lines.append("</Mesh>")
    return "\n".join(lines), len(verts), len(tris) // 3


def rigid_head_mesh():
    x0, y0, x1, y1 = 104, 34, 520, 382
    verts = [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]
    tb = base64.b64encode(b"".join(varuint(t) for t in [0, 1, 2, 0, 2, 3])).decode()
    hi = TENDON_INDEX["Head"] + 1
    lines = [f'<Mesh triangleIndexBytes="{tb}" name="HeadMesh">']
    for x, y in verts:
        lines.append(
            f'  <MeshVertex x="{x}" y="{y}" u="{fmt(x / W)}" v="{fmt(y / H)}">'
            f'<Weight values="255" indices="{hi}"/></MeshVertex>'
        )
    xx, xy, yx, yy, tx, ty = head.bind()
    lines.append(f'  <Skin tx="0" ty="{TOP}" name="Skin">')
    lines.append(
        f'    <Tendon boneId="{head.id}" xx="{fmt(xx)}" xy="{fmt(xy)}" yx="{fmt(yx)}" '
        f'yy="{fmt(yy)}" tx="{fmt(tx)}" ty="{fmt(ty)}" name="Head"/>'
    )
    lines.append("  </Skin>\n</Mesh>")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Scène
# ---------------------------------------------------------------------------
IDS = {k: nid() for k in [
    "artboard", "style", "sm", "vm", "vmi", "p_mood", "p_nod", "p_cheer",
    "kili", "shadow", "img_body", "img_tail", "img_head",
    "a_body", "a_tail", "a_head", "zs", "z1", "z2", "z3",
]}
LIDS = {}
for k in EYES:
    LIDS[k] = {"lid": nid(), "clip": nid(), "lash": nid()}

lx, ly = -PIVOT[0], TOP - PIVOT[1]   # position locale des images (origine 0,0)

body_mesh, bv, bt = build_mesh(alpha * (1.0 - depth), "BodyMesh", (104, 34, 922, 722))
tail_mesh, tv, tt = build_mesh(alpha * poly, "TailMesh", (640, 220, 940, 640))


def bone_xml(b, indent):
    pad = " " * indent
    if b.root:
        x, y = b.local_pos()
        head_ = (f'{pad}<RootBone x="{fmt(x)}" y="{fmt(y)}" length="{fmt(b.length)}" '
                 f'rotation="{fmt(b.local_rot)}" name="{b.name}" id="{b.id}"')
    else:
        head_ = (f'{pad}<Bone length="{fmt(b.length)}" rotation="{fmt(b.local_rot)}" '
                 f'name="{b.name}" id="{b.id}"')
    inner = [bone_xml(c, indent + 2) for c in b.children]
    if b is head:
        inner.append(eyes_xml(indent + 2))
    if not inner:
        return head_ + "/>"
    tag = "RootBone" if b.root else "Bone"
    return head_ + ">\n" + "\n".join(inner) + f"\n{pad}</{tag}>"


EYE_BOXES = {"L": (112, 104, 202, 238), "R": (322, 112, 468, 258)}


def _hull(points):
    pts = sorted(set(points))
    if len(pts) < 3:
        return pts

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lower, upper = [], []
    for p_ in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p_) <= 0:
            lower.pop()
        lower.append(p_)
    for p_ in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p_) <= 0:
            upper.pop()
        upper.append(p_)
    return lower[:-1] + upper[:-1]


def eye_shape(k):
    """Enveloppe convexe de l'œil (blanc + iris + contour sombre) dans
    `kili_head.png` : tout ce qui n'est pas de la peau orange, plus grande
    composante connexe de la boîte. Retourne (centre, points relatifs, h)."""
    x0, y0, x1, y1 = EYE_BOXES[k]
    px = np.asarray(head_src).astype(int)[y0:y1, x0:x1]
    r, g, b, a = px[..., 0], px[..., 1], px[..., 2], px[..., 3]
    skin = (r > 150) & (g < 120) & (b < 90)
    # Le trait brun du contour de l'œil touche celui de la tête (œil gauche,
    # vu de trois-quarts) : on l'exclut, puis on regonfle l'enveloppe.
    outline = (r < 130) & (g < 70) & (b < 70) & (r > g + 15)
    m = (~skin) & (~outline) & (a > 200)
    seen = np.zeros_like(m)
    best = []
    for sy_ in range(m.shape[0]):
        for sx_ in range(m.shape[1]):
            if not m[sy_, sx_] or seen[sy_, sx_]:
                continue
            stack, comp = [(sy_, sx_)], []
            seen[sy_, sx_] = True
            while stack:
                cy, cx = stack.pop()
                comp.append((cx + x0, cy + y0))
                for ny, nx in ((cy + 1, cx), (cy - 1, cx), (cy, cx + 1), (cy, cx - 1)):
                    if 0 <= ny < m.shape[0] and 0 <= nx < m.shape[1] and m[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        stack.append((ny, nx))
            if len(comp) > len(best):
                best = comp
    hull = _hull(best)
    cx = sum(p_[0] for p_ in hull) / len(hull)
    cy = sum(p_[1] for p_ in hull) / len(hull)
    rel = []
    for hx, hy in hull:  # léger gonflement pour couvrir l'anticrénelage
        dx, dy = hx - cx, hy - cy
        d = math.hypot(dx, dy) or 1.0
        rel.append((dx + 6.5 * dx / d, dy + 6.5 * dy / d))
    h = max(p_[1] for p_ in rel) - min(p_[1] for p_ in rel)
    return (cx, cy), rel, h


EYE_SHAPES = {k: eye_shape(k) for k in EYE_BOXES}
EYES = {k: (c, 0, h) for k, (c, _, h) in EYE_SHAPES.items()}


def _points_path(rel, pad):
    out = [f'{pad}<PointsPath isClosed="true" name="Path">']
    out += [f'{pad}  <StraightVertex x="{fmt(x)}" y="{fmt(y)}"/>' for x, y in rel]
    out.append(f"{pad}</PointsPath>")
    return out


def eyes_xml(indent):
    pad = " " * indent
    out = []
    # Premier déclaré = dessiné au-dessus : paupières avant leurs masques.
    for k, (c, rel, eh) in EYE_SHAPES.items():
        lx_, ly_ = head.to_local(w(c))
        rot = fmt(-head.world_rot)
        out.append(f'{pad}<Shape x="{fmt(lx_)}" y="{fmt(ly_)}" rotation="{rot}" name="EyeLid{k}">')
        # Trait de cils « œil fermé » : arc tombant, visible seulement en sommeil.
        ew_ = max(p_[0] for p_ in rel) - min(p_[0] for p_ in rel)
        arc = [(ew_ * (t / 6 - 0.5) * 0.8, eh * 0.12 + eh * 0.16 * (1 - ((t / 6 - 0.5) * 2) ** 2)) for t in range(7)]
        out.append(f'{pad}  <Shape opacity="0" name="Lash{k}" id="{LIDS[k]["lash"]}">')
        out.append(f'{pad}    <PointsPath isClosed="false" name="Path">')
        out += [f'{pad}      <StraightVertex x="{fmt(x)}" y="{fmt(y)}"/>' for x, y in arc]
        out.append(f'{pad}    </PointsPath>')
        out.append(f'{pad}    <Stroke thickness="7" cap="round" join="round" name="S"><SolidColor colorValue="{LASH}" name="C"/></Stroke>')
        out.append(f'{pad}  </Shape>')
        out.append(f'{pad}  <Shape y="{fmt(-(eh + 8))}" name="Lid{k}" id="{LIDS[k]["lid"]}">')
        out += _points_path(rel, pad + "    ")
        out.append(f'{pad}    <Fill name="Fill"><LinearGradient startX="0" startY="{fmt(-eh / 2)}" endX="0" endY="{fmt(eh / 2)}" name="G">'
                   f'<GradientStop colorValue="{LID_TOP}" position="0"/>'
                   f'<GradientStop colorValue="{LID_BOTTOM}" position="1"/></LinearGradient></Fill>')
        out.append(f'{pad}    <Stroke thickness="7" cap="round" join="round" name="Lash"><SolidColor colorValue="{LASH}" name="C"/></Stroke>')
        out.append(f'{pad}    <ClippingShape sourceId="{LIDS[k]["clip"]}" name="Clip"/>')
        out.append(f"{pad}  </Shape>")
        out.append(f'{pad}  <Shape name="EyeMask{k}" id="{LIDS[k]["clip"]}">')
        out += _points_path(rel, pad + "    ")
        out.append(f"{pad}  </Shape>")
        out.append(f"{pad}</Shape>")
    return "\n".join(out)


def z_xml():
    zx, zy = w((500, 60))
    parts = [f'  <Node x="{fmt(zx - PIVOT[0])}" y="{fmt(zy - PIVOT[1])}" name="Zzz" id="{IDS["zs"]}">']
    for i, (key, s, dx, dy) in enumerate([("z1", 20, 0, 0), ("z2", 26, 36, -46), ("z3", 32, 80, -104)]):
        parts.append(f'    <Shape x="{dx}" y="{dy}" opacity="0" name="Z{i + 1}" id="{IDS[key]}">')
        parts.append('      <PointsPath isClosed="false" name="Path">')
        for vx, vy in [(-s, -s), (s, -s), (-s, s), (s, s)]:
            parts.append(f'        <StraightVertex x="{vx}" y="{vy}"/>')
        parts.append("      </PointsPath>")
        parts.append('      <Stroke thickness="13" cap="round" join="round" name="Outline"><SolidColor colorValue="FF1E3A34" name="C"/></Stroke>')
        parts.append('      <Stroke thickness="7" cap="round" join="round" name="Ink"><SolidColor colorValue="FFE9B949" name="C"/></Stroke>')
        parts.append("    </Shape>")
    parts.append("  </Node>")
    return "\n".join(parts)


# ---------------------------------------------------------------------------
# Animations
# ---------------------------------------------------------------------------
P_X, P_Y, P_ROT, P_SX, P_SY, P_OP = 13, 14, 15, 16, 17, 18
EASE = {
    "io": (0.42, 0, 0.58, 1),
    "out": (0.0, 0.0, 0.58, 1.0),
    "in": (0.42, 0.0, 1.0, 1.0),
    "back": (0.34, 1.56, 0.64, 1.0),   # dépassement (overshoot)
    "snap": (0.2, 0.9, 0.3, 1.0),
}

# (objet, propriété) → valeur de repos. Chaque animation de la couche Body
# clé TOUTES ces pistes : sinon une piste non clée garde la valeur laissée
# par l'état précédent (queue figée en plein balancement, Z restés visibles…).
REST = {
    (IDS["kili"], P_Y): PIVOT[1],
    (IDS["kili"], P_SX): 1.0,
    (IDS["kili"], P_SY): 1.0,
    (body.id, P_ROT): body.local_rot,
    (neck.id, P_ROT): neck.local_rot,
    (head.id, P_ROT): head.local_rot,
    (IDS["shadow"], P_SX): 1.0,
    (IDS["shadow"], P_OP): 1.0,
    (IDS["z1"], P_OP): 0.0,
    (IDS["z2"], P_OP): 0.0,
    (IDS["z3"], P_OP): 0.0,
    (IDS["zs"], P_Y): 0.0,
}
for t in tails:
    REST[(t.id, P_ROT)] = t.local_rot
REST_Z_Y = float(w((500, 60))[1] - PIVOT[1])
REST[(IDS["zs"], P_Y)] = REST_Z_Y
ABSOLUTE = {(IDS["kili"], P_SX), (IDS["kili"], P_SY), (IDS["shadow"], P_SX),
            (IDS["shadow"], P_OP), (IDS["z1"], P_OP), (IDS["z2"], P_OP), (IDS["z3"], P_OP)}


class Anim:
    def __init__(self, name, frames, loop):
        self.name, self.frames, self.loop = name, frames, loop
        self.id = nid()
        self.tracks = {}

    def key(self, obj, prop, frames):
        """frames : [(frame, valeur, ease)] — valeur = delta sur le repos,
        sauf pour échelles/opacités (absolues)."""
        self.tracks[(obj, prop)] = frames
        return self

    def wave(self, obj, amp, period, phase=0.0, step=6, bias=0.0):
        pts = []
        for f in range(0, self.frames + 1, step):
            pts.append((f, bias + amp * math.sin(2 * math.pi * f / period + phase), None))
        if pts[-1][0] != self.frames:
            f = self.frames
            pts.append((f, bias + amp * math.sin(2 * math.pi * f / period + phase), None))
        self.tracks[(obj, P_ROT)] = pts
        return self

    def xml(self, full=True):
        loop = ' loopValue="loop"' if self.loop else ""
        out = [f'  <LinearAnimation{loop} duration="{self.frames}" name="{self.name}" id="{self.id}">']
        keys = dict(self.tracks)
        if full:
            for k in REST:
                keys.setdefault(k, [(0, None, None)])
        by_obj = {}
        for (obj, prop), frames in keys.items():
            by_obj.setdefault(obj, []).append((prop, frames))
        for obj, props in by_obj.items():
            out.append(f'    <KeyedObject objectId="{obj}">')
            for prop, frames in props:
                out.append(f'      <KeyedProperty propertyKey="{prop}">')
                for f, val, ease in frames:
                    base = REST.get((obj, prop), 0.0)
                    if val is None:
                        v = base
                    elif (obj, prop) in ABSOLUTE:
                        v = val
                    else:
                        v = base + val * SIGN.get((obj, prop), 1.0)
                    if ease:
                        x1, y1, x2, y2 = EASE[ease]
                        out.append(
                            f'        <KeyFrameDouble value="{fmt(v)}" frame="{f}" interpolationType="cubic">'
                            f'<CubicEaseInterpolator x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}"/></KeyFrameDouble>'
                        )
                    else:
                        out.append(f'        <KeyFrameDouble value="{fmt(v)}" frame="{f}" interpolationType="linear"/>')
                out.append("      </KeyedProperty>")
            out.append("    </KeyedObject>")
        out.append("  </LinearAnimation>")
        return "\n".join(out)


K = IDS["kili"]
SH = IDS["shadow"]
anims = {}

# Convention d'écriture des deltas : une valeur POSITIVE baisse le museau
# (tête/cou) et abaisse la poitrine (Body). En repère écran (y vers le bas),
# c'est l'inverse du sens de rotation natif de ces os, d'où le signe.
SIGN = {(body.id, P_ROT): -1.0, (neck.id, P_ROT): -1.0, (head.id, P_ROT): -1.0}

# --- idle : respiration + tête qui flâne + queue en vague lente (3 s) ------
a = Anim("idle", 180, True)
a.key(K, P_SY, [(0, 1.0, "io"), (90, 1.014, "io"), (180, 1.0, None)])
a.key(K, P_SX, [(0, 1.0, "io"), (90, 0.994, "io"), (180, 1.0, None)])
a.key(body.id, P_ROT, [(0, 0, "io"), (90, -0.018, "io"), (180, 0, None)])
a.key(neck.id, P_ROT, [(0, 0, "io"), (90, 0.012, "io"), (180, 0, None)])
a.key(head.id, P_ROT, [(0, 0, "io"), (55, 0.035, "io"), (120, -0.02, "io"), (180, 0, None)])
a.key(SH, P_SX, [(0, 1.0, "io"), (90, 1.012, "io"), (180, 1.0, None)])
for i, t in enumerate(tails):
    a.wave(t.id, 0.03 + 0.012 * i, 180, phase=-0.7 * i)
anims["idle"] = a

# --- happy : petits sauts de joie + queue qui frétille (1,2 s) --------------
a = Anim("happy", 72, True)
a.key(K, P_Y, [(0, 0, "out"), (8, 3, "out"), (26, -26, "in"), (44, 0, "out"), (50, 2, "io"), (72, 0, None)])
a.key(K, P_SY, [(0, 1.0, "out"), (8, 0.94, "out"), (20, 1.05, "io"), (44, 0.95, "out"), (54, 1.0, "io"), (72, 1.0, None)])
a.key(K, P_SX, [(0, 1.0, "out"), (8, 1.04, "out"), (20, 0.97, "io"), (44, 1.04, "out"), (54, 1.0, "io"), (72, 1.0, None)])
a.key(body.id, P_ROT, [(0, 0, "io"), (26, -0.05, "io"), (50, 0.01, "io"), (72, 0, None)])
a.key(head.id, P_ROT, [(0, 0.04, "io"), (36, -0.06, "io"), (72, 0.04, None)])
a.key(SH, P_SX, [(0, 1.0, "out"), (26, 0.86, "in"), (44, 1.0, "out"), (72, 1.0, None)])
a.key(SH, P_OP, [(0, 1.0, "out"), (26, 0.7, "in"), (44, 1.0, "out"), (72, 1.0, None)])
for i, t in enumerate(tails):
    a.wave(t.id, 0.05 + 0.02 * i, 36, phase=-0.9 * i, step=4)
anims["happy"] = a

# --- sad : tête basse, queue tombante, respiration lente (4 s) --------------
a = Anim("sad", 240, True)
a.key(K, P_SY, [(0, 0.985, "io"), (120, 0.995, "io"), (240, 0.985, None)])
a.key(body.id, P_ROT, [(0, 0.05, "io"), (120, 0.04, "io"), (240, 0.05, None)])
a.key(neck.id, P_ROT, [(0, 0.08, "io"), (120, 0.06, "io"), (240, 0.08, None)])
a.key(head.id, P_ROT, [(0, 0.16, "io"), (140, 0.2, "io"), (240, 0.16, None)])
for i, t in enumerate(tails):
    a.wave(t.id, 0.012, 240, phase=-0.5 * i, bias=0.05 + 0.02 * i, step=12)
anims["sad"] = a

# --- sleep : tête posée, grande respiration, « Zzz » qui montent (4 s) -----
a = Anim("sleep", 240, True)
a.key(K, P_SY, [(0, 0.97, "io"), (120, 1.0, "io"), (240, 0.97, None)])
a.key(K, P_SX, [(0, 1.01, "io"), (120, 0.995, "io"), (240, 1.01, None)])
a.key(body.id, P_ROT, [(0, 0.07, "io"), (120, 0.05, "io"), (240, 0.07, None)])
a.key(neck.id, P_ROT, [(0, 0.1, "io"), (120, 0.08, "io"), (240, 0.1, None)])
a.key(head.id, P_ROT, [(0, 0.24, "io"), (120, 0.21, "io"), (240, 0.24, None)])
for i, t in enumerate(tails):
    a.wave(t.id, 0.006, 240, phase=-0.4 * i, bias=0.02 * i, step=24)
a.key(IDS["zs"], P_Y, [(0, 0, None), (240, -40, None)])
for i, z in enumerate(["z1", "z2", "z3"]):
    s = 20 + i * 50
    a.key(IDS[z], P_OP, [(0, 0.0, None), (s, 0.0, "out"), (s + 30, 1.0, "io"), (s + 90, 1.0, "in"),
                         (min(s + 130, 240), 0.0, None), (240, 0.0, None)])
anims["sleep"] = a

# --- nod : les « pompes » du margouillat, deux fois (0,9 s) -----------------
a = Anim("nod", 54, False)
a.key(body.id, P_ROT, [(0, 0, "snap"), (8, -0.09, "io"), (18, 0.015, "snap"), (28, -0.08, "io"), (38, 0.01, "io"), (54, 0, None)])
a.key(neck.id, P_ROT, [(0, 0, "snap"), (8, -0.03, "io"), (18, 0.05, "snap"), (28, -0.03, "io"), (38, 0.04, "io"), (54, 0, None)])
a.key(head.id, P_ROT, [(0, 0, "snap"), (8, -0.04, "io"), (18, 0.11, "snap"), (28, -0.03, "io"), (38, 0.1, "io"), (54, 0, None)])
a.key(K, P_SY, [(0, 1.0, "snap"), (8, 1.03, "io"), (18, 0.985, "snap"), (28, 1.025, "io"), (38, 0.99, "io"), (54, 1.0, None)])
for i, t in enumerate(tails):
    a.key(t.id, P_ROT, [(0, 0, "io"), (14, -0.04 - 0.01 * i, "io"), (34, 0.03 + 0.01 * i, "io"), (54, 0, None)])
anims["nod"] = a

# --- cheer : anticipation, saut, réception écrasée, rebond (1,25 s) --------
a = Anim("cheer", 75, False)
a.key(K, P_Y, [(0, 0, "io"), (10, 4, "out"), (28, -92, "io"), (34, -94, "in"), (48, 0, "out"), (56, 3, "io"), (75, 0, None)])
a.key(K, P_SY, [(0, 1.0, "io"), (10, 0.86, "out"), (20, 1.12, "io"), (34, 1.0, "in"), (48, 1.04, "out"), (53, 0.84, "back"), (66, 1.0, None), (75, 1.0, None)])
a.key(K, P_SX, [(0, 1.0, "io"), (10, 1.1, "out"), (20, 0.92, "io"), (34, 1.0, "in"), (48, 0.98, "out"), (53, 1.12, "back"), (66, 1.0, None), (75, 1.0, None)])
a.key(body.id, P_ROT, [(0, 0, "io"), (10, 0.04, "out"), (26, -0.1, "io"), (48, 0.02, "out"), (60, 0, None), (75, 0, None)])
a.key(neck.id, P_ROT, [(0, 0, "io"), (10, 0.04, "out"), (26, -0.06, "io"), (48, 0.03, "back"), (64, 0, None), (75, 0, None)])
a.key(head.id, P_ROT, [(0, 0, "io"), (10, 0.08, "out"), (26, -0.14, "io"), (48, 0.06, "back"), (64, 0, None), (75, 0, None)])
a.key(SH, P_SX, [(0, 1.0, "io"), (10, 1.06, "out"), (30, 0.62, "in"), (48, 1.08, "out"), (60, 1.0, None), (75, 1.0, None)])
a.key(SH, P_OP, [(0, 1.0, "io"), (30, 0.45, "in"), (48, 1.0, None), (75, 1.0, None)])
for i, t in enumerate(tails):
    a.key(t.id, P_ROT, [(0, 0, "io"), (10, 0.06 + 0.01 * i, "out"), (28, -0.1 - 0.03 * i, "io"),
                        (50, 0.08 + 0.02 * i, "back"), (66, 0, None), (75, 0, None)])
anims["cheer"] = a

# --- paupières (couche Eyes) -------------------------------------------------
eye_anims = {}


def lid_track(an, frames):
    for k, (c, ew, eh) in EYES.items():
        closed_y = 3.0
        open_y = -(eh + 8)
        pts = [(f, open_y + (closed_y - open_y) * v, e) for f, v, e in frames]
        an.tracks[(LIDS[k]["lid"], P_Y)] = pts
        # Arc de cils : opaque seulement quand la paupière est close > 90 %.
        an.tracks[(LIDS[k]["lash"], P_OP)] = [(f, 1.0 if v > 0.9 else 0.0, e) for f, v, e in frames]


def abs_track_xml(an):
    # Les pistes paupières sont absolues : on passe par ABSOLUTE.
    for k in EYES:
        ABSOLUTE.add((LIDS[k]["lid"], P_Y))
        ABSOLUTE.add((LIDS[k]["lash"], P_OP))
    return an.xml(full=False)


a = Anim("blink", 300, True)
lid_track(a, [(0, 0, None), (96, 0, "in"), (101, 1, "out"), (110, 0, None), (246, 0, "in"),
              (250, 1, "out"), (256, 0.1, "in"), (260, 1, "out"), (268, 0, None), (300, 0, None)])
eye_anims["blink"] = a
a = Anim("eyesSad", 240, True)
lid_track(a, [(0, 0.42, None), (150, 0.42, "in"), (156, 1, "out"), (166, 0.42, None), (240, 0.42, None)])
eye_anims["eyesSad"] = a
a = Anim("eyesClosed", 60, True)
lid_track(a, [(0, 1, None), (60, 1, None)])
eye_anims["eyesClosed"] = a
a = Anim("eyesHappy", 180, True)
lid_track(a, [(0, 0.12, None), (70, 0.12, "in"), (75, 1, "out"), (84, 0.12, None), (180, 0.12, None)])
eye_anims["eyesHappy"] = a


# ---------------------------------------------------------------------------
# State machine (pilotée par le view model)
# ---------------------------------------------------------------------------
def cond_mood(op, value):
    return (
        f'<TransitionViewModelCondition opValue="{op}">'
        f'<TransitionPropertyViewModelComparator><BindablePropertyNumber>'
        f'<DataBindContext sourcePathIds="{IDS["vm"]}-{IDS["p_mood"]}" propertyKey="636"/>'
        f'</BindablePropertyNumber></TransitionPropertyViewModelComparator>'
        f'<TransitionValueNumberComparator value="{value}"/></TransitionViewModelCondition>'
    )


def cond_trigger(pid):
    return (
        f'<TransitionViewModelCondition><TransitionPropertyViewModelComparator>'
        f'<BindablePropertyTrigger><DataBindContext sourcePathIds="{IDS["vm"]}-{pid}" propertyKey="686"/>'
        f'</BindablePropertyTrigger></TransitionPropertyViewModelComparator>'
        f'<TransitionValueTriggerComparator/></TransitionViewModelCondition>'
    )


MOODS = ["idle", "happy", "sad", "sleep"]
st = {k: nid() for k in MOODS + ["nod", "cheer"]}
est = {k: nid() for k in ["blink", "eyesHappy", "eyesSad", "eyesClosed"]}
EYE_FOR_MOOD = ["blink", "eyesHappy", "eyesSad", "eyesClosed"]


def mood_layer():
    out = [f'    <StateMachineLayer name="Body" id="{nid()}">',
           '      <AnyState x="0" y="-160">']
    out.append(f'        <StateTransition stateToId="{st["cheer"]}" duration="80">{cond_trigger(IDS["p_cheer"])}</StateTransition>')
    out.append(f'        <StateTransition stateToId="{st["nod"]}" duration="80">{cond_trigger(IDS["p_nod"])}</StateTransition>')
    out.append("      </AnyState>")
    out.append('      <ExitState x="600" y="-160"/>')
    out.append(f'      <EntryState x="-300" y="0"><StateTransition stateToId="{st["idle"]}"/></EntryState>')
    for m_i, m in enumerate(MOODS):
        out.append(f'      <AnimationState x="{m_i * 220}" y="0" animationId="{anims[m].id}" id="{st[m]}">')
        for n_i, n in enumerate(MOODS):
            if n != m:
                out.append(f'        <StateTransition stateToId="{st[n]}" duration="450">{cond_mood("equal", n_i)}</StateTransition>')
        out.append("      </AnimationState>")
    for o_i, o in enumerate(["nod", "cheer"]):
        out.append(f'      <AnimationState x="{o_i * 300 + 150}" y="200" animationId="{anims[o].id}" reset="true" id="{st[o]}">')
        for n_i, n in enumerate(MOODS):
            out.append(
                f'        <StateTransition stateToId="{st[n]}" duration="260" enableExitTime="true" '
                f'exitTimeIsPercetange="true" exitTime="100">{cond_mood("equal", n_i)}</StateTransition>'
            )
        out.append("      </AnimationState>")
    out.append("    </StateMachineLayer>")
    return "\n".join(out)


def eye_layer():
    out = [f'    <StateMachineLayer name="Eyes" id="{nid()}">',
           '      <AnyState x="0" y="-160"/>', '      <ExitState x="600" y="-160"/>',
           f'      <EntryState x="-300" y="0"><StateTransition stateToId="{est["blink"]}"/></EntryState>']
    for s_i, s in enumerate(EYE_FOR_MOOD):
        out.append(f'      <AnimationState x="{s_i * 220}" y="0" animationId="{eye_anims[s].id}" id="{est[s]}">')
        for n_i, n in enumerate(EYE_FOR_MOOD):
            if n != s:
                out.append(f'        <StateTransition stateToId="{est[n]}" duration="220">{cond_mood("equal", n_i)}</StateTransition>')
        out.append("      </AnimationState>")
    out.append("    </StateMachineLayer>")
    return "\n".join(out)


# ---------------------------------------------------------------------------
# Assemblage
# ---------------------------------------------------------------------------
sx, sy = w((520, 716))
parts = [
    '<Rive version="1" kind="fragment">',
    f'<Artboard defaultStateMachineId="{IDS["sm"]}" viewModelId="{IDS["vm"]}" viewModelInstanceId="{IDS["vmi"]}" '
    f'styleId="{IDS["style"]}" width="{AW}" height="{AH}" name="Kili" id="{IDS["artboard"]}">',
    f'  <LayoutComponentStyle name="Artboard Style" id="{IDS["style"]}"/>',
    f'  <Node x="{fmt(PIVOT[0])}" y="{fmt(PIVOT[1])}" name="Kili" id="{IDS["kili"]}">',
    z_xml(),
    # Ordre de dessin : le premier déclaré est au-dessus. Les os passent
    # avant les images parce que les paupières sont leurs enfants.
    bone_xml(ground, 2),
    bone_xml(body, 2),
    f'  <Image x="{fmt(lx)}" y="{fmt(ly)}" originX="0" originY="0" assetId="{IDS["a_head"]}" name="Head" id="{IDS["img_head"]}">',
    rigid_head_mesh(),
    "  </Image>",
    f'  <Image x="{fmt(lx)}" y="{fmt(ly)}" originX="0" originY="0" assetId="{IDS["a_body"]}" name="Body" id="{IDS["img_body"]}">',
    body_mesh,
    "  </Image>",
    f'  <Image x="{fmt(lx)}" y="{fmt(ly)}" originX="0" originY="0" assetId="{IDS["a_tail"]}" name="Tail" id="{IDS["img_tail"]}">',
    tail_mesh,
    "  </Image>",
    "  </Node>",
    f'  <Shape x="{fmt(sx)}" y="{fmt(sy)}" name="Shadow" id="{SH}">',
    '    <Ellipse width="620" height="60" name="Path"/>',
    '    <Fill name="Fill"><RadialGradient startX="0" startY="0" endX="310" endY="0" name="G">'
    '<GradientStop colorValue="55102420" position="0"/><GradientStop colorValue="33102420" position="0.55"/>'
    '<GradientStop colorValue="00102420" position="1"/></RadialGradient></Fill>',
    "  </Shape>",
    f'  <StateMachine name="Kili" id="{IDS["sm"]}">',
    mood_layer(),
    eye_layer(),
    "  </StateMachine>",
]
for an in anims.values():
    parts.append(an.xml(full=True))
for an in eye_anims.values():
    parts.append(abs_track_xml(an))
parts += [
    "</Artboard>",
    f'<ViewModel defaultInstanceId="{IDS["vmi"]}" name="Kili" id="{IDS["vm"]}">',
    f'  <ViewModelPropertyNumber name="mood" id="{IDS["p_mood"]}"/>',
    f'  <ViewModelPropertyTrigger name="nod" id="{IDS["p_nod"]}"/>',
    f'  <ViewModelPropertyTrigger name="cheer" id="{IDS["p_cheer"]}"/>',
    f'  <ViewModelInstance exports="true" name="Default" id="{IDS["vmi"]}">',
    f'    <ViewModelInstanceNumber propertyValue="0" viewModelPropertyId="{IDS["p_mood"]}"/>',
    f'    <ViewModelInstanceTrigger viewModelPropertyId="{IDS["p_nod"]}"/>',
    f'    <ViewModelInstanceTrigger viewModelPropertyId="{IDS["p_cheer"]}"/>',
    "  </ViewModelInstance>",
    "</ViewModel>",
    f'<ImageAsset file="body.png" name="kili_body" id="{IDS["a_body"]}"/>',
    f'<ImageAsset file="tail.png" name="kili_tail" id="{IDS["a_tail"]}"/>',
    f'<ImageAsset file="head.png" name="kili_head" id="{IDS["a_head"]}"/>',
    "</Rive>",
]
(HERE / "scene.rml").write_text("\n".join(parts) + "\n")
print(f"scene.rml écrit — corps {bv} sommets/{bt} tri, queue {tv}/{tt}")
