"""Digital clay: SDF sculpting (smooth booleans, displacement), marching-cubes meshing, decimation and a
hand-painted vertex-colour bake (AO, curvature edge-light, cavity, warm/cool key light, brush noise)."""
import numpy as np, math
from scipy.ndimage import map_coordinates, gaussian_filter
from skimage.measure import marching_cubes
import fast_simplification, trimesh
from PIL import Image, ImageFilter

# ------------------------------------------------------------------ noise
_rng = np.random.default_rng(11)
_LAT = gaussian_filter(_rng.random((40, 40, 40)).astype(np.float32), 0.9, mode='wrap')
_LAT = (_LAT - _LAT.min()) / (_LAT.max() - _LAT.min())

def vnoise(P, f, off=0.0):
    q = (P * f + off) % 40.0
    return map_coordinates(_LAT, [q[:, 0], q[:, 1], q[:, 2]], order=1, mode='wrap')

def fbm(P, f, octs=3, off=0.0):
    a = 1.0; t = 0.0; o = np.zeros(len(P), np.float32)
    for i in range(octs):
        o += a * vnoise(P, f * 2 ** i, off + i * 7.3); t += a; a *= 0.5
    return o / t

def hexc(h):
    h = h.lstrip('#'); return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], np.float32) / 255.0

def rotm(axis, ang):
    a = np.array(axis, float); a /= np.linalg.norm(a)
    K = np.array([[0, -a[2], a[1]], [a[2], 0, -a[0]], [-a[1], a[0], 0]])
    return np.eye(3) + math.sin(ang) * K + (1 - math.cos(ang)) * K @ K

def look_rot(d):
    """rotation taking +Y to direction d"""
    d = np.array(d, float); d /= np.linalg.norm(d); y = np.array([0, 1., 0]); ax = np.cross(y, d)
    if np.linalg.norm(ax) < 1e-6: return np.eye(3) if d[1] > 0 else rotm((1, 0, 0), math.pi)
    return rotm(ax, math.acos(np.clip(y @ d, -1, 1)))

# ------------------------------------------------------------------ shapes: each returns fn(P)->d
def sphere(c, r):
    c = np.array(c, float); return lambda P: np.linalg.norm(P - c, axis=1) - r

def ellipsoid(c, r, R=None):
    c = np.array(c, float); r = np.array(r, float)
    def f(P):
        q = P - c
        if R is not None: q = q @ R
        k0 = np.linalg.norm(q / r, axis=1); k1 = np.linalg.norm(q / (r * r), axis=1)
        return k0 * (k0 - 1.0) / np.maximum(k1, 1e-6)
    return f

def rcone(a, b, r1, r2):
    a = np.array(a, float); b = np.array(b, float)
    ba = b - a; l2 = ba @ ba; rr = r1 - r2; a2 = l2 - rr * rr; il2 = 1.0 / l2
    def f(P):
        pa = P - a; y = pa @ ba; z = y - l2
        t = pa * l2 - ba[None, :] * y[:, None]; x2 = (t * t).sum(1)
        y2 = y * y * l2; z2 = z * z * l2
        k = np.sign(rr) * rr * rr * x2
        return np.where(np.sign(z) * a2 * z2 > k, np.sqrt(x2 + z2) * il2 - r2,
                        np.where(np.sign(y) * a2 * y2 < k, np.sqrt(x2 + y2) * il2 - r1,
                                 (np.sqrt(x2 * a2 * il2) + y * rr) * il2 - r1))
    return f

def capsule(a, b, r): return rcone(a, b, r, r)

def rbox(c, h, rad=0.0, R=None):
    c = np.array(c, float); h = np.array(h, float) - rad
    def f(P):
        q = P - c
        if R is not None: q = q @ R
        q = np.abs(q) - h
        return np.linalg.norm(np.maximum(q, 0), axis=1) + np.minimum(q.max(1), 0) - rad
    return f

def cylinder(c, r, hh, R=None, rad=0.0):
    c = np.array(c, float)
    def f(P):
        q = P - c
        if R is not None: q = q @ R
        dx = np.linalg.norm(q[:, [0, 2]], axis=1) - (r - rad); dy = np.abs(q[:, 1]) - (hh - rad)
        return np.minimum(np.maximum(dx, dy), 0) + np.linalg.norm(np.stack([np.maximum(dx, 0), np.maximum(dy, 0)], 1), axis=1) - rad
    return f

def torus(c, R_, r, Rm=None):
    c = np.array(c, float)
    def f(P):
        q = P - c
        if Rm is not None: q = q @ Rm
        return np.hypot(np.linalg.norm(q[:, [0, 2]], axis=1) - R_, q[:, 1]) - r
    return f

def cone_y(c, r_bot, r_top, h, rad=0.0):
    """truncated cone along y (centre c at mid height)"""
    return rcone((c[0], c[1] - h / 2, c[2]), (c[0], c[1] + h / 2, c[2]), r_bot, r_top)

def shell(fn, t):
    return lambda P: np.abs(fn(P)) - t

def displace(fn, amp_fn):
    return lambda P: fn(P) + amp_fn(P)

def warp(fn, wfn):
    return lambda P: fn(wfn(P))

# ------------------------------------------------------------------ sculpt
class Sculpt:
    def __init__(self): self.ops = []
    def add(self, fn, col, k=0.0, g=0.0):
        self.ops.append(('add', fn, hexc(col) if isinstance(col, str) else np.array(col, np.float32), k, g)); return self
    def cut(self, fn, col='#3a2418', k=0.0, g=0.0):
        self.ops.append(('cut', fn, hexc(col) if isinstance(col, str) else np.array(col, np.float32), k, g)); return self
    def clip(self, fn):
        self.ops.append(('clip', fn, None, 0.0, 0.0)); return self

    def field(self, P, color=False):
        N = len(P); d = np.full(N, 9.0, np.float32)
        c = np.zeros((N, 3), np.float32) if color else None
        g = np.zeros(N, np.float32) if color else None
        for kind, fn, col, k, gl in self.ops:
            d2 = fn(P).astype(np.float32)
            if kind == 'clip':
                d = np.maximum(d, d2); continue
            if kind == 'add':
                if k <= 0:
                    m = d2 < d
                    if color:
                        c[m] = col; g[m] = gl
                    d = np.where(m, d2, d)
                else:
                    h = np.clip(0.5 + 0.5 * (d - d2) / k, 0, 1)
                    if color:
                        c = c * (1 - h[:, None]) + col[None, :] * h[:, None]; g = g * (1 - h) + gl * h
                    d = d * (1 - h) + d2 * h - k * h * (1 - h)
            else:
                nd2 = -d2
                if k <= 0:
                    m = nd2 > d
                    if color:
                        c[m] = col; g[m] = gl
                    d = np.maximum(d, nd2)
                else:
                    h = np.clip(0.5 - 0.5 * (d + d2) / k, 0, 1)
                    if color:
                        c = c * (1 - h[:, None]) + col[None, :] * h[:, None]; g = g * (1 - h) + gl * h
                    d = d * (1 - h) + nd2 * h + k * h * (1 - h)
        return (d, c, g) if color else d

    def mesh(self, lo, hi, vox, tris=None, style=None, post=None):
        lo = np.array(lo, float); hi = np.array(hi, float)
        n = np.ceil((hi - lo) / vox).astype(int) + 1
        xs = [lo[i] + np.arange(n[i]) * vox for i in range(3)]
        G = np.stack(np.meshgrid(*xs, indexing='ij'), -1).reshape(-1, 3).astype(np.float32)
        d = self.field(G).reshape(n)
        d[0, :, :] = d[-1, :, :] = 1; d[:, 0, :] = d[:, -1, :] = 1; d[:, :, 0] = d[:, :, -1] = 1
        if d.min() > 0 or d.max() < 0: raise ValueError('empty sculpt')
        v, f, _, _ = marching_cubes(d, 0.0, spacing=(vox, vox, vox))
        v = v + lo
        import os; tris = int(tris * float(os.environ.get('TRI_SCALE', '1'))) if tris else tris
        if tris and len(f) > tris:
            v, f = fast_simplification.simplify(v.astype(np.float32), f.astype(np.int32), target_reduction=1 - tris / len(f))
        return bake(self, np.asarray(v, np.float64), np.asarray(f, np.int64), vox, style or {}, post)

# ------------------------------------------------------------------ painted bake
class VMesh:
    def __init__(s, v, f, n, col, glow): s.v, s.f, s.n, s.col, s.glow = v, f, n, col, glow
    def copy(s): return VMesh(s.v.copy(), s.f.copy(), s.n.copy(), s.col.copy(), s.glow.copy())
    def tr(s, t): s.v = s.v + np.asarray(t, float); return s
    def merge(s, o):
        off = len(s.v); s.v = np.vstack([s.v, o.v]); s.f = np.vstack([s.f, o.f + off]); s.n = np.vstack([s.n, o.n])
        s.col = np.vstack([s.col, o.col]); s.glow = np.concatenate([s.glow, o.glow]); return s
    def rot(s, R, about=(0, 0, 0)):
        a = np.array(about, float); s.v = (s.v - a) @ R.T + a; s.n = s.n @ R.T; return s
    def mirror_x(s):
        m = s.copy(); m.v[:, 0] *= -1; m.n[:, 0] *= -1; m.f = m.f[:, ::-1]; return m
    def save(s, path):
        rgba = np.concatenate([np.clip(s.col, 0, 1), np.clip(s.glow, 0, 1)[:, None]], 1)
        uv = np.stack([s.glow, np.zeros_like(s.glow)], 1)
        tm = trimesh.Trimesh(vertices=s.v, faces=s.f, vertex_normals=s.n, process=False)
        tm.visual = trimesh.visual.ColorVisuals(tm, vertex_colors=(rgba * 255).astype(np.uint8))
        tm.export(path, file_type='glb')

KEY = np.array([-0.45, 0.82, 0.42]); KEY /= np.linalg.norm(KEY)
WARM = np.array([1.08, 0.97, 0.80]); COOL = np.array([0.50, 0.58, 0.70])

def bake(sc, V, F, vox, style, post):
    e = vox * 0.9
    def D(P): return sc.field(P.astype(np.float32))
    N = np.stack([D(V + [e, 0, 0]) - D(V - [e, 0, 0]), D(V + [0, e, 0]) - D(V - [0, e, 0]), D(V + [0, 0, e]) - D(V - [0, 0, e])], 1)
    N = N / np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-9)
    d0, col, glow = sc.field(V.astype(np.float32), True)
    # ambient occlusion (distance-field cone samples)
    sc_ao = style.get('ao_scale', 1.0)
    occ = np.zeros(len(V), np.float32)
    for i, s in enumerate((0.05, 0.12, 0.25, 0.5)):
        s = s * sc_ao
        occ += np.clip((s - D(V + N * s)) / s, 0, 1) * (0.5 ** i) * 0.55
    ao = np.clip(1.0 - occ, 0.25, 1.0)
    # curvature from SDF laplacian: convex = edge highlight, concave = cavity
    lap = (D(V + [e, 0, 0]) + D(V - [e, 0, 0]) + D(V + [0, e, 0]) + D(V - [0, e, 0]) + D(V + [0, 0, e]) + D(V - [0, 0, e]) - 6 * d0) / (e * e)
    edge = np.clip(lap * e * style.get('edge_k', 0.9), 0, 1); cav = np.clip(-lap * e * style.get('cav_k', 0.9), 0, 1)
    if post is not None:
        col, glow, extra = post(V, N, col, glow)
    else:
        extra = {}
    lam = np.clip(N @ KEY * 0.5 + 0.5, 0, 1) ** style.get('wrap', 1.35)
    # soft 4-band painted ramp (not hard cel): quantise lightly then blend
    q = np.round(lam * 4) / 4; lam = lam * 0.6 + q * 0.4
    light = COOL[None, :] * (1 - lam[:, None]) + WARM[None, :] * lam[:, None]
    bn = fbm(V, style.get('brush_f', 9.0), 3) - 0.5
    bn2 = fbm(V * [1, 4, 1], style.get('brush_f', 9.0) * 0.7, 2, 3.1) - 0.5
    shade = light * (0.62 + 0.55 * ao[:, None]) * (1 + bn[:, None] * 0.34 + bn2[:, None] * 0.18)
    out = col * shade
    out = out + edge[:, None] * np.array([0.30, 0.22, 0.10]) * style.get('edge_amt', 1.0) * (0.5 + lam[:, None])
    out = out * (1 - cav[:, None] * 0.38 * style.get('cav_amt', 1.0)) + cav[:, None] * np.array([0.02, 0.03, 0.06]) * 0.4
    # painterly hue drift: warm vs teal in big patches
    hd = fbm(V, style.get('drift_f', 2.0), 2, 9.7) - 0.5
    out = out * (1 + hd[:, None] * np.array([0.22, 0.0, -0.22]) * style.get('drift', 1.0))
    if 'dirt' in style:
        y0, y1, amt = style['dirt']
        t = np.clip(1 - (V[:, 1] - y0) / max(y1 - y0, 1e-3), 0, 1) ** 1.5
        out = out * (1 - t[:, None] * amt * np.array([0.35, 0.45, 0.55])) + t[:, None] * amt * np.array([0.10, 0.06, 0.03]) * 0.4
    out = np.where(glow[:, None] > 0.5, np.maximum(out, col * 1.2), out)  # glow stays luminous
    return VMesh(V, F, N, np.clip(out, 0, 1.2).astype(np.float32), np.clip(glow + extra.get('glow', 0), 0, 1).astype(np.float32))

# ------------------------------------------------------------------ preview renderer (gouraud + painted lighting + ink edge)
def _rm(ax, a):
    c, s = math.cos(a), math.sin(a)
    return np.array({'x': [[1, 0, 0], [0, c, -s], [0, s, c]], 'y': [[c, 0, s], [0, 1, 0], [-s, 0, c]]}[ax])

def render(meshes, size=(640, 800), yaw=0.5, pitch=-0.1, target=(0, 1, 0), dist=4.0, fov=30, ss=2, bg=('#f0c288', '#6fa6a3'), ink=True):
    W, H = size[0] * ss, size[1] * ss
    top, bot = hexc(bg[0]), hexc(bg[1]); t = np.linspace(0, 1, H)[:, None]
    img = (top[None, None, :] * (1 - t[..., None]) + bot[None, None, :] * t[..., None]) * np.ones((H, W, 3), np.float32)
    img = img.astype(np.float32); zb = np.full((H, W), 1e9, np.float32)
    R = _rm('x', -pitch) @ _rm('y', yaw); tgt = np.array(target, float)
    f = 1.0 / math.tan(math.radians(fov) / 2); asp = W / H
    Lw = R @ (KEY * np.array([1, 1, 1]))
    for m in meshes:
        vc = (m.v - tgt) @ R.T; vc[:, 2] += dist; nc = m.n @ R.T
        z = vc[:, 2]; sx = (vc[:, 0] / z * f / asp * 0.5 + 0.5) * W; sy = (0.5 - vc[:, 1] / z * f * 0.5) * H
        lit = np.clip(nc @ Lw * 0.5 + 0.5, 0, 1)
        vcol = m.col * (0.78 + 0.34 * lit[:, None]); vcol = np.where(m.glow[:, None] > 0.5, np.minimum(m.col * 1.15 + 0.15, 1), vcol)
        fn = np.cross(vc[m.f[:, 1]] - vc[m.f[:, 0]], vc[m.f[:, 2]] - vc[m.f[:, 0]]); fc = vc[m.f].mean(1)
        vis = (fn * fc).sum(1) < 0
        for tri in m.f[vis]:
            a, b, c = tri
            if z[a] < 0.1 or z[b] < 0.1 or z[c] < 0.1: continue
            x0, y0, x1, y1, x2, y2 = sx[a], sy[a], sx[b], sy[b], sx[c], sy[c]
            area = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0)
            if abs(area) < 1e-9: continue
            minx = max(int(min(x0, x1, x2)), 0); maxx = min(int(max(x0, x1, x2)) + 1, W - 1)
            miny = max(int(min(y0, y1, y2)), 0); maxy = min(int(max(y0, y1, y2)) + 1, H - 1)
            if minx > maxx or miny > maxy: continue
            gx, gy = np.meshgrid(np.arange(minx, maxx + 1) + 0.5, np.arange(miny, maxy + 1) + 0.5)
            w0 = ((x1 - gx) * (y2 - gy) - (x2 - gx) * (y1 - gy)) / area; w1 = ((x2 - gx) * (y0 - gy) - (x0 - gx) * (y2 - gy)) / area; w2 = 1 - w0 - w1
            msk = (w0 >= -1e-3) & (w1 >= -1e-3) & (w2 >= -1e-3)
            if not msk.any(): continue
            zi = w0 * z[a] + w1 * z[b] + w2 * z[c]
            sub = zb[miny:maxy + 1, minx:maxx + 1]; msk &= zi < sub
            if not msk.any(): continue
            out = w0[..., None] * vcol[a] + w1[..., None] * vcol[b] + w2[..., None] * vcol[c]
            sub[msk] = zi[msk]; img[miny:maxy + 1, minx:maxx + 1][msk] = out[msk]
    if ink:
        zz = np.where(zb > 1e8, 0, zb)
        e = (np.abs(np.diff(zz, axis=1, prepend=zz[:, :1])) > 0.03 * dist * 0.1) | (np.abs(np.diff(zz, axis=0, prepend=zz[:1, :])) > 0.03 * dist * 0.1)
        bgm = zb > 1e8; e &= ~((np.roll(bgm, 1, 0) & bgm) | (np.roll(bgm, 1, 1) & bgm))
        e = np.asarray(Image.fromarray((e * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(3))) > 0
        img[e] = img[e] * 0.3 + np.array([0.08, 0.04, 0.05]) * 0.7
    return Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8)).resize(size, Image.LANCZOS)
