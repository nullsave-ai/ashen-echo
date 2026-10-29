import numpy as np, math, os, sys
from sdf import *
from hero_sculpt import inter, subt, RX, RZ
RXn = rotm((1, 0, 0), math.pi / 2)

ADOBE = '#e0b07a'; ADOBE2 = '#c58a58'; PLAS = '#f3e2bb'; SAND = '#f0d79c'; WOOD = '#6e4528'; WOOD2 = '#8a5a30'; RED = '#a8321f'; TEAL = '#1f948e'
STONE = '#d3a877'; DARKM = '#2c3f44'; RUST = '#a4552a'; GLOW = '#3dffe8'; BRASS = '#c99b3c'; ROCK = '#b0775a'; ROCK2 = '#d49a70'; CANV = '#b09868'
SE = dict(ao_scale=1.0, edge_k=0.9, cav_k=1.0, brush_f=3.5, drift_f=0.8, drift=1.1, dirt=(0.0, 1.2, 0.45))
SEF = dict(ao_scale=1.4, edge_k=0.8, cav_k=0.9, brush_f=2.5, drift_f=0.5, drift=1.0)

def chisel(f=3.0, amp=0.05, seed=0.0):
    def fn(P):
        n = fbm(P, f, 3, seed); return amp * (0.45 * n + 0.55 * np.round(n * 3) / 3 - 0.5) + amp * 0.35 * (fbm(P, f * 4, 2, seed + 4) - 0.5)
    return fn

def bricks(rowh=0.2, colw=0.46, mortar='#6f4a34', tint=0.14):
    def post(V, N, col, glow):
        side = np.abs(N[:, 1]) < 0.55
        u = np.where(np.abs(N[:, 0]) > np.abs(N[:, 2]), V[:, 2], V[:, 0])
        row = np.floor(V[:, 1] / rowh); fy = V[:, 1] / rowh - row
        uu = u / colw + (row % 2) * 0.5; col_i = np.floor(uu); fu = uu - col_i
        m = ((fy < 0.1) | (fu < 0.05)) & side
        h = (np.sin(row * 12.9898 + col_i * 78.233) * 43758.5453) % 1.0
        col = col * (1 + (h[:, None] - 0.5) * tint * side[:, None])
        col = np.where(m[:, None], col * 0.62 + hexc(mortar)[None, :] * 0.2, col)
        return col, glow, {}
    return post

def strata(c2, f=5.0, amp=1.0, wob=2.0):
    def post(V, N, col, glow):
        b = 0.5 + 0.5 * np.sin(V[:, 1] * f + wob * fbm(V, 1.2, 2, 3.3))
        col = col * (1 - b[:, None] * 0.0) * (1 - 0.0) + (hexc(c2)[None, :] - col) * (b[:, None] * 0.55 * amp)
        return col, glow, {}
    return post

def chain_post(*ps):
    def post(V, N, col, glow):
        ex = {}
        for p in ps:
            col, glow, e = p(V, N, col, glow); ex.update(e)
        return col, glow, ex
    return post

def stains(amount=0.22):
    def post(V, N, col, glow):
        n = fbm(V, 1.4, 4, 5.1); col = col * (1 - amount * np.clip((n - 0.45) * 3, 0, 1)[:, None] * np.array([0.35, 0.5, 0.65]))
        return col, glow, {}
    return post

def arch_door(s, cx, cz, w, h, depth, axis='z'):
    """cut a rounded arch doorway through a wall (axis z walls)"""
    s.cut(rbox((cx, h / 2 - 0.02, cz), (w / 2, h / 2 - w / 4, depth), 0.04), '#3a2418', k=0.04)
    s.cut(cylinder((cx, h - w / 2, cz), w / 2, depth, RXn), '#3a2418', k=0.04)

def adobe_body(s, w, d, h, rad=0.2, col=ADOBE, wall=0.35, y0=0.0, cx=0.0, cz=0.0):
    body = rbox((cx, y0 + h / 2, cz), (w / 2, h / 2, d / 2), rad)
    body = displace(body, chisel(2.2, 0.09))
    s.add(body, col)
    s.cut(rbox((cx, y0 + h / 2 + 0.15, cz), (w / 2 - wall, h / 2 - 0.1, d / 2 - wall), 0.06), '#5b3d2a', k=0.05)

def roof_rim(s, w, d, y, col=SAND, thick=0.2, rim=0.3, cx=0.0, cz=0.0):
    s.add(rbox((cx, y, cz), (w / 2 + 0.15, thick / 2, d / 2 + 0.15), 0.08), col, k=0.05)
    s.add(displace(rbox((cx, y + rim / 2, cz), (w / 2 + 0.1, rim / 2 + thick / 2, d / 2 + 0.1), 0.1), chisel(2.0, 0.06, 2.0)), col, k=0.05)
    s.cut(rbox((cx, y + rim / 2 + 0.12, cz), (w / 2 - 0.25, rim / 2 + 0.05, d / 2 - 0.25), 0.05), '#a98b5c', k=0.03)

def vigas(s, w, y, zs, cx=0.0, cz=0.0, r=0.09):
    for z in zs: s.add(capsule((cx - w / 2 - 0.55, y, z), (cx + w / 2 + 0.55, y, z), r), WOOD, k=0.02)

def awning(s, cx, cz, w, d, y, col=RED, tilt=0.25):
    for x in (cx - w / 2 + 0.1, cx + w / 2 - 0.1): s.add(capsule((x, 0.0, cz + d - 0.1), (x, y, cz + d - 0.1), 0.065), WOOD, k=0.02)
    f = rbox((cx, y + 0.05, cz + d / 2), (w / 2, 0.025, d / 2), 0.02)
    f = warp(f, lambda P: np.stack([P[:, 0], P[:, 1] + (P[:, 2] - cz) * tilt - 0.06 * np.sin((P[:, 0] - cx) * 5.0), P[:, 2]], 1))
    s.add(f, col)

M = {}
def mk(name, fn, lo, hi, vox, tris, style=SE, post=None, scale=1.0):
    s = Sculpt(); fn(s)
    M[name] = s.mesh(lo, hi, vox, tris=tris, style=style, post=post)
    print(name, len(M[name].f), flush=True)

# ---------------------------------------------------------------- SETTLEMENT
def house_a(s):
    adobe_body(s, 6.5, 6.0, 3.4)
    arch_door(s, 0.0, 3.0, 1.5, 2.4, 0.6); arch_door(s, -2.3, 3.0, 0.9, 1.5, 0.6) if False else None
    s.cut(rbox((-2.3, 1.9, 3.0), (0.45, 0.5, 0.5), 0.05), '#3a2418', k=0.03); s.cut(rbox((2.4, 1.9, 3.0), (0.4, 0.45, 0.5), 0.05), '#3a2418', k=0.03)
    s.cut(rbox((3.25, 1.9, 0.5), (0.5, 0.45, 0.5), 0.05), '#3a2418', k=0.03)
    roof_rim(s, 6.5, 6.0, 3.5); vigas(s, 6.5, 3.35, [-2.5 + i * 0.85 for i in range(7)])
    s.add(rbox((0, 0.05, 0), (3.1, 0.06, 2.8), 0.02), SAND)
    s.add(capsule((-2.6, 3.9, -2.5), (-2.6, 5.2, -2.5), 0.05), WOOD)
    awning(s, 0.0, 3.0, 2.8, 1.8, 2.7)
    for (x, z, r) in ((2.6, 3.7, 0.3), (3.3, 4.3, 0.22)):
        s.add(ellipsoid((x, r * 1.1, z), (r, r * 1.15, r)), RUST); s.cut(sphere((x, r * 2.3, z), r * 0.6), '#3a2418')
    s.add(rbox((-2.2, 0.15, 3.6), (0.5, 0.15, 0.3), 0.05), WOOD2)
def house_b(s):
    adobe_body(s, 7.5, 5.5, 3.2, col=PLAS)
    s.add(displace(rbox((0, 3.2 + 1.4, -0.5), (2.5, 1.4, 2.0), 0.2), chisel(2.2, 0.08, 3.0)), ADOBE, k=0.04)
    s.cut(rbox((0, 4.7, -0.3), (2.15, 1.2, 1.65), 0.06), '#5b3d2a', k=0.04)
    arch_door(s, -1.5, 2.75, 1.3, 2.3, 0.6); s.cut(rbox((1.8, 2.0, 2.75), (0.5, 0.55, 0.5), 0.05), '#3a2418', k=0.03)
    arch_door(s, 0.0, 1.5, 1.2, 2.0, 0.6) if False else None
    s.cut(cylinder((0, 3.7, 1.5), 0.6, 0.6, RXn), '#3a2418', k=0.04); s.cut(rbox((0, 3.2, 1.5), (0.6, 0.5, 0.6), 0.04), '#3a2418')
    s.cut(rbox((3.75, 1.9, 0), (0.5, 0.5, 0.5), 0.04), '#3a2418', k=0.03)
    s.add(rbox((0, 3.35, 3.25), (2.75, 0.07, 0.9), 0.03), WOOD, k=0.02)
    for x in np.linspace(-2.6, 2.6, 7): s.add(capsule((x, 3.45, 4.0), (x, 4.0, 4.0), 0.03), WOOD)
    s.add(capsule((-2.7, 3.9, 4.0), (2.7, 3.9, 4.0), 0.04), WOOD)
    s.add(rbox((0, 6.2, -0.5), (2.65, 0.15, 2.15), 0.08), SAND, k=0.04)
    for x in (-3.2, 3.2): s.add(capsule((x, 0, 3.0), (x, 3.3, 3.0), 0.08), WOOD, k=0.02)
    awning(s, 0.0, 2.8, 3.4, 1.9, 2.55, TEAL)
def dome_house(s):
    adobe_body(s, 5.5, 5.5, 3.0, col=PLAS)
    s.add(displace(rbox((0, 3.15, 0), (3.1, 0.15, 3.1), 0.08), chisel(2, 0.05)), SAND, k=0.04)
    s.add(ellipsoid((0, 3.2, 0), (2.75, 2.7, 2.75)), PLAS, k=0.08)
    s.cut(rbox((0, 1.4, 0), (2.4, 1.3, 2.4), 0.06), '#5b3d2a', k=0.04)
    s.cut(rbox((0, -0.5, 0), (4.5, 0.5, 4.5)), '#000000')
    arch_door(s, 0.0, 2.75, 1.4, 2.2, 0.6)
    s.cut(rbox((2.75, 1.9, 0), (0.5, 0.45, 0.45), 0.05), '#3a2418', k=0.03)
    s.cut(cylinder((0, 6.1, 0), 0.35, 0.6, None), '#3a2418', k=0.05) if False else None
    for a in range(4): s.add(rbox((math.cos(a * 1.571) * 2.9, 3.55, math.sin(a * 1.571) * 2.9), (0.3, 0.4, 0.3), 0.1), TEAL)
    s.add(capsule((0, 5.8, 0), (0, 7.1, 0), 0.07), BRASS); s.add(ellipsoid((0, 6.3, 0), (0.2, 0.26, 0.2)), BRASS, k=0.03)
def tower(s):
    r0, r1, h = 2.2, 1.55, 9.0
    s.add(displace(rcone((0, 0, 0), (0, h, 0), r0, r1), chisel(1.5, 0.12, 4.0)), ADOBE)
    s.cut(cylinder((0, h - 0.3, 0), r1 - 0.45, 0.9, None, 0.1), '#5b3d2a', k=0.05)
    s.add(displace(cylinder((0, h + 0.2, 0), 2.0, 0.28, None, 0.06), chisel(2.0, 0.06)), SAND, k=0.05)
    for k in range(8):
        a = k * math.pi / 4; s.add(rbox((math.cos(a) * 1.82, h + 0.95, math.sin(a) * 1.82), (0.38, 0.5, 0.28), 0.08, rotm((0, 1, 0), -a)), SAND, k=0.04)
    arch_door(s, 0.0, 2.3, 1.2, 2.3, 1.0)
    for y in (3.8, 6.2): s.cut(rbox((0, y, 1.9), (0.2, 0.6, 0.6), 0.05), '#3a2418', k=0.03)
    s.add(rbox((0, 8.0, 1.5), (0.4, 1.0, 0.03), 0.01), RED); s.add(sphere((0, h + 1.4, 0), 0.3), GLOW, g=1.0); s.add(capsule((0, h + 0.4, 0), (0, h + 1.2, 0), 0.06), BRASS)
    for a in range(10): s.add(rbox((math.cos(a * 0.63) * 2.2, 0.15, math.sin(a * 0.63) * 2.2), (0.38, 0.15, 0.3), 0.06, rotm((0, 1, 0), a)), STONE)
def well(s):
    s.add(displace(cylinder((0, 0.55, 0), 1.1, 0.55, None, 0.12), chisel(2, 0.06)), STONE); s.cut(cylinder((0, 1.0, 0), 0.8, 0.5, None), '#1a1210', k=0.03)
    for x in (-1.0, 1.0): s.add(capsule((x, 0, 0), (x, 3.0, 0), 0.08), WOOD, k=0.02)
    s.add(capsule((-1.2, 3.0, 0), (1.2, 3.0, 0), 0.07), WOOD); s.add(displace(rbox((0, 3.25, 0), (1.5, 0.05, 0.9), 0.03), lambda P: 0.04 * np.sin(P[:, 0] * 4)), RED)
    s.add(cylinder((0, 2.9, 0), 0.14, 0.4, RZ), WOOD2); s.add(capsule((0, 2.9, 0), (0, 1.3, 0), 0.012), LEAD := '#3a2316'); s.add(cylinder((0, 1.15, 0), 0.2, 0.17, None, 0.03), WOOD2)
def stall(s):
    for x in (-1.4, 1.4):
        for z, hh in ((-0.9, 2.6), (0.9, 2.2)): s.add(capsule((x, 0, z), (x, hh, z), 0.06), WOOD, k=0.02)
    can = rbox((0, 2.4, 0), (1.7, 0.03, 1.05), 0.02)
    can = warp(can, lambda P: np.stack([P[:, 0], P[:, 1] + P[:, 2] * 0.22 - 0.1 * np.sin(P[:, 0] * 4.5) * (1 - np.abs(P[:, 2]) / 1.1), P[:, 2]], 1))
    s.add(can, RED)
    s.add(rbox((0, 0.85, -0.2), (1.3, 0.04, 0.5), 0.02), WOOD2); s.add(rbox((0, 0.42, -0.2), (1.2, 0.42, 0.42), 0.04), WOOD)
    for k in range(5): s.add(ellipsoid((-1.0 + k * 0.5, 1.0, -0.2), (0.14, 0.11, 0.14)), RUST if k % 2 else BRASS, k=0.01)
def swall(s):
    s.add(displace(rbox((0, 1.1, 0), (2.5, 1.1, 0.3), 0.12), chisel(2.2, 0.16, 6.0)), ADOBE)
    s.add(displace(rbox((-1.3, 2.4, 0), (0.75, 0.4, 0.3), 0.1), chisel(3, 0.14, 8.0)), ADOBE2, k=0.05)
    s.cut(sphere((1.8, 2.1, 0), 0.7), '#1a1210', k=0.1)
    s.add(rbox((0.9, 2.3, 0.1), (0.45, 0.18, 0.33), 0.06), SAND)

# ---------------------------------------------------------------- STATION
def st_hall(s):
    W, D, H = 12, 8, 3.6
    s.add(displace(rbox((0, H / 2, 0), (W / 2, H / 2, D / 2), 0.16), chisel(2.5, 0.05)), PLAS)
    s.cut(rbox((0, H / 2 + 0.1, 0), (W / 2 - 0.3, H / 2 - 0.1, D / 2 - 0.3), 0.05), '#6b5a4a', k=0.04)
    s.add(rbox((0, 0.06, 0), (W / 2 - 0.2, 0.05, D / 2 - 0.2), 0.02), '#4a8c88')
    s.cut(rbox((0, 1.25, D / 2), (0.9, 1.25, 0.6), 0.06), '#2a1e16', k=0.04)
    for x in (-4, 4): s.cut(rbox((x, 1.75, D / 2), (0.7, 0.65, 0.6), 0.05), '#2a1e16', k=0.03)
    s.cut(rbox((-2.3, 1.85, D / 2), (0.5, 0.45, 0.6), 0.05), '#2a1e16', k=0.03); s.cut(rbox((3, 1.8, -D / 2), (0.6, 0.6, 0.6), 0.05), '#2a1e16', k=0.03)
    s.cut(rbox((W / 2, 1.8, 0), (0.6, 0.6, 0.7), 0.05), '#2a1e16', k=0.03); s.cut(rbox((-W / 2, 1.8, 0), (0.6, 0.6, 0.7), 0.05), '#2a1e16', k=0.03)
    for x in (-4, 4): s.add(rbox((x, 1.1, D / 2 + 0.06), (0.78, 0.04, 0.12), 0.02), DARKM)
    s.add(rbox((0, H + 0.2, 0), (W / 2 + 0.3, 0.2, D / 2 + 0.3), 0.08), SAND, k=0.04)
    s.add(displace(rbox((0, H + 0.6, 0), (W / 2 + 0.2, 0.3, D / 2 + 0.2), 0.1), chisel(2, 0.05, 1)), SAND, k=0.03)
    s.cut(rbox((0, H + 0.75, 0), (W / 2 - 0.2, 0.3, D / 2 - 0.2), 0.05), '#9b7c54')
    # corrugated awning
    aw = rbox((0, 3.0, D / 2 + 1.3), (3.6, 0.04, 1.4), 0.015)
    aw = warp(aw, lambda P: np.stack([P[:, 0], P[:, 1] + (P[:, 2] - D / 2) * 0.12 + 0.03 * np.sin(P[:, 0] * 16), P[:, 2]], 1))
    s.add(aw, RUST)
    for x in (-3.3, 3.3): s.add(capsule((x, 0, D / 2 + 2.5), (x, 3.0, D / 2 + 2.5), 0.07), WOOD, k=0.02)
    s.add(rbox((0, 2.55, D / 2 + 0.12), (1.1, 0.07, 0.14), 0.03), DARKM); s.add(rbox((0, 2.75, D / 2 + 0.15), (0.7, 0.03, 0.03), 0.01), GLOW, g=1.0)
    for x in (-4, -2.4): s.add(rbox((x, H + 1.2, -1.5), (0.6, 0.35, 0.5), 0.08), DARKM)
    for k in range(4): s.add(rbox((1.5 + k * 1.1, H + 1.15, -1.2), (0.48, 0.025, 0.8), 0.01, rotm((1, 0, 0), -0.4)), '#2b6f78')
    s.add(capsule((-5.2, H + 0.5, 2.6), (-5.2, H + 4.3, 2.6), 0.05), BRASS); s.add(capsule((-5.6, H + 3.6, 2.6), (-4.8, H + 3.6, 2.6), 0.03), BRASS)
    s.add(cylinder((5.0, H + 1.4, 2.0), 0.85, 0.9, None, 0.1), RUST); s.add(ellipsoid((5.0, H + 2.4, 2.0), (0.85, 0.35, 0.85)), RUST, k=0.05)
    # interior: benches, terminal, shelves, cot
    for k in range(3):
        s.add(rbox((-3.2, 0.5, -2.6 + k * 1.7), (1.2, 0.05, 0.42), 0.03), WOOD2); s.add(rbox((-3.2, 0.25, -2.6 + k * 1.7), (1.15, 0.25, 0.35), 0.03), DARKM)
    s.add(sphere((-2.6, 0.72, -2.6), 0.1), GLOW, g=1.0); s.add(cylinder((-2.2, 0.66, -0.9), 0.08, 0.13, None, 0.02), '#3a8c88')
    s.add(rbox((4.6, 0.85, -3.2), (0.5, 0.85, 0.3), 0.05), DARKM); s.add(rbox((4.6, 1.38, -2.88), (0.4, 0.25, 0.012), 0.005), GLOW, g=1.0)
    for k in range(3): s.add(rbox((5.7, 0.6 + k * 0.7, 0.5), (0.2, 0.03, 1.6), 0.01), WOOD2)
    for z in (-1, 2): s.add(capsule((5.85, 0, z + 0.5), (5.85, 2.0, z + 0.5), 0.025), WOOD)
    s.add(rbox((-5.0, 0.35, 2.5), (0.95, 0.12, 0.4), 0.06), CANV); s.add(rbox((-5.0, 0.5, 2.5), (0.9, 0.05, 0.35), 0.04), RED)
    s.add(rbox((2.0, 0.7, 2.3), (0.7, 0.03, 0.4), 0.02), WOOD2); s.add(rbox((2.0, 0.35, 2.3), (0.65, 0.35, 0.02), 0.01), WOOD)
    s.add(rbox((-2, 1.0, -3.8), (1.0, 0.7, 0.025), 0.01), TEAL)
    s.add(rbox((1.5, 0.45, 1.5), (0.25, 0.025, 0.25), 0.01, rotm((0, 0, 1), 1.2)), WOOD2)
def st_dome(s):
    s.add(displace(cylinder((0, 1.5, 0), 4.0, 1.5, None, 0.15), chisel(2.0, 0.05)), PLAS)
    s.add(ellipsoid((0, 3.0, 0), (3.95, 3.8, 3.95)), PLAS, k=0.05)
    s.cut(rbox((0, -1, 0), (6, 1, 6)), '#000000'); s.cut(ellipsoid((0, 2.9, 0), (3.5, 3.4, 3.5)), '#6b5a4a', k=0.05)
    s.cut(rbox((0, 4.6, -3.0), (0.5, 3.0, 2.0), 0.1, rotm((1, 0, 0), 0.55)), '#2a3a40', k=0.04)
    s.add(rbox((0, 4.6, -3.0), (0.38, 3.0, 0.12), 0.04, rotm((1, 0, 0), 0.55)), GLOW, g=0.5, k=0.0) if False else None
    for k in range(8):
        a = k * math.pi / 4; s.add(capsule((math.cos(a) * 3.95, 3.0, math.sin(a) * 3.95), (math.cos(a) * 0.5, 6.7, math.sin(a) * 0.5), 0.09), RUST, k=0.03)
    s.cut(rbox((0, 1.15, 4.0), (0.8, 1.15, 0.6), 0.08), '#2a1e16', k=0.04)
    s.add(rbox((0, 0.07, 0), (3.6, 0.06, 3.6), 0.02), '#4a8c88')
    s.add(rcone((0, 0.1, 0), (0, 2.2, 0), 0.45, 0.3), DARKM); s.add(rcone((0, 2.2, 0), (0.3, 3.4, -1.7), 0.28, 0.2), BRASS, k=0.04); s.add(cylinder((0.35, 3.5, -1.95), 0.3, 0.06, RXn), GLOW, g=0.9)
    for i in range(10): s.add(rbox((math.cos(i * 0.628) * 4.3, 0.15, math.sin(i * 0.628) * 4.3), (0.4, 0.15, 0.3), 0.06, rotm((0, 1, 0), -i * 0.628)), STONE)
def dish(s):
    s.add(rcone((0, 0, 0), (0, 2.4, 0), 0.3, 0.16), DARKM)
    R = rotm((1, 0, 0), -1.0)
    s.add(inter(shell(ellipsoid((0, 3.4, 0), (2.4, 2.4, 2.4), R), 0.07), lambda P: (-(P - np.array([0, 3.4, 0])) @ R.T)[:, 1] * 1.0 - 0.9), '#e3d5b5')
    s.add(capsule((0, 3.2, 0), (0, 4.4, -1.8), 0.04), BRASS); s.add(sphere((0, 4.45, -1.85), 0.12), GLOW, g=1.0)
    for a in range(3): s.add(capsule((math.cos(a * 2.09) * 1.1, 0, math.sin(a * 2.09) * 1.1), (0, 2.2, 0), 0.07), DARKM)
def tank(s):
    s.add(cylinder((0, 3.2, 0), 1.35, 1.3, None, 0.18), RUST); s.add(ellipsoid((0, 4.5, 0), (1.35, 0.5, 1.35)), RUST, k=0.1)
    s.add(displace(torus((0, 3.2, 0), 1.37, 0.04), lambda P: 0), DARKM); s.add(torus((0, 2.6, 0), 1.37, 0.04), DARKM); s.add(torus((0, 3.8, 0), 1.37, 0.04), DARKM)
    for a in range(4):
        x, z = math.cos(a * 1.57 + 0.78) * 1.0, math.sin(a * 1.57 + 0.78) * 1.0; s.add(capsule((x * 1.15, 0, z * 1.15), (x * 0.9, 2.0, z * 0.9), 0.1), WOOD, k=0.03)
    s.add(capsule((0, 0, 0), (0, 2.0, 0), 0.06), BRASS); s.add(capsule((1.0, 4.9, 0), (1.0, 1.0, 1.7), 0.04), DARKM)
def generator(s):
    s.add(displace(rbox((0, 0.65, 0), (1.0, 0.55, 0.55), 0.12), chisel(5, 0.03)), DARKM); s.add(cylinder((-0.5, 1.45, 0), 0.25, 0.25, None, 0.05), RUST)
    s.add(capsule((0.6, 1.2, 0), (0.6, 2.0, 0), 0.08), BRASS); s.add(rbox((0.3, 0.75, -0.55), (0.3, 0.12, 0.02), 0.01), GLOW, g=1.0)
    s.add(rbox((0, 0.05, 0), (1.25, 0.06, 0.78), 0.02), RUST); s.add(capsule((1.0, 0.5, 0.0), (1.8, 0.1, 0.3), 0.04), '#2a1e16')
    for k in range(4): s.add(rbox((-0.6 + k * 0.3, 0.6, 0.57), (0.1, 0.35, 0.02), 0.01), '#1a2a2e')

# ---------------------------------------------------------------- COMPLEX
def corridor(s):
    L = 8.0
    s.add(displace(rbox((0, 1.75, 0), (2.4, 1.9, L / 2), 0.2), chisel(2.0, 0.04)), STONE)
    s.cut(rbox((0, 1.75, 0), (1.95, 1.55, L / 2 + 1), 0.15), '#2c4a50', k=0.1)
    for k in range(5):
        z = -L / 2 + 0.8 + k * 1.6
        for sx in (-1, 1): s.add(rbox((sx * 1.9, 1.75, z), (0.22, 1.55, 0.26), 0.06), DARKM, k=0.03); s.add(rbox((sx * 1.72, 1.1, z), (0.03, 0.8, 0.05), 0.01), GLOW, g=1.0)
        s.add(rbox((0, 3.2, z), (1.9, 0.14, 0.2), 0.04), DARKM, k=0.03)
    s.add(rbox((0, 3.2, 0), (0.15, 0.03, L / 2 - 0.2), 0.01), GLOW, g=1.0)
    for sx in (-1, 1): s.add(capsule((sx * 1.7, 3.0, -L / 2), (sx * 1.7, 3.0, L / 2), 0.09), '#46646a')
    s.add(rbox((0, 0.1, 0), (1.95, 0.1, L / 2), 0.03), '#3f7f7b')
def co_hall(s):
    S = 18.0; Hh = 7.0
    s.add(displace(rbox((0, Hh / 2, 0), (S / 2, Hh / 2, S / 2), 0.25), chisel(1.8, 0.07)), STONE)
    s.cut(rbox((0, Hh / 2 + 0.1, 0), (S / 2 - 0.6, Hh / 2 - 0.3, S / 2 - 0.6), 0.2), '#2c4a50', k=0.1)
    for (cx, cz, ax) in ((0, S / 2, 'z'), (S / 2, 0, 'x'), (-S / 2, 0, 'x')):
        if ax == 'z': s.cut(rbox((cx, 1.9, cz), (1.5, 1.9, 0.8), 0.06), '#1a2a2e', k=0.05); s.cut(cylinder((cx, 3.0, cz), 1.5, 0.8, RXn), '#1a2a2e', k=0.05)
        else: s.cut(rbox((cx, 1.9, cz), (0.8, 1.9, 1.5), 0.06), '#1a2a2e', k=0.05); s.cut(cylinder((cx, 3.0, cz), 1.5, 0.8, rotm((0, 0, 1), math.pi / 2)), '#1a2a2e', k=0.05)
    s.add(rbox((0, Hh + 0.25, 0), (S / 2 + 0.6, 0.25, S / 2 + 0.6), 0.1), '#3f7f7b', k=0.05) if False else None
    for sx in (-5, 5):
        for sz in (-5, 5):
            s.add(displace(rcone((sx, 0.2, sz), (sx, Hh, sz), 0.7, 0.55), lambda P: 0.03 * np.sin(P[:, 1] * 9)), STONE, k=0.1)
            s.add(torus((sx, 2.6, sz), 0.6, 0.06), GLOW, g=1.0); s.add(rbox((sx, 0.3, sz), (0.85, 0.3, 0.85), 0.1), DARKM, k=0.05)
    s.add(cylinder((0, 0.4, 0), 2.2, 0.4, None, 0.1), DARKM); s.add(cylinder((0, 0.8, 0), 1.5, 0.4, None, 0.08), '#3f7f7b', k=0.05)
    s.add(displace(rcone((0, 1.0, 0), (0, 3.9, 0), 0.75, 0.05), lambda P: 0.12 * (np.abs(((np.arctan2(P[:, 0], P[:, 2]) * 3 / math.pi) % 1) - 0.5) - 0.25)), GLOW, g=1.0, k=0.03)
    for k in range(6): a = k * 1.047; s.add(capsule((math.cos(a) * 1.4, 0.8, math.sin(a) * 1.4), (math.cos(a) * 1.4, 2.5, math.sin(a) * 1.4), 0.05), '#46646a')
    s.add(torus((0, 0.25, 0), 4.5, 0.03), GLOW, g=1.0)
    for x in (-7.5, 7.5): s.add(rbox((x, 0.5, 6), (0.9, 0.5, 0.5), 0.08), DARKM)
def co_door(s):
    for sx in (-1, 1): s.add(displace(rbox((sx * 2.0, 2.4, 0), (0.5, 2.4, 0.5), 0.1), chisel(2.0, 0.06)), STONE); s.add(rbox((sx * 1.52, 2.4, -0.48), (0.03, 1.5, 0.03), 0.01), GLOW, g=1.0)
    s.add(displace(rbox((0, 4.8, 0), (2.5, 0.45, 0.5), 0.1), chisel(2.0, 0.06, 2)), STONE, k=0.05); s.add(rbox((0, 4.8, -0.5), (0.6, 0.08, 0.03), 0.01), GLOW, g=1.0)
    s.add(torus((0, 5.5, -0.3), 0.4, 0.05, RXn), GLOW, g=1.0)
def terminal(s):
    s.add(rbox((0, 0.6, 0), (0.45, 0.6, 0.3), 0.06), DARKM); s.add(rbox((0, 1.1, -0.18), (0.35, 0.26, 0.02), 0.01, rotm((1, 0, 0), 0.3)), GLOW, g=1.0); s.add(rbox((0, 1.25, 0.1), (0.4, 0.04, 0.2), 0.02), BRASS)

# ---------------------------------------------------------------- FRACTURE
def spire(h, r, seed, lean):
    def f(s):
        s.add(displace(rcone((0, 0, 0), (lean[0] * h, h, lean[1] * h), r, r * 0.15), lambda P: chisel(1.1, r * 0.35, seed)(P) + 0.25 * np.sin(P[:, 1] * 2.1 + fbm(P, 0.6, 2, seed) * 5) * 0.4), ROCK)
        s.add(displace(rcone((r * 0.4, 0, -r * 0.2), (r * 0.5 + lean[0] * h * 0.5, h * 0.55, -r * 0.2), r * 0.45, r * 0.05), chisel(2, r * 0.1, seed + 2)), ROCK2, k=0.3)
        s.add(rcone((r * 0.3, 1.0, -r * 0.7), (r * 0.35 + lean[0] * h * 0.3, h * 0.5, -r * 0.7), 0.06, 0.02), GLOW, g=1.0)
    return f
def arch_rock(s):
    pts = [(math.cos(a) * 7, math.sin(a) * 6.5) for a in np.linspace(0, math.pi, 14)]
    for i in range(13): s.add(displace(rcone((pts[i][0], pts[i][1], 0), (pts[i + 1][0], pts[i + 1][1], 0), 1.9 - abs(i - 6) * 0.08, 1.9 - abs(i - 5) * 0.08), chisel(0.9, 0.5, 4.0)), ROCK, k=0.4)
    s.add(ellipsoid((7, 0.5, 0), (2.4, 1.6, 2.2)), ROCK2, k=0.5); s.add(ellipsoid((-7, 0.5, 0), (2.4, 1.6, 2.2)), ROCK2, k=0.5)
def crystal(s):
    for k in range(7):
        a = k * 0.9; hh = 1.3 + (k % 3) * 0.8; s.add(rcone((math.cos(a) * 0.5, 0, math.sin(a) * 0.5), (math.cos(a) * 0.75 + k * 0.05, hh, math.sin(a) * 0.75), 0.24, 0.02), GLOW, g=1.0, k=0.0)
    s.add(displace(ellipsoid((0, 0.1, 0), (1.1, 0.5, 1.1)), chisel(2.5, 0.12, 3)), ROCK, k=0.1)
def crack(s):
    for k in range(7):
        s.add(rbox((math.sin(k * 1.7) * 0.8, 0.05, k * 2.0), (0.1 + 0.03 * (k % 3), 0.05, 1.1), 0.03, rotm((0, 1, 0), math.sin(k * 2.1) * 0.5)), GLOW, g=1.0)
    for k in range(4): s.add(displace(rbox((0.6 * (-1) ** k, 0.05, k * 4 + 1), (0.35, 0.05, 0.7), 0.04, rotm((0, 1, 0), k * 0.7)), chisel(3, 0.06)), ROCK)
def rock_a(s): s.add(displace(ellipsoid((0, 0.55, 0), (1.3, 0.9, 1.2)), chisel(1.6, 0.35, 7.0)), ROCK)
def rock_b(s):
    s.add(displace(ellipsoid((0, 0.4, 0), (0.85, 0.6, 0.8)), chisel(2.2, 0.22, 11.0)), ROCK2); s.add(displace(ellipsoid((1.0, 0.2, 0.3), (0.5, 0.35, 0.5)), chisel(3, 0.14, 12.0)), ROCK, k=0.1)
def slab(s):
    s.add(displace(rbox((0, 1.4, 0), (1.8, 1.4, 0.4), 0.15, rotm((0, 0, 1), 0.14)), chisel(1.6, 0.3, 5.0)), ROCK); s.add(rbox((0.4, 0.9, -0.42), (0.04, 0.9, 0.02), 0.01, rotm((0, 0, 1), 0.14)), GLOW, g=1.0)

# ---------------------------------------------------------------- PROPS
def crate(s):
    s.add(displace(rbox((0, 0.5, 0), (0.5, 0.5, 0.5), 0.06), chisel(8, 0.02)), WOOD2)
    for y in (0.08, 0.5, 0.92): s.add(rbox((0, y, 0), (0.52, 0.05, 0.52), 0.015), DARKM)
    for x in (-0.46, 0.46): s.add(rbox((x, 0.5, 0), (0.05, 0.5, 0.52), 0.015), DARKM)
def barrel(s):
    s.add(rcone((0, 0.05, 0), (0, 1.05, 0), 0.38, 0.38), RUST); s.add(ellipsoid((0, 0.55, 0), (0.43, 0.5, 0.43)), RUST, k=0.05)
    for y in (0.25, 0.85): s.add(torus((0, y, 0), 0.4, 0.03), DARKM, k=0.01)
    s.cut(cylinder((0, 1.1, 0), 0.32, 0.08, None), '#1a1210')
def tent(s):
    for sx in (-1, 1):
        s.add(warp(rbox((sx * 1.0, 1.0, 0), (1.2, 0.03, 1.6), 0.015, rotm((0, 0, 1), -sx * 0.88)), lambda P: np.stack([P[:, 0], P[:, 1], P[:, 2] + 0.03 * np.sin(P[:, 0] * 6)], 1)), CANV)
    for z in (-1.6, 1.6): s.add(capsule((0, 0, z), (0, 2.0, z), 0.05), WOOD)
    s.add(capsule((0, 2.0, -1.6), (0, 2.0, 1.6), 0.04), WOOD); s.add(rbox((0, 0.04, 0), (1.2, 0.03, 1.4), 0.01), RED)
def deadtree(s):
    s.add(displace(rcone((0, 0, 0), (0.1, 3.4, 0), 0.34, 0.05), chisel(2.5, 0.12, 3.0)), WOOD2)
    s.add(rcone((0.05, 1.5, 0), (1.4, 3.0, 0.1), 0.1, 0.02), WOOD2, k=0.05); s.add(rcone((-0.1, 2.2, 0), (-1.2, 3.7, -0.2), 0.09, 0.02), WOOD2, k=0.05)
    s.add(rcone((0.4, 2.5, 0), (0.9, 4.2, 0.3), 0.05, 0.01), WOOD2, k=0.03)
def bones(s):
    s.add(displace(ellipsoid((0, 0.2, 0), (0.28, 0.2, 0.4)), chisel(6, 0.04)), '#e6dcb8'); s.cut(sphere((0, 0.25, -0.35), 0.1), '#1a1210')
    for k in range(5): s.add(rcone((-0.3, 0.1, k * 0.12 - 0.2), (0.1, 0.5, k * 0.12 - 0.2), 0.025, 0.012), '#e6dcb8')
def wreck(s):
    s.add(displace(rbox((0, 1.0, 0), (1.2, 0.65, 2.0), 0.18, rotm((0, 0, 1), 0.12)), chisel(1.8, 0.08, 2.0)), RUST); s.add(rbox((0, 1.9, 1.2), (1.1, 0.45, 0.8), 0.14, rotm((0, 0, 1), 0.12)), RUST, k=0.05)
    s.cut(rbox((0, 2.0, 0.4), (0.9, 0.22, 0.1), 0.04), '#2c4a50')
    s.add(cylinder((-1.3, 0.55, 1.4), 0.55, 0.2, RZ, 0.08), DARKM); s.add(cylinder((1.35, 0.5, -1.4), 0.55, 0.2, RZ, 0.08), DARKM)
    s.add(displace(rbox((0, 1.45, -1.0), (1.1, 0.4, 1.0), 0.15, rotm((0, 0, 1), 0.12)), chisel(3, 0.1)), CANV); s.cut(rbox((0, 1.6, -1.0), (0.9, 0.3, 0.85), 0.08), '#6b5a4a')
def lantern(s):
    s.add(rcone((0, 0, 0), (0, 2.4, 0), 0.11, 0.07), DARKM); s.add(rbox((0, 0.12, 0), (0.4, 0.12, 0.4), 0.06), DARKM); s.add(rbox((0, 2.6, 0), (0.28, 0.06, 0.28), 0.03), BRASS)
    s.add(rbox((0, 2.95, 0), (0.2, 0.28, 0.2), 0.04), '#2b9d97'); s.add(sphere((0, 2.95, 0), 0.15), GLOW, g=1.0); s.add(rcone((0, 3.2, 0), (0, 3.65, 0), 0.32, 0.01), BRASS)
    for a in range(4): s.add(capsule((math.cos(a * 1.571) * 0.2, 2.7, math.sin(a * 1.571) * 0.2), (math.cos(a * 1.571) * 0.2, 3.2, math.sin(a * 1.571) * 0.2), 0.015), BRASS)
    s.add(torus((0, 0.2, 0), 1.0, 0.025), GLOW, g=1.0)
def decoy(s):
    s.add(rcone((0, 0.02, 0), (0, 0.2, 0), 0.1, 0.07), DARKM); s.add(sphere((0, 0.26, 0), 0.08), GLOW, g=1.0); s.add(capsule((0, 0.3, 0), (0.04, 0.55, 0), 0.01), BRASS); s.add(torus((0, 0.18, 0), 0.09, 0.015), BRASS)
def shard(s): s.add(rcone((0, -0.18, 0), (0, 0.0, 0), 0.01, 0.1), GLOW, g=1.0); s.add(rcone((0, 0.0, 0), (0, 0.2, 0), 0.1, 0.01), GLOW, g=1.0, k=0.01)
def cache(s):
    s.add(rbox((0, 0.35, 0), (0.45, 0.35, 0.3), 0.06), DARKM); s.add(rbox((0, 0.72, 0), (0.47, 0.04, 0.32), 0.02), BRASS); s.add(rbox((0, 0.4, -0.31), (0.15, 0.05, 0.01), 0.005), GLOW, g=1.0)
def sandbags(s):
    for k in range(6): s.add(displace(ellipsoid(((k % 3) * 0.6 - 0.6, 0.15 + (k // 3) * 0.26, 0), (0.3, 0.14, 0.2)), chisel(8, 0.03, k)), CANV, k=0.03)
def spool(s):
    s.add(cylinder((0, 0.55, 0), 0.5, 0.05, RXn), WOOD2); s.add(cylinder((0, 0.55, 0.3), 0.5, 0.03, RXn), WOOD2); s.add(cylinder((0, 0.55, 0.15), 0.4, 0.14, RXn), '#2a1e16')
def pot(s):
    s.add(ellipsoid((0, 0.33, 0), (0.33, 0.33, 0.33)), RUST); s.add(cylinder((0, 0.62, 0), 0.2, 0.06, None, 0.02), RUST, k=0.03); s.cut(cylinder((0, 0.7, 0), 0.15, 0.06, None), '#1a1210')
def shrub(s):
    for k in range(7):
        a = k * 0.9; s.add(rcone((0, 0, 0), (math.cos(a) * 0.5, 0.5 + (k % 3) * 0.12, math.sin(a) * 0.5), 0.03, 0.006), '#8a7a4a', k=0.02)
    s.add(ellipsoid((0, 0.12, 0), (0.2, 0.1, 0.2)), '#6d5b38')

PIECES = [
    ('se_house_a', house_a, (-4.6, -0.1, -4.5), (4.6, 7.0, 5.0), 0.09, 16000, SE, bricks()),
    ('se_house_b', house_b, (-4.6, -0.1, -3.6), (4.6, 6.8, 4.6), 0.1, 18000, SE, chain_post(bricks(0.2, 0.5, '#8a6a4a', 0.1), stains())),
    ('se_dome_house', dome_house, (-3.6, -0.1, -3.6), (3.6, 7.4, 3.6), 0.09, 12000, SE, stains()),
    ('se_tower', tower, (-3.2, -0.2, -3.2), (3.2, 11.5, 3.2), 0.1, 12000, SE, bricks(0.22, 0.5)),
    ('se_well', well, (-1.5, -0.1, -1.5), (1.5, 3.6, 1.5), 0.04, 5000, SE, None),
    ('se_stall', stall, (-1.8, -0.1, -1.3), (1.8, 2.8, 1.3), 0.04, 5000, SE, None),
    ('se_wall', swall, (-3.0, -0.1, -0.7), (3.0, 3.0, 0.7), 0.06, 5000, SE, bricks()),
    ('st_hall', st_hall, (-6.6, -0.1, -4.6), (6.6, 8.2, 6.0), 0.1, 26000, SE, stains(0.3)),
    ('st_dome', st_dome, (-4.9, -0.1, -4.9), (4.9, 7.2, 4.9), 0.1, 14000, SE, stains(0.25)),
    ('st_dish', dish, (-2.6, -0.1, -2.6), (2.6, 5.4, 2.6), 0.06, 5000, SE, None),
    ('st_tank', tank, (-1.9, -0.1, -1.9), (2.0, 5.5, 2.4), 0.06, 6000, SE, None),
    ('st_generator', generator, (-1.4, -0.1, -0.9), (2.0, 2.2, 0.9), 0.04, 5000, SE, None),
    ('co_corridor', corridor, (-2.8, -0.1, -4.2), (2.8, 3.9, 4.2), 0.09, 12000, SE, stains()),
    ('co_hall', co_hall, (-9.8, -0.1, -9.8), (9.8, 8.0, 9.8), 0.13, 30000, dict(SE, dirt=(0, 2.0, 0.6)), stains()),
    ('co_door', co_door, (-3.0, -0.1, -0.8), (3.0, 6.0, 0.8), 0.05, 6000, SE, strata('#7a5a40', 3, 0.5)),
    ('co_terminal', terminal, (-0.6, -0.05, -0.4), (0.6, 1.5, 0.4), 0.025, 2500, SE, None),
    ('fr_spire_0', spire(14, 3.2, 1.0, (0.08, 0.0)), (-5, -0.5, -5), (7, 15, 5), 0.16, 8000, SEF, strata('#c48a62', 2.3, 1.0)),
    ('fr_spire_1', spire(9, 2.4, 2.0, (-0.1, 0.05)), (-5, -0.5, -4), (4, 10, 4), 0.12, 6000, SEF, strata('#c48a62', 2.6, 1.0)),
    ('fr_spire_2', spire(19, 4.0, 3.0, (0.04, -0.06)), (-6, -0.5, -8), (8, 20, 6), 0.2, 9000, SEF, strata('#c48a62', 2.0, 1.0)),
    ('fr_arch', arch_rock, (-11, -0.5, -4), (11, 9, 4), 0.2, 9000, SEF, strata('#c48a62', 2.5, 1.0)),
    ('fr_crystal', crystal, (-1.6, -0.2, -1.6), (1.6, 3.0, 1.6), 0.06, 4000, SEF, None),
    ('fr_crack', crack, (-1.8, -0.1, -0.5), (1.8, 0.3, 14.5), 0.07, 5000, SEF, None),
    ('fr_rock', rock_a, (-2, -0.2, -2), (2, 2.0, 2), 0.09, 2500, SEF, strata('#c48a62', 4, 1.0)),
    ('fr_rock2', rock_b, (-1.6, -0.2, -1.4), (2, 1.5, 1.6), 0.07, 2200, SEF, strata('#c48a62', 4, 1.0)),
    ('fr_slab', slab, (-2.5, -0.1, -1.0), (2.5, 3.2, 1.0), 0.07, 3500, SEF, strata('#c48a62', 3, 0.8)),
    ('p_crate', crate, (-0.7, -0.05, -0.7), (0.7, 1.1, 0.7), 0.03, 1500, SE, None),
    ('p_barrel', barrel, (-0.6, -0.05, -0.6), (0.6, 1.2, 0.6), 0.03, 1500, SE, None),
    ('p_tent', tent, (-2.2, -0.05, -2.0), (2.2, 2.4, 2.0), 0.05, 3000, SE, None),
    ('p_deadtree', deadtree, (-1.8, -0.05, -1.0), (2.2, 4.8, 1.0), 0.05, 3200, SE, None),
    ('p_bones', bones, (-0.6, -0.05, -0.6), (0.6, 0.7, 0.6), 0.025, 1500, SE, None),
    ('p_wreck', wreck, (-2.4, -0.05, -2.4), (2.4, 2.8, 2.4), 0.07, 7000, SE, stains()),
    ('p_lantern', lantern, (-1.3, -0.05, -1.3), (1.3, 3.8, 1.3), 0.04, 4000, SE, None),
    ('p_decoy', decoy, (-0.2, -0.02, -0.2), (0.2, 0.6, 0.2), 0.012, 1200, dict(ao_scale=0.1, edge_k=3), None),
    ('p_shard', shard, (-0.2, -0.25, -0.2), (0.2, 0.3, 0.2), 0.012, 600, dict(ao_scale=0.1), None),
    ('p_crate_cache', cache, (-0.6, -0.05, -0.4), (0.6, 0.85, 0.4), 0.025, 1500, SE, None),
    ('p_sandbags', sandbags, (-1.0, -0.05, -0.4), (1.0, 0.7, 0.4), 0.04, 1600, SE, None),
    ('p_cable', spool, (-0.7, -0.05, -0.7), (0.7, 1.2, 0.7), 0.03, 1200, SE, None),
    ('p_pot', pot, (-0.5, -0.05, -0.5), (0.5, 0.8, 0.5), 0.025, 1000, SE, None),
    ('p_shrub', shrub, (-0.8, -0.05, -0.8), (0.8, 0.9, 0.8), 0.03, 800, SE, None),
]

if __name__ == '__main__':
    import pickle, time
    only = sys.argv[1:] ; t = time.time()
    for (n, fn, lo, hi, vox, tris, st, post) in PIECES:
        if only and n not in only: continue
        mk(n, fn, lo, hi, vox, tris, st, post)
    print('env done', round(time.time() - t), 's', sum(len(m.f) for m in M.values()), 'tris')
    pickle.dump(M, open('/tmp/env_%s.pkl' % ('_'.join(only) if only else 'all'), 'wb'))
