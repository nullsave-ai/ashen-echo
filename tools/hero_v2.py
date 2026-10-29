import numpy as np, math, sys
from sdf import *
from hero_sculpt import inter, subt, RX, RZ, SK, SKD, head as sculpt_head, stripe_post
from rigv2 import Rig

ST = dict(ao_scale=0.16, edge_k=2.6, cav_k=1.8, brush_f=18.0, drift_f=5.0, drift=0.5)
STB = dict(ao_scale=0.3, edge_k=1.6, cav_k=1.4, brush_f=12.0, drift_f=4.0, drift=0.6)
TAN = '#c79c5e'; TAN2 = '#a47e47'; RED = '#a8321f'; TEAL = '#1d8c88'; GOLD = '#e0b552'; LEA = '#6e4527'; LEAD = '#3a2316'; METAL = '#2f464b'; BRASS = '#c99b3c'; CANV = '#8f7649'

def folds(freq, amp, ax=1, ang=True, seed=3.0):
    def f(P):
        a = np.arctan2(P[:, 0], P[:, 2]) if ang else 0
        return amp * np.sin(freq * P[:, ax] + 7 * a + 5 * fbm(P, 8, 2, seed))
    return f

def build():
    R = Rig('hero')
    R.pivot('hips', None, (0, 0.95, 0)); R.pivot('spine', 'hips', (0, 1.04, 0)); R.pivot('head', 'spine', (0, 1.50, 0))
    R.pivot('braid', 'head', (0, 1.66, 0.085)); R.pivot('scarf', 'spine', (0, 1.46, 0.09)); R.pivot('weapon', 'hips', (0.15, 1.33, -0.25))
    for sd, x in (('r', 0.21), ('l', -0.21)):
        R.pivot(f'sh_{sd}', 'spine', (x, 1.42, 0)); R.pivot(f'el_{sd}', f'sh_{sd}', (x * 1.1, 1.17, 0))
        R.pivot(f'th_{sd}', 'hips', (x * 0.5, 0.93, 0)); R.pivot(f'kn_{sd}', f'th_{sd}', (x * 0.5, 0.52, 0))
    V = 0.0065
    # ------------- head
    R.part('head', 'head', sculpt_head())
    # braid (sway pivot)
    s = Sculpt()
    for i in range(9):
        y = 1.665 - i * 0.04; z = 0.085 + 0.012 * i
        s.add(ellipsoid((0.004 * (-1) ** i, y, z), (0.028 - i * 0.0018, 0.024, 0.026 - i * 0.0015)), '#1f100c', k=0.01)
    s.add(sphere((0.0, 1.665 - 8 * 0.04 - 0.02, 0.19), 0.017), BRASS, k=0.004)
    R.part('braid', 'braid', s.mesh((-0.08, 1.28, 0.03), (0.08, 1.70, 0.26), 0.0045, tris=2500, style=ST))
    # ------------- torso (undershirt + vest + straps + plate)
    s = Sculpt()
    s.add(ellipsoid((0, 1.27, -0.004), (0.172, 0.21, 0.112)), '#d2a867')
    s.add(capsule((0, 0.98, 0), (0, 1.2, 0), 0.135), '#d2a867', k=0.06)
    s.add(capsule((-0.2, 1.43, 0), (0.2, 1.43, 0), 0.05), '#d2a867', k=0.05)
    for sx in (-1, 1): s.add(ellipsoid((sx * 0.058, 1.33, -0.075), (0.07, 0.055, 0.05)), '#d2a867', k=0.04)
    vest = inter(shell(ellipsoid((0, 1.25, -0.004), (0.186, 0.2, 0.124)), 0.011), lambda P: np.abs(P[:, 1] - 1.22) - 0.205)
    vest = subt(vest, rbox((0, 1.27, -0.14), (0.018, 0.22, 0.05), 0.01))
    vest = displace(vest, folds(40, 0.003, 1, True, 5.0))
    s.add(vest, LEA, k=0.008)
    s.add(capsule((-0.13, 1.42, -0.1), (0.1, 1.12, -0.125), 0.014), LEAD, k=0.004); s.add(capsule((0.13, 1.42, -0.1), (-0.1, 1.12, -0.125), 0.014), LEAD, k=0.004)
    s.add(rbox((0.0, 1.27, -0.138), (0.017, 0.017, 0.01), 0.004), BRASS)
    s.add(rbox((0.075, 1.335, -0.128), (0.045, 0.034, 0.012), 0.008), METAL); s.add(sphere((0.075, 1.335, -0.14), 0.0145), '#3dffe8', g=1.0)
    s.add(torus((0, 1.49, 0.0), 0.078, 0.032), '#1f948e', k=0.01)
    s.add(displace(torus((0, 1.475, 0.0), 0.085, 0.022), folds(60, 0.004, 1)), '#1f948e', k=0.01)
    R.part('spine', 'torso', s.mesh((-0.3, 0.96, -0.22), (0.3, 1.56, 0.2), V, tris=9000, style=ST, post=stripe_post([(1, 30, 0.08, GOLD)])))
    # backpack
    s = Sculpt()
    s.add(rbox((0, 1.26, 0.168), (0.145, 0.19, 0.082), 0.045), CANV)
    s.add(rbox((0, 1.08, 0.18), (0.1, 0.06, 0.07), 0.025), CANV, k=0.02)
    s.add(displace(cylinder((0, 1.5, 0.19), 0.062, 0.17, RZ, 0.02), folds(70, 0.0025, 0, False)), RED, k=0.012)
    s.add(rbox((0, 1.31, 0.255), (0.085, 0.092, 0.028), 0.01), METAL)
    s.add(torus((0, 1.31, 0.285), 0.045, 0.012, RX), '#3dffe8', g=1.0); s.add(torus((0, 1.31, 0.3), 0.028, 0.01, RX), '#3dffe8', g=1.0)
    s.add(capsule((0.11, 1.4, 0.24), (0.14, 1.93, 0.27), 0.005), BRASS); s.add(sphere((0.14, 1.93, 0.27), 0.012), '#3dffe8', g=1.0)
    s.add(capsule((-0.12, 1.15, 0.2), (-0.12, 1.45, 0.25), 0.01), LEAD)
    R.part('spine', 'backpack', s.mesh((-0.25, 0.96, 0.03), (0.25, 1.98, 0.36), 0.008, tris=5500, style=STB, post=stripe_post([(0, 14, 0.18, GOLD)])))
    # scarf tail (pivot scarf)
    s = Sculpt()
    rb = rbox((0, 1.1, 0.1), (0.05, 0.36, 0.004), 0.002)
    w = lambda P: P + np.stack([0.02 * np.sin(14 * P[:, 1]), np.zeros(len(P)), -(1.47 - P[:, 1]) * 0.07 + 0.02 * np.sin(9 * P[:, 1])], 1)
    s.add(warp(rb, w), '#1f948e')
    R.part('scarf', 'scarf_tail', s.mesh((-0.12, 0.7, 0.0), (0.12, 1.5, 0.3), 0.005, tris=2200, style=ST, post=stripe_post([(1, 12, 0.07, GOLD)])))
    # ------------- hips: trousers, belt, pouches, skirt
    s = Sculpt()
    s.add(ellipsoid((0, 0.96, 0), (0.172, 0.11, 0.115)), TAN2)
    belt = inter(shell(ellipsoid((0, 1.01, 0), (0.184, 0.05, 0.126)), 0.011), lambda P: np.abs(P[:, 1] - 1.01) - 0.028)
    s.add(belt, LEAD, k=0.004)
    s.add(rbox((0, 1.012, -0.128), (0.032, 0.026, 0.01), 0.006), BRASS)
    for sx in (-1, 1):
        s.add(rbox((sx * 0.2, 0.93, -0.01), (0.038, 0.055, 0.05), 0.016), LEA, k=0.006); s.add(rbox((sx * 0.2, 0.975, -0.01), (0.04, 0.014, 0.052), 0.008), LEAD)
    s.add(rbox((0, 0.95, 0.135), (0.07, 0.045, 0.025), 0.01), LEA)
    R.part('hips', 'pelvis', s.mesh((-0.3, 0.84, -0.2), (0.3, 1.06, 0.2), V, tris=3500, style=ST))
    s = Sculpt()
    ang = lambda P: np.arctan2(P[:, 0], -P[:, 2])
    outer = lambda P: (np.hypot(P[:, 0] / 1.0, P[:, 2] / 0.78) - (0.195 + (0.99 - P[:, 1]) * 0.30)) * 0.9
    sk = inter(inter(shell(outer, 0.016), lambda P: P[:, 1] - 0.995), lambda P: (0.64 + 0.02 * np.sin(7 * ang(P) + 1.3) - P[:, 1]))
    sk = displace(sk, lambda P: 0.012 * np.sin(11 * ang(P) + 3 * fbm(P, 6, 2)))
    s.add(sk, RED)
    flap = warp(rbox((-0.1, 0.8, -0.17), (0.085, 0.17, 0.006), 0.003), lambda P: P + np.stack([np.zeros(len(P)), np.zeros(len(P)), 0.012 * np.sin(18 * P[:, 1])], 1))
    s.add(flap, '#1f948e')
    R.part('hips', 'skirt', s.mesh((-0.34, 0.6, -0.3), (0.34, 1.0, 0.3), 0.007, tris=4500, style=ST, post=stripe_post([(1, 9, 0.1, GOLD)])))
    # ------------- legs / boots
    for sd, x in (('r', 0.1), ('l', -0.1)):
        s = Sculpt()
        s.add(rcone((x, 0.95, 0), (x, 0.53, 0.0), 0.088, 0.058), TAN2)
        s.add(displace(rcone((x, 0.9, 0), (x, 0.55, 0), 0.093, 0.062), folds(55, 0.003, 1)), TAN2, k=0.01)
        R.part(f'th_{sd}', f'thigh_{sd}', s.mesh((x - 0.14, 0.5, -0.14), (x + 0.14, 0.98, 0.14), V, tris=2600, style=ST))
        s = Sculpt()
        s.add(rcone((x, 0.54, 0), (x, 0.22, 0.003), 0.058, 0.046), TAN2)
        s.add(rbox((x, 0.52, -0.052), (0.044, 0.045, 0.016), 0.01), LEA, k=0.005)
        for i in range(5): s.add(torus((x, 0.34 - i * 0.032, 0.002), 0.054 - i * 0.002, 0.0085), RED, k=0.004)
        s.add(rcone((x, 0.24, 0), (x, 0.07, -0.006), 0.057, 0.062), '#5a3620', k=0.01)
        s.add(torus((x, 0.235, 0), 0.058, 0.012), LEA, k=0.004)
        s.add(ellipsoid((x, 0.05, -0.095), (0.054, 0.046, 0.105)), '#5a3620', k=0.02)
        s.add(rbox((x, 0.022, -0.07), (0.062, 0.016, 0.17), 0.012), '#2a1810', k=0.004)
        s.add(rbox((x, 0.022, 0.05), (0.052, 0.022, 0.03), 0.01), '#2a1810', k=0.004)
        for i in range(3): s.add(capsule((x - 0.03, 0.14 - i * 0.025, -0.052), (x + 0.03, 0.14 - i * 0.025, -0.052), 0.005), '#d8c8a0', k=0.002)
        R.part(f'kn_{sd}', f'shin_{sd}', s.mesh((x - 0.12, 0.0, -0.24), (x + 0.12, 0.56, 0.12), V, tris=4200, style=ST))
    # ------------- arms
    for sd, x, sg in (('r', 0.21, 1), ('l', -0.21, -1)):
        s = Sculpt()
        s.add(rcone((x, 1.43, 0), (x * 1.1, 1.17, 0), 0.05, 0.04), TAN)
        s.add(displace(shell(rcone((x * 1.0, 1.41, 0), (x * 1.09, 1.2, 0), 0.058, 0.05), 0.008), folds(60, 0.003, 1)), RED, k=0.01)
        s.add(torus((x * 1.09, 1.2, 0), 0.052, 0.012), RED, k=0.006)
        if sd == 'l':
            s.add(ellipsoid((-0.245, 1.46, 0), (0.09, 0.062, 0.088)), LEA, k=0.012)
            s.add(torus((-0.245, 1.435, 0), 0.085, 0.01), BRASS, k=0.004)
            for a in range(5): s.add(sphere((-0.245 + 0.05 * math.cos(a * 1.25), 1.5, 0.05 * math.sin(a * 1.25)), 0.008), BRASS)
        else:
            s.add(ellipsoid((0.228, 1.455, 0), (0.07, 0.05, 0.068)), TEAL, k=0.012)
        R.part(f'sh_{sd}', f'uarm_{sd}', s.mesh((x - 0.16, 1.1, -0.12), (x + 0.16, 1.55, 0.12), V, tris=2800, style=ST))
        s = Sculpt(); xe = x * 1.1
        s.add(rcone((xe, 1.17, 0), (x * 1.13, 0.93, -0.02), 0.04, 0.028), SK)
        s.add(displace(shell(rcone((xe, 1.1, -0.004), (x * 1.128, 0.955, -0.018), 0.047, 0.036), 0.007), folds(50, 0.002, 1)), LEA, k=0.006)
        s.add(torus((x * 1.12, 1.03, -0.014), 0.043, 0.007), BRASS, k=0.003)
        hx = x * 1.14
        s.add(rbox((hx, 0.89, -0.03), (0.026, 0.035, 0.016), 0.012), LEAD, k=0.006)
        for i in range(4): s.add(capsule((hx - 0.021 + i * 0.014, 0.865, -0.03), (hx - 0.021 + i * 0.014, 0.82, -0.048), 0.0075), LEAD, k=0.006)
        s.add(capsule((hx - sg * 0.028, 0.9, -0.03), (hx - sg * 0.036, 0.865, -0.05), 0.009), LEAD, k=0.006)
        R.part(f'el_{sd}', f'farm_{sd}', s.mesh((x - 0.08, 0.76, -0.14), (x * 1.2 + 0.08, 1.2, 0.1), 0.005, tris=3600, style=ST))
    # ------------- weapon (several toggleable parts) -----------------
    o = np.array([0.15, 1.33, -0.25])
    def W(*a): return tuple(o + np.array(a))
    s = Sculpt()
    s.add(rbox(W(0, 0, 0), (0.026, 0.046, 0.14), 0.01), METAL)
    s.add(rbox(W(0, 0.045, -0.03), (0.016, 0.012, 0.12), 0.004), '#4d6a70')
    s.add(rcone(W(0, 0.0, 0.14), W(0, -0.045, 0.34), 0.026, 0.034), '#7a4a26', k=0.02)
    s.add(rbox(W(0, -0.045, 0.37), (0.02, 0.06, 0.03), 0.01), '#7a4a26', k=0.02)
    s.add(rcone(W(0, -0.04, 0.05), W(0, -0.115, 0.075), 0.018, 0.015), '#7a4a26', k=0.012)
    s.add(capsule(W(0, 0.01, -0.12), W(0, 0.01, -0.69), 0.011), METAL, k=0.004)
    s.add(displace(cylinder(W(0, 0.005, -0.27), 0.03, 0.11, RX, 0.01), lambda P: 0.002 * np.sin(120 * P[:, 2])), BRASS, k=0.006)
    s.add(cylinder(W(0, 0.01, -0.69), 0.02, 0.03, RX, 0.006), BRASS)
    s.add(rbox(W(0, -0.085, -0.07), (0.016, 0.055, 0.03), 0.008), LEAD)
    s.add(rbox(W(0, 0.075, -0.2), (0.005, 0.014, 0.005), 0.002), BRASS); s.add(rbox(W(0, 0.07, 0.08), (0.007, 0.012, 0.007), 0.002), BRASS)
    s.add(sphere(W(0, 0.02, 0.0), 0.012), '#3dffe8', g=1.0)
    R.part('weapon', 'rifle_body', s.mesh(W(-0.06, -0.15, -0.74), W(0.06, 0.1, 0.42), 0.0045, tris=5200, style=dict(ao_scale=0.1, edge_k=3.0, brush_f=24.0)))
    def single(name, build, lo, hi, tris=1200):
        s = Sculpt(); build(s); R.part('weapon', name, s.mesh(W(*lo), W(*hi), 0.0045, tris=tris, style=dict(ao_scale=0.1, edge_k=3.0, brush_f=24.0)))
    def coil(s):
        for z in (-0.4, -0.45, -0.5): s.add(torus(W(0, 0.01, z), 0.034, 0.011, RX), '#3dffe8', g=1.0)
        s.add(cylinder(W(0, 0.01, -0.45), 0.02, 0.07, RX, 0.004), '#1a3a3d')
    single('rifle_coil', coil, (-0.06, -0.06, -0.56), (0.06, 0.07, -0.34))
    def scope(s):
        s.add(capsule(W(0, 0.09, -0.06), W(0, 0.09, 0.06), 0.02), METAL); s.add(cylinder(W(0, 0.09, -0.085), 0.027, 0.02, RX, 0.006), BRASS)
        s.add(cylinder(W(0, 0.09, -0.108), 0.021, 0.004, RX), '#3dffe8', g=0.9); s.add(rbox(W(0, 0.065, 0.0), (0.008, 0.02, 0.03), 0.004), BRASS)
    single('rifle_scope', scope, (-0.05, 0.04, -0.14), (0.05, 0.13, 0.1))
    single('rifle_maglong', lambda s: s.add(rbox(W(0, -0.13, -0.07), (0.018, 0.09, 0.034), 0.008), METAL), (-0.04, -0.25, -0.12), (0.04, -0.03, -0.02))
    single('rifle_suppressor', lambda s: s.add(cylinder(W(0, 0.01, -0.78), 0.025, 0.09, RX, 0.008), '#26363a'), (-0.05, -0.05, -0.9), (0.05, 0.06, -0.68))
    return R

if __name__ == '__main__':
    import time; t = time.time()
    R = build(); print('sculpted', sum(len(m.f) for _, _, m in R.parts), 'tris', round(time.time() - t), 's')
    import pickle; pickle.dump(R, open('/tmp/hero.pkl', 'wb'))
