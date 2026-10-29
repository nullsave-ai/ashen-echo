import numpy as np, math
from sdf import *

def inter(a, b): return lambda P: np.maximum(a(P), b(P))
def subt(a, b): return lambda P: np.maximum(a(P), -b(P))
def uni(a, b, k=0.0): return lambda P: np.minimum(a(P), b(P))
RX = rotm((1, 0, 0), math.pi / 2)      # +Y axis -> +Z axis (for z-facing cylinders)
RZ = rotm((0, 0, 1), math.pi / 2)      # +Y -> -X (x-axis cylinders)
SK = '#a96a40'; SKD = '#7e4a2c'
SM = dict(ao_scale=0.12, edge_k=3.2, cav_k=2.0, brush_f=16.0, drift_f=5.0, drift=0.5)

def stripe_post(bands):
    """bands: list of (axis, freq, width, colour) painted over colour field"""
    def post(V, N, col, glow):
        for ax, fr, w, c in bands:
            m = (np.abs(((V[:, ax] * fr) % 1.0) - 0.5) < w) & (np.abs(col - hexc('#d5a968')[None, :]).sum(1) < 0.22)
            col = np.where(m[:, None], hexc(c)[None, :], col)
        return col, glow, {}
    return post

def head():
    s = Sculpt()
    s.add(ellipsoid((0, 1.655, 0.006), (0.088, 0.092, 0.092)), SK)
    s.add(rcone((0, 1.612, -0.03), (0, 1.565, -0.048), 0.066, 0.034), SK, k=0.035)
    s.add(sphere((0.052, 1.604, -0.05), 0.027), SK, k=0.03); s.add(sphere((-0.052, 1.604, -0.05), 0.027), SK, k=0.03)
    s.add(capsule((-0.058, 1.672, -0.084), (0.058, 1.672, -0.084), 0.014), SK, k=0.024)
    s.add(rcone((0, 1.664, -0.088), (0, 1.607, -0.116), 0.008, 0.014), SK, k=0.012)
    for sx in (-1, 1):
        s.add(sphere((sx * 0.0145, 1.603, -0.109), 0.0085), SK, k=0.01)
        s.cut(sphere((sx * 0.037, 1.653, -0.078), 0.0205), SKD, k=0.012)
        s.add(sphere((sx * 0.037, 1.653, -0.082), 0.0135), '#f1e6cc')
        s.add(sphere((sx * 0.037, 1.653, -0.0925), 0.007), '#40ffe6', g=1.0)
        s.add(ellipsoid((sx * 0.037, 1.667, -0.09), (0.019, 0.0075, 0.013)), SK, k=0.005)
        s.add(ellipsoid((sx * 0.087, 1.642, 0.006), (0.011, 0.025, 0.017)), SK, k=0.01)
    s.add(ellipsoid((0, 1.583, -0.092), (0.023, 0.0075, 0.011)), '#7c3a2e', k=0.008)
    s.add(capsule((0, 1.50, 0.005), (0, 1.58, -0.005), 0.05), SK, k=0.03)
    # hair mass + fringe
    hair = '#1c0f0c'
    s.add(inter(ellipsoid((0, 1.636, 0.034), (0.09, 0.088, 0.082)), lambda P: (1.664 - P[:, 1]) * 0.9 + 0.35 * (P[:, 2] - 0.0) * 0 ), hair, k=0.006)
    for sx in (-1, 1):
        s.add(rcone((sx * 0.072, 1.69, -0.05), (sx * 0.083, 1.60, -0.03), 0.009, 0.006), hair, k=0.01)
    # headwrap with folds
    ymin = lambda P: 1.672 + 0.40 * (-P[:, 2])
    wrap = inter(ellipsoid((0, 1.688, 0.012), (0.1, 0.108, 0.108)), lambda P: (ymin(P) - P[:, 1]) * 0.9)
    wrap = displace(wrap, lambda P: 0.0045 * np.sin(34 * P[:, 1] + 9 * np.arctan2(P[:, 0], P[:, 2]) + 4 * fbm(P, 9, 2)))
    s.add(wrap, '#d5a968', k=0.01)
    s.add(sphere((0.075, 1.745, -0.01), 0.038), '#b5432b', k=0.02)
    s.add(rcone((-0.07, 1.70, 0.08), (-0.105, 1.60, 0.115), 0.034, 0.02), '#b5432b', k=0.015)
    # goggles
    for sx in (-1, 1):
        s.add(cylinder((sx * 0.04, 1.718, -0.098), 0.022, 0.01, RX, 0.004), '#3dffe8', g=0.85)
        s.add(torus((sx * 0.04, 1.718, -0.097), 0.025, 0.006, RX), '#c99b3c', k=0.004)
    s.add(capsule((-0.015, 1.718, -0.1), (0.015, 1.718, -0.1), 0.006), '#c99b3c')
    strap = inter(shell(ellipsoid((0, 1.718, 0.01), (0.1, 0.1, 0.108)), 0.006), lambda P: np.abs(P[:, 1] - 1.718) - 0.013)
    s.add(strap, '#3a2316')
    return s.mesh((-0.16, 1.47, -0.16), (0.16, 1.80, 0.18), 0.0045, tris=10000, style=SM, post=stripe_post([(1, 90, 0.07, '#b5432b')]))
if __name__ == '__main__':
    import time; t = time.time(); h = head(); print(len(h.f), 'tris', time.time() - t)
    for i, (yaw, nm) in enumerate(((0.45, 'a'), (-0.5, 'b'))):
        render([h], size=(700, 700), yaw=yaw, pitch=-0.03, target=(0, 1.64, 0), dist=0.85, fov=28).save(f'/home/claude/ashen_echo/previews/_head_{nm}.png')
