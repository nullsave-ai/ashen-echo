import numpy as np, math
from sdf import *
from hero_sculpt import inter, subt, RX, RZ
from rigv2 import Rig
HIDE='#3b343a'; ASH='#6d6258'; BONE='#e6dcb8'; EMB='#3dffe8'; CLAW='#d8ccaa'
ST=dict(ao_scale=0.3, edge_k=1.6, cav_k=1.4, brush_f=10.0, drift_f=3.0, drift=0.5)
def cracks(w=0.022, f=5.0, seedoff=0.0):
    def post(V,N,col,glow):
        n=fbm(V,f*1.6,3,seedoff); m=np.abs(n-0.5)<w*0.3
        col=np.where(m[:,None],hexc(EMB)[None,:],col); glow=np.where(m,1.0,glow); return col,glow,{}
    return post
def cone(a,b,r): return rcone(a,b,r,0.004)

def hound():
    R=Rig('hound')
    R.pivot('body',None,(0,0.8,0)); R.pivot('head','body',(0,0.9,-0.5)); R.pivot('jaw','head',(0,0.84,-0.62)); R.pivot('tail','body',(0,0.88,0.55))
    legs={'fr':(0.17,-0.38),'fl':(-0.17,-0.38),'br':(0.18,0.4),'bl':(-0.18,0.4)}
    for n,(x,z) in legs.items(): R.pivot(n,'body',(x,0.78,z))
    s=Sculpt()
    s.add(ellipsoid((0,0.88,-0.3),(0.21,0.25,0.3)),HIDE); s.add(ellipsoid((0,0.82,0.05),(0.17,0.2,0.3)),HIDE,k=0.12); s.add(ellipsoid((0,0.85,0.42),(0.21,0.23,0.24)),HIDE,k=0.12)
    s.add(capsule((0,1.0,-0.4),(0,1.0,0.5),0.05),ASH,k=0.06)
    for i in range(9):
        z=-0.42+i*0.11; s.add(cone((0,1.0,z),(0,1.0+0.15-abs(i-4)*0.012,z+0.07),0.04),BONE,k=0.01)
    s.add(displace(ellipsoid((0,0.84,-0.12),(0.225,0.255,0.2)),lambda P:0.012*np.sin(45*P[:,2])*(P[:,1]<0.95)),ASH,k=0.02)
    R.part('body','body',s.mesh((-0.4,0.5,-0.75),(0.4,1.3,0.9),0.012,tris=7000,style=ST,post=cracks(0.02,5.0,1.0)))
    s=Sculpt()
    s.add(rcone((0,0.9,-0.4),(0,0.99,-0.64),0.15,0.11),HIDE)
    s.add(ellipsoid((0,0.99,-0.74),(0.125,0.125,0.16)),HIDE,k=0.04); s.add(rcone((0,0.97,-0.76),(0,0.915,-1.0),0.09,0.05),HIDE,k=0.04)
    s.add(rbox((0,1.055,-0.86),(0.05,0.012,0.17),0.008),BONE,k=0.01)
    for sx in (-1,1):
        s.cut(sphere((sx*0.075,1.02,-0.82),0.03),'#111111',k=0.01); s.add(sphere((sx*0.073,1.02,-0.835),0.02),EMB,g=1.0)
        s.add(cone((sx*0.08,1.09,-0.7),(sx*0.15,1.3,-0.62),0.05),HIDE,k=0.02); s.add(cone((sx*0.1,1.06,-0.74),(sx*0.2,1.22,-0.5),0.026),BONE,k=0.01)
        for i in range(5): s.add(cone((sx*0.045,0.915,-0.84-i*0.026),(sx*0.045,0.855,-0.84-i*0.026),0.009),CLAW)
    R.part('head','skull',s.mesh((-0.3,0.78,-1.1),(0.3,1.35,-0.35),0.008,tris=4200,style=ST,post=cracks(0.014,7.0,3.0)))
    s=Sculpt(); s.add(rcone((0,0.875,-0.74),(0,0.85,-0.98),0.065,0.032),HIDE)
    for sx in (-1,1):
        for i in range(4): s.add(cone((sx*0.035,0.875,-0.84-i*0.03),(sx*0.035,0.935,-0.84-i*0.03),0.008),CLAW)
    s.add(rbox((0,0.87,-0.86),(0.03,0.006,0.1),0.003),EMB,g=1.0)
    R.part('jaw','jaw',s.mesh((-0.15,0.78,-1.05),(0.15,0.98,-0.65),0.007,tris=1400,style=ST))
    s=Sculpt(); s.add(rcone((0,0.88,0.5),(0,0.92,0.8),0.1,0.07),HIDE); s.add(rcone((0,0.92,0.8),(0,1.1,1.15),0.07,0.03),HIDE,k=0.03); s.add(rcone((0,1.1,1.15),(0,1.2,1.5),0.03,0.01),BONE); s.add(sphere((0,1.2,1.5),0.03),EMB,g=1.0)
    R.part('tail','tail',s.mesh((-0.2,0.75,0.4),(0.2,1.35,1.6),0.01,tris=1800,style=ST))
    for n,(x,z) in legs.items():
        fwd=-1 if z<0 else 1; s=Sculpt()
        if fwd<0:
            s.add(rcone((x,0.8,z),(x*1.05,0.45,z+fwd*0.06),0.11,0.05),HIDE); s.add(rcone((x*1.05,0.45,z+fwd*0.06),(x*1.05,0.1,z-0.03),0.045,0.032),HIDE,k=0.03)
        else:
            s.add(ellipsoid((x,0.72,z),(0.11,0.2,0.16)),HIDE); s.add(rcone((x,0.7,z),(x*1.05,0.42,z-0.12),0.09,0.045),HIDE,k=0.04); s.add(rcone((x*1.05,0.42,z-0.12),(x*1.05,0.08,z+0.0),0.04,0.03),HIDE,k=0.03)
        s.add(ellipsoid((x*1.05,0.04,z-0.06),(0.05,0.035,0.09)),HIDE,k=0.03)
        for c in (-1,0,1): s.add(cone((x*1.05+c*0.025,0.03,z-0.12),(x*1.05+c*0.03,0.005,z-0.22),0.012),CLAW)
        R.part(n,f'leg_{n}',s.mesh((x-0.2,0.0,z-0.3),(x+0.2,0.95,z+0.3),0.01,tris=2300,style=ST,post=cracks(0.012,6.0,5.0)))
    return R

def husk():
    R=Rig('husk')
    R.pivot('hips',None,(0,1.0,0)); R.pivot('spine','hips',(0,1.1,0)); R.pivot('head','spine',(0,1.78,-0.3))
    for sd,x in (('r',1),('l',-1)):
        R.pivot(f'sh_{sd}','spine',(x*0.38,1.7,-0.28)); R.pivot(f'el_{sd}',f'sh_{sd}',(x*0.44,1.2,-0.3)); R.pivot(f'th_{sd}','hips',(x*0.14,1.0,0)); R.pivot(f'kn_{sd}',f'th_{sd}',(x*0.15,0.55,-0.12))
    s=Sculpt()
    s.add(ellipsoid((0,1.0,0),(0.24,0.16,0.17)),HIDE); R.part('hips','pelvis',s.mesh((-0.4,0.75,-0.3),(0.4,1.25,0.3),0.014,tris=1500,style=ST))
    rag=inter(inter(shell(lambda P:np.hypot(P[:,0],P[:,2]*1.2)-(0.25+(1.0-P[:,1])*0.18),0.012),lambda P:P[:,1]-1.02),lambda P:(0.5+0.06*np.sin(9*np.arctan2(P[:,0],P[:,2]))-P[:,1]))
    s=Sculpt(); s.add(displace(rag,lambda P:0.02*np.sin(8*np.arctan2(P[:,0],P[:,2])+3*fbm(P,5,2))),'#a98657'); R.part('hips','rags',s.mesh((-0.5,0.4,-0.5),(0.5,1.05,0.5),0.012,tris=1800,style=ST))
    s=Sculpt()
    s.add(ellipsoid((0,1.45,-0.12),(0.3,0.32,0.2)),HIDE); s.add(ellipsoid((0,1.2,-0.05),(0.22,0.2,0.16)),HIDE,k=0.1); s.add(ellipsoid((0,1.74,0.04),(0.26,0.2,0.2)),ASH,k=0.1)
    for i in range(5): s.add(torus((0,1.18+i*0.1,-0.12+0.02*i),0.27+0.02*i,0.018,None),BONE,k=0.02)
    s.cut(sphere((0,1.45,-0.31),0.09),'#142a2b',k=0.03); s.add(sphere((0,1.45,-0.29),0.062),EMB,g=1.0)
    for k in range(6):
        a=k/6*6.283; s.add(cone((math.cos(a)*0.1,1.45+math.sin(a)*0.1,-0.28),(math.cos(a)*0.2,1.45+math.sin(a)*0.2,-0.4),0.025),BONE,k=0.01)
    for k in range(5): s.add(cone((0,1.8-k*0.12,0.18+k*0.02),(0,1.98-k*0.1,0.38+k*0.07),0.045),BONE,k=0.02)
    R.part('spine','torso',s.mesh((-0.45,1.0,-0.5),(0.45,2.1,0.55),0.014,tris=7000,style=ST,post=cracks(0.014,5.0,2.0)))
    s=Sculpt()
    s.add(ellipsoid((0,1.82,-0.38),(0.12,0.17,0.13)),BONE); s.add(rbox((0,1.78,-0.5),(0.075,0.12,0.012),0.01),'#26363a',k=0.01)
    for sx in (-1,1): s.add(rbox((sx*0.045,1.84,-0.515),(0.022,0.008,0.006),0.003),EMB,g=1.0)
    for i,x in enumerate((-0.09,-0.03,0.03,0.09)): s.add(cone((x,1.95,-0.38),(x*2.4,2.22+abs(x),-0.28),0.03),BONE,k=0.01)
    s.add(rcone((0,1.7,-0.42),(0,1.55,-0.42),0.06,0.03),BONE,k=0.02)
    R.part('head','skull',s.mesh((-0.35,1.45,-0.7),(0.35,2.4,-0.05),0.01,tris=3200,style=ST))
    for sd,x in (('r',1),('l',-1)):
        s=Sculpt(); s.add(rcone((x*0.38,1.7,-0.28),(x*0.44,1.2,-0.3),0.1,0.07),HIDE); s.add(ellipsoid((x*0.4,1.78,-0.28),(0.15,0.1,0.15)),'#5a3c34',k=0.03)
        R.part(f'sh_{sd}',f'uarm_{sd}',s.mesh((x*0.38-0.25,1.1,-0.5),(x*0.38+0.25,1.95,-0.05),0.012,tris=2200,style=ST,post=cracks(0.012,6.0,7.0)))
        s=Sculpt(); s.add(rcone((x*0.44,1.2,-0.3),(x*0.47,0.55,-0.34),0.07,0.045),HIDE)
        for c in (-1,0,1): s.add(cone((x*0.47+c*0.03,0.56,-0.34),(x*0.47+c*0.05,0.06,-0.5+abs(c)*0.04),0.024),BONE,k=0.006)
        R.part(f'el_{sd}',f'farm_{sd}',s.mesh((x*0.47-0.2,0.0,-0.65),(x*0.47+0.2,1.3,0.0),0.012,tris=2400,style=ST))
        s=Sculpt(); s.add(rcone((x*0.14,1.0,0),(x*0.16,0.78,0.02),0.12,0.095),HIDE,); s.add(rcone((x*0.16,0.78,0.02),(x*0.15,0.55,-0.12),0.095,0.07),HIDE,k=0.03)
        R.part(f'th_{sd}',f'thigh_{sd}',s.mesh((x*0.14-0.2,0.45,-0.25),(x*0.14+0.2,1.1,0.2),0.012,tris=1400,style=ST))
        s=Sculpt(); s.add(rcone((x*0.15,0.55,-0.12),(x*0.15,0.3,0.08),0.07,0.045),HIDE); s.add(rcone((x*0.15,0.3,0.08),(x*0.15,0.07,-0.05),0.045,0.05),HIDE,k=0.03); s.add(rbox((x*0.15,0.035,-0.14),(0.07,0.03,0.17),0.012),BONE,k=0.02)
        R.part(f'kn_{sd}',f'shin_{sd}',s.mesh((x*0.15-0.15,0.0,-0.4),(x*0.15+0.15,0.6,0.2),0.01,tris=1800,style=ST))
    return R

def burrower():
    R=Rig('burrower'); prev=None
    for i in range(6): R.pivot(f'seg{i}',prev,(0,0.3*i,0)); prev=f'seg{i}'
    R.pivot('head','seg5',(0,1.8,0))
    for i in range(6):
        r=0.55-i*0.04; y0=0.3*i; s=Sculpt()
        s.add(cylinder((0,y0+0.15,0),r+0.02,0.17,None,0.06),HIDE); s.add(torus((0,y0+0.15,0),r+0.06,0.05),ASH,k=0.03)
        R.part(f'seg{i}',f'seg{i}',s.mesh((-0.7,y0-0.05,-0.7),(0.7,y0+0.36,0.7),0.02,tris=1500,style=ST,post=cracks(0.02,4.0,i)))
    s=Sculpt(); s.add(cylinder((0,1.95,0),0.55,0.18,None,0.08),HIDE); s.cut(cylinder((0,2.12,0),0.36,0.12,None,0.04),'#10393a',k=0.05,g=0.0); s.add(cylinder((0,2.0,0),0.34,0.04,None,0.01),EMB,g=1.0)
    for k in range(4):
        a=k*math.pi/2; c,sn=math.cos(a),math.sin(a); s.add(rcone((c*0.45,2.0,sn*0.45),(c*0.2,2.8,sn*0.2),0.13,0.012),BONE,k=0.03)
    for k in range(10):
        a=k*math.pi/5+0.2; s.add(cone((math.cos(a)*0.34,2.1,math.sin(a)*0.34),(math.cos(a)*0.24,2.36,math.sin(a)*0.24),0.04),CLAW)
    R.part('head','head',s.mesh((-0.8,1.7,-0.8),(0.8,2.9,0.8),0.022,tris=3500,style=ST,post=cracks(0.02,4.0,9.0)))
    return R
if __name__=='__main__':
    import pickle,time; t=time.time()
    d={'hound':hound(),'husk':husk(),'burrower':burrower()}
    print({k:sum(len(m.f) for _,_,m in v.parts) for k,v in d.items()}, round(time.time()-t),'s')
    pickle.dump(d,open('/tmp/creatures.pkl','wb'))
