import numpy as np, json, os
OUT='/home/claude/ashen_echo'; MD=OUT+'/assets/models'
os.makedirs(MD,exist_ok=True)
class Rig:
    def __init__(s,name): s.name=name; s.piv={}; s.parts=[]
    def pivot(s,n,parent,pos): s.piv[n]=(parent,np.array(pos,float))
    def part(s,piv,name,mesh): s.parts.append((piv,name,mesh))
    def chain(s,p):
        c=[]
        while p: c.append(p); p=s.piv[p][0]
        return c
    def posed(s,rots=None):
        rots=rots or {}; out=[]
        for piv,name,m in s.parts:
            mm=m.copy()
            for p in s.chain(piv):
                if p in rots:
                    R=rots[p]; a=s.piv[p][1]; mm.v=(mm.v-a)@R.T+a; mm.n=mm.n@R.T
            out.append(mm)
        return out
    def export(s,prefix):
        d={'pivots':[],'parts':[]}
        for n,(par,pos) in s.piv.items():
            pp=s.piv[par][1] if par else np.zeros(3)
            d['pivots'].append({'name':n,'parent':par or '','pos':[round(float(x),4) for x in (pos-pp)]})
        for piv,name,m in s.parts:
            mm=m.copy(); mm.v=mm.v-s.piv[piv][1]
            fn=f'{prefix}_{name}.glb'; mm.save(f'{MD}/{fn}')
            d['parts'].append({'pivot':piv,'mesh':fn,'mat':'painted'})
        return d
