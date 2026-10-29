import os, sys, json, math, pickle, time
os.environ.setdefault('TRI_SCALE', '0.6')
import numpy as np
from scipy.ndimage import map_coordinates, gaussian_filter
from sdf import *
import hero_v2, creatures_v2, env_v2
from rigv2 import Rig, MD, OUT

t0 = time.time()
data = {}

# ------------------------------------------------------------------ hero + IK aim pose
hero = hero_v2.build()
def swing(d):
    d = np.array(d, float); d /= np.linalg.norm(d); a = np.array([0, -1., 0]); ax = np.cross(a, d)
    if np.linalg.norm(ax) < 1e-6: return np.array([1., 0, 0]), 0.0
    return ax / np.linalg.norm(ax), math.acos(np.clip(a @ d, -1, 1))
def ik2(sh, tgt, l1, l2, hint):
    v = np.array(tgt) - np.array(sh); L = min(np.linalg.norm(v), l1 + l2 - 1e-3); u = v / np.linalg.norm(v)
    a = (l1 * l1 - l2 * l2 + L * L) / (2 * L); h = math.sqrt(max(l1 * l1 - a * a, 0))
    hint = np.array(hint, float); hp = hint - u * (hint @ u); hp /= np.linalg.norm(hp)
    return np.array(sh) + u * a + hp * h, np.array(sh) + u * L
spine_yaw = -0.52; Ry = rotm((0, 1, 0), spine_yaw); sp = hero.piv['spine'][1]
aim = {'spine_yaw': spine_yaw}; rots = {'spine': Ry}
for sd, grip in (('r', np.array([0.15, 1.30, -0.30])), ('l', np.array([0.14, 1.34, -0.52]))):
    sh = hero.piv[f'sh_{sd}'][1]; tl = np.linalg.inv(Ry) @ (grip - sp) + sp
    el, hand = ik2(sh, tl, 0.26, 0.28, np.array([1 if sd == 'r' else -1, -0.6, 0.0]))
    ax1, an1 = swing(el - sh); q1 = rotm(ax1, an1); ax2, an2 = swing(hand - el); q2 = np.linalg.inv(q1) @ rotm(ax2, an2)
    ang = math.acos(np.clip((np.trace(q2) - 1) / 2, -1, 1))
    ax2l = np.array([1., 0, 0]) if abs(ang) < 1e-5 else np.array([q2[2, 1] - q2[1, 2], q2[0, 2] - q2[2, 0], q2[1, 0] - q2[0, 1]]) / (2 * math.sin(ang))
    aim[f'sh_{sd}'] = [float(x) for x in ax1] + [float(an1)]; aim[f'el_{sd}'] = [float(x) for x in ax2l] + [float(ang)]
    rots[f'sh_{sd}'] = q1; rots[f'el_{sd}'] = q2
rots['head'] = rotm((0, 1, 0), -spine_yaw)
data['aim_pose'] = aim
data['hero'] = hero.export('hero')
pickle.dump((hero, rots), open('/tmp/hero_final.pkl', 'wb'))
print('hero', sum(len(m.f) for _, _, m in hero.parts), round(time.time() - t0), flush=True)

# ------------------------------------------------------------------ creatures
os.environ['TRI_SCALE'] = '0.5'
cr = {'hound': creatures_v2.hound(), 'husk': creatures_v2.husk(), 'burrower': creatures_v2.burrower()}
for k, r in cr.items(): data[k] = r.export(k)
pickle.dump(cr, open('/tmp/creatures_final.pkl', 'wb'))
print('creatures', round(time.time() - t0), flush=True)

# ------------------------------------------------------------------ environment kit
os.environ['TRI_SCALE'] = '0.7'
for (n, fn, lo, hi, vox, tris, st, post) in env_v2.PIECES:
    env_v2.mk(n, fn, lo, hi, vox, tris, st, post)
data['env'] = {}
for n, m in env_v2.M.items():
    fnm = f'env_{n}.glb'; m.save(f'{MD}/{fnm}'); data['env'][n] = [{'mesh': fnm, 'mat': 'painted'}]
pickle.dump(env_v2.M, open('/tmp/env_final.pkl', 'wb'))
print('env', sum(len(m.f) for m in env_v2.M.values()), round(time.time() - t0), flush=True)

# ------------------------------------------------------------------ terrain: heightfield + painted mesh
ZONES = {'st': (0, 0), 'se': (120, -40), 'co': (60, -150), 'fr': (-70, -170)}
ZONE_Y = {'st': 0.0, 'se': 1.0, 'co': 0.0, 'fr': -2.5}
X0, Z0, X1, Z1 = -180.0, -290.0, 220.0, 60.0
STEP = 3.0
xs = np.arange(X0, X1 + 0.01, STEP); zs = np.arange(Z0, Z1 + 0.01, STEP)
def noise2(X, Z, f, seed, octs=3):
    r = np.random.default_rng(seed); out = np.zeros_like(X); a = 1.0; tot = 0
    for o in range(octs):
        g = gaussian_filter(r.random((90, 90)), 1.0, mode='wrap'); g = (g - g.min()) / (g.max() - g.min())
        q = np.stack([(X * f * 2 ** o + 13.7 * o) % 90, (Z * f * 2 ** o + 5.1 * o) % 90])
        out += a * map_coordinates(g, q, order=1, mode='wrap'); tot += a; a *= 0.5
    return out / tot - 0.5
def smooth(a, b, x): t = np.clip((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t)
def height(X, Z):
    h = noise2(X, Z, 0.011, 4242) * 22.0 + noise2(X, Z, 0.09, 99, 2) * 1.2 + 3.0
    h += np.sin(X * 0.55 + Z * 0.17 + noise2(X, Z, 0.3, 7) * 8) * 0.12
    w = np.zeros_like(X); zy = np.zeros_like(X)
    for k, c in ZONES.items():
        d = np.hypot(X - c[0], Z - c[1]); wk = 1 - smooth(34, 62, d); m = wk > w; zy = np.where(m, ZONE_Y[k], zy); w = np.where(m, wk, w)
    h = h * (1 - w) + zy * w
    fx, fz = ZONES['fr']; dx = X - fx; dz = Z - fz
    cx = 8.0 * np.sin(Z * 0.06); g = np.exp(-((dx - cx) / 9.0) ** 2) * (1 - smooth(55, 78, np.abs(dz))) * (np.abs(dx) < 60)
    h = h - g * 9.0 + np.maximum(0, noise2(X * 2.5, Z * 2.5, 0.09, 5)) * 5.0 * (1 - smooth(10, 40, np.abs(dx))) * (np.abs(dz) < 80)
    cxx, czz = ZONES['co']; bx = X - cxx; bz = Z - czz; rb = np.maximum(np.abs(bx), np.abs(bz))
    bank = 7.0 * smooth(11, 14, rb) * (1 - smooth(16, 34, rb)); bank = np.where(bz > 8, bank * smooth(5, 8, np.abs(bx)), bank)
    h = h + bank
    ex = np.maximum(np.maximum(X0 - X, X - X1), np.maximum(Z0 - Z, Z - Z1)); h = h + smooth(-30, 0, ex) * 70.0
    return h
XX, ZZ = np.meshgrid(xs, zs, indexing='ij'); HH = height(XX, ZZ).astype(np.float32)
nx, nz = len(xs), len(zs)
with open(f'{OUT}/scripts/terrain_data.gd', 'w') as fh:
    fh.write('# AUTO-GENERATED heightfield (3 m grid) -- single source of truth for terrain mesh, props and AI\nclass_name TerrainData\n')
    fh.write(f'const NX = {nx}\nconst NZ = {nz}\nconst X0 = {X0}\nconst Z0 = {Z0}\nconst STEP = {STEP}\n')
    fh.write('const H = [' + ','.join('%.2f' % v for v in HH.T.flatten()) + ']\n')   # row-major z then x
# painted terrain mesh
V = np.stack([XX, HH, ZZ], -1).reshape(-1, 3).astype(np.float64)
idx = np.arange(nx * nz).reshape(nx, nz); F = []
a = idx[:-1, :-1].flatten(); b = idx[1:, :-1].flatten(); c = idx[:-1, 1:].flatten(); d = idx[1:, 1:].flatten()
F = np.concatenate([np.stack([a, c, b], 1), np.stack([b, c, d], 1)])
gx, gz = np.gradient(HH, STEP, axis=(0, 1)); Nn = np.stack([-gx, np.ones_like(HH), -gz], -1); Nn /= np.linalg.norm(Nn, axis=-1, keepdims=True); N = Nn.reshape(-1, 3)
lam = np.clip(N @ KEY * 0.5 + 0.5, 0, 1) ** 1.3
slope = 1 - N[:, 1]
n1 = noise2(XX, ZZ, 0.2, 31, 3).flatten(); n2 = noise2(XX, ZZ, 0.8, 32, 2).flatten()
rip = 0.5 + 0.5 * np.sin(V[:, 0] * 0.9 + V[:, 2] * 0.35 + n1 * 14)
sandL = hexc('#f6dfa6'); sandD = hexc('#d8a56a'); rockC = hexc('#b57858'); redC = hexc('#a45e48'); plaza = hexc('#efd4a0'); teal = hexc('#3dffe8')
col = sandD[None, :] * (1 - lam[:, None]) + sandL[None, :] * lam[:, None]
col = col * (1 + (rip[:, None] - 0.5) * 0.2) * (1 + n1[:, None] * 0.34) * (1 - np.clip(n2[:, None] * 1.2, 0, 0.35) * np.array([0.1, 0.22, 0.34]))
rk = np.clip((slope - 0.18) * 4.5, 0, 1)
col = col * (1 - rk[:, None]) + (rockC[None, :] * (0.8 + 0.4 * lam[:, None]) * (1 + n2[:, None] * 0.3)) * rk[:, None]
glow = np.zeros(len(V), np.float32)
for k, cc in ZONES.items():
    dd = np.hypot(V[:, 0] - cc[0], V[:, 2] - cc[1]); w = 1 - smooth(14, 40, dd)
    col = col * (1 - w[:, None] * 0.55) + plaza[None, :] * (0.9 + 0.2 * lam[:, None]) * w[:, None] * 0.55
fdist = np.hypot(V[:, 0] - ZONES['fr'][0], V[:, 2] - ZONES['fr'][1]); wf = 1 - smooth(30, 75, fdist)
col = col * (1 - wf[:, None] * 0.7) + redC[None, :] * (0.7 + 0.5 * lam[:, None]) * wf[:, None] * 0.7
cv = np.abs(noise2(XX, ZZ, 0.35, 77, 3).flatten()) < 0.012
cv &= (wf > 0.2); col = np.where(cv[:, None], teal[None, :], col); glow = np.where(cv, 1.0, glow).astype(np.float32)
edge = V[:, 1] > 25; col = np.where(edge[:, None], rockC[None, :] * 0.9, col)
tm = VMesh(V, F, N, np.clip(col, 0, 1.15).astype(np.float32), glow); tm.save(f'{MD}/terrain.glb')
data['terrain'] = 'terrain.glb'
print('terrain', len(F), round(time.time() - t0), flush=True)

with open(f'{OUT}/scripts/rig_data.gd', 'w') as fh:
    fh.write('# AUTO-GENERATED by pipeline/build_all.py (SDF-sculpted models, rig pivots, aim pose)\nclass_name RigData\nconst DATA = ' + json.dumps(data) + '\n')
print('ALL DONE', round(time.time() - t0), 's')
