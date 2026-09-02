import json, struct
from pathlib import Path

OUT = Path(__file__).parents[1] / "glb"
OUT.mkdir(parents=True, exist_ok=True)

def box(parts, pos, scale, color):
    parts.append((pos, scale, color))

def save(name, parts):
    v=[]; i=[]; mats=[]; nodes=[]
    for n,(p,s,c) in enumerate(parts):
        base=len(v)//3; x,y,z=[q/2 for q in s]
        v += [a for q in [(-x,-y,-z),(x,-y,-z),(x,y,-z),(-x,y,-z),(-x,-y,z),(x,-y,z),(x,y,z),(-x,y,z)] for a in q]
        i += [base+a for a in (0,1,2,0,2,3,4,6,5,4,7,6,0,4,5,0,5,1,1,5,6,1,6,2,2,6,7,2,7,3,4,0,3,4,3,7)]
        mats.append({"pbrMetallicRoughness":{"baseColorFactor":[*c,1],"metallicFactor":0,"roughnessFactor":.72}})
        nodes.append({"mesh":n,"translation":p})
    vb=struct.pack("<%sf"%len(v),*v); pad=b'\0'*((-len(vb))%4); ib=struct.pack("<%sH"%len(i),*i)
    data=vb+pad+ib; j={"asset":{"version":"2.0","generator":"Pawductivity low-poly asset generator"},"scene":0,"scenes":[{"nodes":list(range(len(nodes)))}],"nodes":nodes,"materials":mats,"buffers":[{"byteLength":len(data)}],"bufferViews":[{"buffer":0,"byteOffset":0,"byteLength":len(vb),"target":34962},{"buffer":0,"byteOffset":len(vb)+len(pad),"byteLength":len(ib),"target":34963}],"accessors":[{"bufferView":0,"componentType":5126,"count":len(v)//3,"type":"VEC3","min":[-4,-4,-4],"max":[4,4,4]},{"bufferView":1,"componentType":5123,"count":len(i),"type":"SCALAR"}],"meshes":[{"primitives":[{"attributes":{"POSITION":0},"indices":1,"material":n}]} for n in range(len(parts))]}
    raw=json.dumps(j,separators=(',',':')).encode(); raw+=b' '*((-len(raw))%4)
    (OUT/f'{name}.glb').write_bytes(struct.pack('<4sIII4s',b'glTF',2,12+8+len(raw)+8+len(data),len(raw),b'JSON')+raw+struct.pack('<I4s',len(data),b'BIN\0')+data)

wood=(.55,.28,.12); green=(.32,.48,.35); dark=(.08,.1,.14); orange=(.9,.28,.06); white=(.85,.86,.84); mint=(.3,.75,.62); coral=(.95,.35,.3); cream=(.92,.82,.62)
save('desk',[((0,.8,0),(3.6,.15,1.5),wood),*((p,(.16,1.5,.16),wood) for p in [(-1.55,0,-.6),(1.55,0,-.6),(-1.55,0,.6),(1.55,0,.6)]),((0,1.35,-.45),(3.4,.25,.25),wood)])
save('chair',[((0,.75,0),(1.3,.18,1.3),green),((0,1.65,.35),(1.3,1.55,.18),green),((0,.25,0),(.22,.65,.22),dark),*((p,(1.3,.12,.18),dark) for p in [(0,.05,0),(0,.05,0)])])
save('laptop',[((0,.12,0),(2.0,.12,1.35),dark),((0,1.0,-.55),(2.0,1.55,.1),dark),((0,1.0,-.48),(1.75,1.3,.04),(.25,.55,.7))])
save('cat',[((0,.6,0),(1.0,.9,.55),orange),((0,1.25,-.15),(.7,.65,.55),orange),((-.25,1.7,-.15),(.22,.3,.25),orange),((.25,1.7,-.15),(.22,.3,.25),orange),((0,.55,.7),(.18,.18,1.1),orange)])
save('camera',[((0,.55,0),(.9,.7,.7),white),((0,.15,0),(.7,.2,.7),white),((0,.55,-.38),(.35,.35,.04),dark)])
save('spray_bottle',[((0,.55,0),(.75,1.1,.5),mint),((0,1.22,0),(.65,.18,.35),coral),((0,1.42,-.2),(.65,.25,.25),coral),((0,1.2,-.52),(.18,.16,.45),coral)])
save('wall_intact',[((0,2.5,0),(5,.12,5),cream)])
save('wall_scratched',[((0,2.5,0),(5,.12,5),cream),*((p,(1.5,.04,.03),dark) for p in [(-.4,2.5,-.08),(.3,2.9,-.08),(.8,2.1,-.08)])])
save('wall_critical',[((0,2.5,0),(5,.12,5),(.45,.34,.25)),*((p,(1.3,.1,.03),dark) for p in [(-.5,2.5,-.08),(.4,3,-.08),(.8,1.8,-.08),(-.2,1.7,-.08)])])
