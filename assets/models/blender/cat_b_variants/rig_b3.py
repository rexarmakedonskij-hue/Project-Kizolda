"""Rig the accepted B3 source shapes with separate deformable limbs."""
import bpy, math, json, random, bisect
from pathlib import Path
from collections import defaultdict
from mathutils import Vector, Matrix, Euler
from mathutils.kdtree import KDTree
SRC=Path(__file__).resolve().parent
OUT=SRC.parents[3]/'builds/b3-rig-review'
OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(SRC/'accepted/B3-refined.blend'))
scene=bpy.context.scene
pieces=[o for o in scene.objects if o.type=='MESH' and o.name!='Studio floor']
for o in pieces:
 bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o
 bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
# Coordinates keep the existing Godot-facing convention.
def point(x,y,z):return Vector((x,-z,y))
bpy.ops.object.armature_add();rig=bpy.context.object;rig.name='CatRig';rig.show_in_front=True
bpy.ops.object.mode_set(mode='EDIT');rig.data.edit_bones.remove(rig.data.edit_bones[0])
def bone(name,a,b,parent='root'):
 q=rig.data.edit_bones.new(name);q.head=a;q.tail=b
 if parent:q.parent=rig.data.edit_bones[parent]
bone('root',point(0,0,0),point(0,.2,0),None)
bone('body',point(0,.30,0),point(0,.90,0))
bone('head',point(0,1.01,.02),point(0,1.4,.02),'body')
bone('tail',point(.16,.18,-.26),point(.42,.18,-.18))
rest={}
for side,suffix in [(-1,'L'),(1,'R')]:
 a=point(side*.159,.75,.105);b=point(side*.148,.42,.20);c=point(side*.148,.10,.28)
 rest[suffix]=(a,b,c)
 bone('upper_'+suffix,a,b);bone('fore_'+suffix,b,c);bone('paw_'+suffix,c,c+point(0,0,.12))
 a=point(side*.25,.46,-.10);b=point(side*.25,.25,-.12);c=point(side*.276,.08,.19)
 rest['H'+suffix]=(a,b,c)
 bone('upper_H'+suffix,a,b);bone('fore_H'+suffix,b,c);bone('paw_H'+suffix,c,c+point(0,0,.12))
bpy.ops.object.mode_set(mode='OBJECT')
def smooth(a,b,x):
 t=max(0,min(1,(x-a)/(b-a)));return t*t*(3-2*t)
# Rebuild the same source ellipsoids as separate anatomical surfaces. Cutting
# the fused seated skin made flat caps through the chest, unsuitable for motion.
import ast
source=ast.parse((SRC/'build_b3_refined.py').read_text())
helpers=ast.Module(body=[node for node in source.body if isinstance(node,ast.FunctionDef) and node.name in ('co','mat','ball','union','mix','color','paint','mesh','fur')],type_ignores=[])
ns={'bpy':bpy,'math':math,'Vector':Vector,'width':1.06,'fur_scale':1.12,'random':random,'bisect':bisect}
exec(compile(helpers,'accepted-shape-helpers','exec'),ns)
ball,union,paint=ns['ball'],ns['union'],ns['paint']
coat=ns['mat']('Rig coat',(.28,.205,.17));white=ns['mat']('Rig mittens',(.84,.8,.7))
old_body=bpy.data.objects['Body_anatomy'];pieces.remove(old_body);bpy.data.objects.remove(old_body,do_unlink=True)
body_parts=[ball('Pelvis',(0,.40,-.08),(.60,.72,.55),coat),ball('Ribcage',(0,.72,.005),(.45,.64,.42),coat),ball('Neck',(0,.995,.015),(.34,.45,.33),coat)]
body=union('Body_anatomy skin',body_parts,.009);paint(body,'body');new_pieces=[body]
for side,suffix in [(-1,'L'),(1,'R')]:
 arm_parts=[ball('Shoulder',(side*.15,.72,.105),(.17,.43,.21),coat),ball('Foreleg',(side*.14,.39,.20),(.115,.57,.13),coat),ball('Wrist',(side*.14,.16,.23),(.13,.21,.14),white),ball('Forepaw',(side*.14,.074,.28),(.17,.14,.24),white)]
 for j in [-1,0,1]:arm_parts.append(ball('Toe',(side*.14+j*.043,.056,.345),(.057,.088,.10),white))
 arm=union('Foreleg_'+suffix+' skin',arm_parts,.006);paint(arm,'body');new_pieces.append(arm)
 hind_parts=[ball('Haunch',(side*.225,.28,-.04),(.29,.44,.40),coat),ball('Rear foot',(side*.26,.082,.17),(.18,.155,.31),white)]
 hind=union('Foreleg_H'+suffix+' skin',hind_parts,.006);paint(hind,'body');new_pieces.append(hind)
def limb_weights(p,suffix):
 z=p.z;paw=1-smooth(.12,.21,z);upper=smooth(.21,.34,z) if suffix.startswith('H') else smooth(.34,.50,z)
 return {'upper_'+suffix:upper,'fore_'+suffix:(1-upper)*(1-paw),'paw_'+suffix:(1-upper)*paw}
body_weights=[];tree=KDTree(sum(len(o.data.vertices) for o in new_pieces))
for o in new_pieces:
 for vertex in o.data.vertices:
  weights_here=limb_weights(vertex.co,o.name[len('Foreleg_'):].split()[0]) if o.name.startswith('Foreleg_') else {'body':1.}
  tree.insert(vertex.co,len(body_weights));body_weights.append(weights_here)
tree.balance();pieces.extend(new_pieces)
old_fur=bpy.data.objects['body groom fibers'];pieces.remove(old_fur);bpy.data.objects.remove(old_fur,do_unlink=True)
random.seed(371)
for o in new_pieces:
 count=60000 if o.name.startswith('Body_') else 15000
 pieces.append(ns['fur'](o,'body',count))
# Quantization allows batched assignments, and each strand receives its root's weights.
def bind(o):
 groups={n:o.vertex_groups.new(name=n) for n in rig.data.bones.keys()};batches=defaultdict(list)
 if o.name.startswith('Foreleg_'):
  suffix=o.name[len('Foreleg_'):].split()[0]
  for vertex in o.data.vertices:
   for name,value in limb_weights(vertex.co,suffix).items():
    if value>.001:batches[(name,round(value,3))].append(vertex.index)
 elif o.name=='Body_anatomy skin':
  batches[('body',1.)]=list(range(len(o.data.vertices)))
 elif o.name.startswith('body groom fibers'):
  assert len(o.data.vertices)%18==0,'Expected six triangular rings per strand'
  for first in range(0,len(o.data.vertices),18):
   root=sum((o.data.vertices[first+j].co for j in range(3)),Vector())/3
   _,index,_=tree.find(root)
   for name,value in body_weights[index].items():
    if value>.001:batches[(name,round(value,3))].extend(range(first,first+18))
 else:
  name='tail' if o.name in ('Tail','tail groom fibers') else 'head'
  batches[(name,1.)]=list(range(len(o.data.vertices)))
 for (name,value),indices in batches.items():groups[name].add(indices,value,'REPLACE')
 modifier=o.modifiers.new('B3 skin','ARMATURE');modifier.object=rig;modifier.use_deform_preserve_volume=False;o.parent=rig
for o in pieces:bind(o)
print('B3_BOUND',len(pieces),'meshes',flush=True)
rig.animation_data_create();scene.render.fps=30

def reset():
 for p in rig.pose.bones:p.matrix_basis=Matrix.Identity(4);p.rotation_mode='QUATERNION'
def key(frame):
 for p in rig.pose.bones:
  for prop in ['location','rotation_quaternion','scale']:p.keyframe_insert(prop,frame=frame)
def limb(suffix,a,c,bend_direction=None):
 ar,br,cr=rest[suffix];l1=(br-ar).length;l2=(cr-br).length
 axis=(c-a).normalized();distance=min((c-a).length,l1+l2-.0001)
 along=(l1*l1-l2*l2+distance*distance)/(2*distance)
 side=-1 if suffix.endswith('L') else 1
 bend=bend_direction if bend_direction is not None else (Vector((0,1,0)) if suffix.startswith('H') else Vector((side,0,0)));bend=(bend-axis*bend.dot(axis)).normalized()
 b=a+axis*along+bend*math.sqrt(max(0,l1*l1-along*along))
 for name,start,end,old_start,old_end in [('upper_',a,b,ar,br),('fore_',b,c,br,cr),('paw_',c,c+point(0,0,.12),cr,cr+point(0,0,.12))]:
  q=rig.pose.bones[name+suffix]
  rotation=(old_end-old_start).rotation_difference(end-start).to_matrix().to_4x4()
  q.matrix=Matrix.Translation(start)@rotation@Matrix.Translation(-old_start)@q.bone.matrix_local

actions={}
action=bpy.data.actions.new('Sit');action.use_fake_user=True;rig.animation_data.action=action;reset();key(1);key(31);actions['Sit']=action
# Same 40-frame phase schedule as the accepted dev scratch loop.
action=bpy.data.actions.new('Scratch');action.use_fake_user=True;rig.animation_data.action=action
keys=[(0,.76,.30),(.35,1.12,.44),(.40,1.12,.44),(.60,.72,.44),(.76,.68,.30),(1,.76,.30)]
for frame in range(1,42):
 phase=(frame-1)/40;reset();drop=-.018*(1-math.cos(phase*math.tau*2))
 rig.pose.bones['body'].location.y=drop
 rig.pose.bones['tail'].rotation_quaternion=Euler((0,0,.04*math.sin(phase*math.tau))).to_quaternion()
 for side,suffix in [(-1,'L'),(1,'R')]:
  ph=(phase+(0 if side==-1 else .5))%1
  for a,b in zip(keys,keys[1:]):
   if a[0]<=ph<=b[0]:
    t=(ph-a[0])/(b[0]-a[0]);t=t*t*(3-2*t)
    height=a[1]+(b[1]-a[1])*t;reach=a[2]+(b[2]-a[2])*t;break
  limb(suffix,rest[suffix][0]+point(0,drop,0),point(side*.25,height,reach))
 key(frame)
actions['Scratch']=action
# Four-foot gait: diagonal pairs, constant-speed stance and a C1 swing arc.
def foot_step(phase):
 if phase<.5:return .16-.64*phase,0.
 u=(phase-.5)*2
 reach=(2*u**3-3*u**2+1)*(-.16)+(u**3-2*u**2+u)*(-.32)+(-2*u**3+3*u**2)*.16+(u**3-u**2)*(-.32)
 return reach,.095*math.sin(math.pi*u)**2

action=bpy.data.actions.new('Walk');action.use_fake_user=True;rig.animation_data.action=action
pivot=point(0,.30,0)
for frame in range(1,26):
 phase=(frame-1)/24;reset();bob=.008*math.sin(phase*math.tau*2)
 body_transform=Matrix.Translation(point(0,.18+bob,0))@Matrix.Translation(pivot)@Matrix.Rotation(math.radians(70),4,'X')@Matrix.Translation(-pivot)
 rig.pose.bones['body'].matrix=body_transform@rig.data.bones['body'].matrix_local
 head=rig.pose.bones['head']
 head.rotation_quaternion=Euler((math.radians(-70),0,0)).to_quaternion()
 tail=rig.pose.bones['tail'];tail.matrix=Matrix.Translation(point(0,.28+bob,-.25))@tail.bone.matrix_local
 for side,suffix in [(-1,'L'),(1,'R')]:
  step=(phase+(0 if side==-1 else .5))%1
  stride,lift=foot_step(step)
  limb(suffix,body_transform@rest[suffix][0],point(side*.159,.10+lift,.54+stride),Vector((0,1,0)))
  stride,lift=foot_step((step+.5)%1)
  limb('H'+suffix,point(side*.25,.53+bob,-.06),point(side*.276,.08+lift,-.10+stride))
 key(frame)
actions['Walk']=action
# Check the new binding against real evaluated geometry before gameplay integration.
report={'meshes':len(pieces),'bones':len(rig.data.bones),'clips':list(actions),'poses':{}}
scene.cycles.samples=24
for clip,frame in [('Sit',1),('Scratch',15),('Scratch',25),('Walk',1),('Walk',7),('Walk',13)]:
 rig.animation_data.action=actions[clip];reset();scene.frame_set(frame);bpy.context.view_layer.update()
 bounds=[];deps=bpy.context.evaluated_depsgraph_get()
 for o in pieces:
  evaluated=o.evaluated_get(deps)
  bounds.extend(evaluated.matrix_world@Vector(corner) for corner in evaluated.bound_box)
 assert all(math.isfinite(v) for p in bounds for v in p)
 report['poses'][f'{clip}-{frame}']={'min':[min(p[i] for p in bounds) for i in range(3)],'max':[max(p[i] for p in bounds) for i in range(3)]}
 scene.render.filepath=str(OUT/f'{clip}-{frame}.png');bpy.ops.render.render(write_still=True)
rig.animation_data.action=actions['Sit'];reset();scene.frame_set(1)
# Keep both actions on NLA strips so GLB includes them.
for name,action in actions.items():
 track=rig.animation_data.nla_tracks.new();track.name=name;track.strips.new(name,1,action);track.mute=True
bpy.ops.object.select_all(action='DESELECT')
for o in pieces+[rig]:o.select_set(True)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'B3-rig-review.blend'))
(OUT/'validation.json').write_text(json.dumps(report,indent=2))
print('B3_RIG_REVIEW_COMPLETE',flush=True)
