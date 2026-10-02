"""Bake desk poses against the accepted rig, without changing its mesh."""
from pathlib import Path
import json
import math
import argparse
import hashlib
import re
import sys
import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[3]
arguments = sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
parser = argparse.ArgumentParser()
parser.add_argument('--output-name', default='desktop_poses')
options = parser.parse_args(arguments)
if not re.fullmatch(r'[A-Za-z][A-Za-z0-9_]*', options.output_name):
    raise ValueError('Output name must be a simple file stem')
OUTPUT_NAME = options.output_name
bpy.ops.wm.open_mainfile(filepath=str(Path(__file__).with_name('cat_reference.blend')))
rig = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')
rig.animation_data_clear()
for b in rig.pose.bones:
    b.matrix_basis = Matrix.Identity(4)
bpy.context.view_layer.update()
rest = {b.name: b.matrix.copy() for b in rig.pose.bones}
targets = []
for limb in ['front', 'back']:
    for side in ['left', 'right']:
        bone = rig.pose.bones[f'leg_{limb}_{side}_3']
        target = bpy.data.objects.new('Desk IK', None)
        bpy.context.collection.objects.link(target)
        ik = bone.constraints.new('IK')
        ik.chain_count = 3
        ik.target = target
        ik.use_stretch = False
        targets.append((limb, side, target, bone.tail.copy()))

poses = {}
anatomy = {}
kinematics = {}
DURATIONS = {'Sit':1.2,'SitDown':.65,'Stand':.55,'Crouch':.35,'CrouchDown':.28,'Jump':.8,'Land':.24,'Descend':.7,'Touch':1.2}
def ease(a,b,t):
    t=max(0,min(1,(t-a)/(b-a)))
    return t*t*(3-2*t)

def place_leg(name,start,end):
    bone=rig.pose.bones[name]
    original=bone.bone.tail_local-bone.bone.head_local
    rotation=original.rotation_difference((end-start).normalized()).to_matrix().to_4x4()
    placed=rotation @ rest[name]
    placed.translation=start
    bone.matrix=placed
    bpy.context.view_layer.update()

def rotate_about_joint(name, angle):
    """Rotate the bone around its connected joint; retain its original length."""
    bone = rig.pose.bones[name]
    pivot = bone.matrix.translation.copy()
    bone.matrix = Matrix.Translation(pivot) @ Matrix.Rotation(angle,4,'Y') @ Matrix.Translation(-pivot) @ bone.matrix
    bpy.context.view_layer.update()

def flight_phases(kind,t):
    if kind=='Jump':
        return (ease(0,.12,t)*(1-ease(.18,.38,t)),
                ease(.14,.34,t)*(1-ease(.57,.78,t)),
                ease(.57,.85,t)*(1-ease(.90,1,t)))
    return (ease(0,.14,t)*(1-ease(.20,.40,t)),
            ease(.15,.36,t)*(1-ease(.62,.84,t)),
            ease(.55,.83,t)*(1-ease(.90,1,t)))

def sitting_hind(side,ankle,amount):
    # Fold the knee forward and hold the hock above the planted paw.
    names=[f'leg_back_{side}_{i}' for i in [1,2,3]]
    hip=rest[names[0]].translation+Vector((.025*amount,0,-.070*amount))
    old_hock=rest[names[2]].translation
    rest_ankle=rig.data.bones[names[2]].tail_local
    lower=(old_hock-rest_ankle).lerp(Vector((-.024,0,.026)),amount).normalized()
    lengths=[rig.data.bones[n].length for n in names]
    hock=ankle+lower*lengths[2]
    direction=hock-hip
    distance=max(.0001,direction.length)
    forward=direction.normalized()
    pole=(rest[names[1]].translation-rest[names[0]].translation).normalized().lerp(Vector((1,0,.15)),amount)
    bend=(pole-forward*pole.dot(forward)).normalized()
    along=(lengths[0]**2-lengths[1]**2+distance**2)/(2*distance)
    height=math.sqrt(max(0,lengths[0]**2-along**2))
    knee=hip+forward*along+bend*height
    place_leg(names[0],hip,knee)
    place_leg(names[1],knee,hock)
    place_leg(names[2],hock,ankle)
for kind in DURATIONS:
    samples = []
    for frame in range(25):
        t = frame / 24
        for b in rig.pose.bones:
            b.matrix_basis = Matrix.Identity(4)
        bpy.context.view_layer.update()
        sitting = 1 if kind=='Sit' else (ease(0,1,t) if kind=='SitDown' else (1-ease(0,1,t) if kind=='Stand' else 0))
        drop = .085*sitting
        for limb,side,target,foot_rest in targets:
            if limb=='back': rig.pose.bones[f'leg_back_{side}_3'].constraints[0].influence=0 if sitting>0 else 1
        pitch = .5*sitting
        if kind in ['Crouch','CrouchDown']:
            compression=ease(0,.7,t)
            release=ease(.7,1,t)
            # The wrist fur remains clear when the haunches compress; retain
            # the same 30 mm launch offset while keeping the chest above it.
            drop=.040*compression-.010*release
            pitch=-.035*compression
        if kind=='Jump':
            drop=.03*(1-ease(0,.22,t))
            pitch=-.035*(1-ease(0,.10,t))+.18*math.sin(math.pi*t)*(1-.25*ease(.62,1,t))
        if kind=='Descend':
            drop=.03*(1-ease(0,.18,t))
            pitch=-.035*(1-ease(0,.10,t))-.25*math.sin(math.pi*t)
        if kind=='Land':
            impact=math.sin(math.pi*t)**2
            drop=.035*impact
            pitch=-.04*impact
        pivot = rest['pelvis'].translation
        body_transform = Matrix.Translation(pivot + Vector((0, 0, -drop))) @ Matrix.Rotation(-pitch, 4, 'Y') @ Matrix.Translation(-pivot)
        rig.pose.bones['pelvis'].matrix = body_transform @ rest['pelvis']
        # Parent matrices must be evaluated before setting child global matrices.
        # Otherwise a compressed pelvis gets applied twice to the foreleg roots.
        bpy.context.view_layer.update()
        if kind in ['Jump','Descend']:
            launch,tuck,reach=flight_phases(kind,t)
            bpy.context.view_layer.update()
            # Round the spine during gathering, then release toward the landing.
            # The two connected joints share the bend instead of moving a rigid torso.
            rotate_about_joint('body_1',-.09*tuck)
            rotate_about_joint('body_2',.11*tuck-.035*reach)
            # Keep the head attentive to the destination through the arc.
            rotate_about_joint('head',(.06*launch+.12*reach) if kind=='Jump' else .11*(tuck+reach))
        if sitting>0:
            bpy.context.view_layer.update()
            # Sitting raises the chest; keep the face level instead of staring up.
            head=rest['head'].copy()
            head.translation=(body_transform @ rest['head']).translation
            head.translation.z-=.012*sitting
            rig.pose.bones['head'].matrix=head
        for limb in ['front','back']:
            for side in ['left', 'right']:
                name=f'leg_{limb}_{side}_1'
                rig.pose.bones[name].matrix=body_transform @ rest[name]
                if limb=='front' and kind in ['Jump','Descend']:
                    chest=rig.pose.bones['body_2'].matrix @ rest['body_2'].inverted()
                    placed=chest @ rest[name]
                    # Match the accepted crouch's shoulder location at launch;
                    # release that compression over the push instead of jumping
                    # directly to the corrected airborne shoulder placement.
                    preceding='Crouch' if kind=='Jump' else 'CrouchDown'
                    start=Matrix.Translation(pivot+Vector((0,0,-.030))) @ Matrix.Rotation(.035,4,'Y') @ Matrix.Translation(-pivot)
                    shoulder_shift=Vector(kinematics[preceding][-1]['bones'][name]['head'])-(start @ rest[name]).translation
                    placed.translation+=shoulder_shift*(1-ease(0,.18,t))
                    rig.pose.bones[name].matrix=placed
                if limb=='front' and sitting>0:
                    # A sitting cat keeps its shoulders above the planted forelegs;
                    # only its haunches lower, rather than lifting the foreleg roots.
                    rig.pose.bones[name].matrix=rest[name]
                if limb=='back' and sitting>0:
                    rig.pose.bones[name].matrix=Matrix.Translation((.025*sitting,0,-.035*sitting)) @ rest[name]
        tail_pivot = rest['tail_1'].translation
        tail_y=.12*math.sin(math.pi*t) if kind in ['Jump','Descend'] else 0
        rig.pose.bones['tail_1'].matrix = Matrix.Translation(tail_pivot + Vector((0, 0, -drop))) @ Matrix.Rotation(1.2*sitting,4,'Z') @ Matrix.Rotation(tail_y,4,'Y') @ Matrix.Translation(-tail_pivot) @ rest['tail_1']
        bpy.context.view_layer.update()
        for limb, side, target, foot_rest in targets:
            p = foot_rest.copy()
            if limb=='back' and sitting>0:
                p.x += .035*sitting
                if kind in ['SitDown','Stand']: p.z += .018*math.sin(math.pi*t)
            if kind=='Jump':
                launch,tuck,reach=flight_phases(kind,t)
                if limb=='front':
                    p.x += .028*launch-.032*tuck+.058*reach
                    p.z += .050*launch+.100*tuck+.018*reach
                else:
                    # Extend behind the hips during the push, then gather the hocks.
                    p.x += -.045*launch+.052*tuck+.014*reach
                    p.z += -.010*launch+.092*tuck+.014*reach
            if kind=='Descend':
                launch,tuck,reach=flight_phases(kind,t)
                if limb=='front':
                    # Lift clear of the desktop lip before reaching down into space.
                    down=ease(.24,.40,t)*(1-ease(.75,1,t))
                    p.x += .024*launch-.018*tuck+.062*reach
                    p.z += .018*launch+.027*tuck-.024*down
                else:
                    p.x += .018*launch+.060*tuck+.010*reach
                    p.z += .012*launch+.087*tuck+.012*reach
            if kind == 'Touch' and limb == 'front' and side == 'left':
                pulse = .5 - .5 * math.cos(math.tau * t)
                p.x += .055 * pulse
                p.z += .065 * pulse
            target.location = rig.matrix_world @ p
            if limb=='back' and sitting>0: sitting_hind(side,p,sitting)
        bpy.context.view_layer.update()
        for limb, side, target, foot_rest in targets:
            ankle = rig.pose.bones[f'leg_{limb}_{side}_3']
            foot = rig.pose.bones[f'leg_{limb}_{side}_4']
            planted = rest[foot.name].copy()
            planted.translation = ankle.tail
            if kind in ['Jump','Descend']:
                launch,tuck,reach=flight_phases(kind,t)
                angle=(.16*launch-.35*tuck+.14*reach) if limb=='front' else (.28*launch-.24*tuck+.10*reach)
                pivot=planted.translation.copy()
                planted=Matrix.Translation(pivot) @ Matrix.Rotation(angle,4,'Y') @ Matrix.Translation(-pivot) @ planted
            foot.matrix = planted
        bpy.context.view_layer.update()
        evaluated = rig.evaluated_get(bpy.context.evaluated_depsgraph_get())
        motion={'phase':t,'drop':drop,'pitch':pitch,'bones':{},'foot_targets':{}}
        for b in evaluated.pose.bones:
            motion['bones'][b.name]={'head':list(b.head),'tail':list(b.tail),'length':b.length,'rest_length':b.bone.length}
        for limb,side,target,foot_rest in targets:
            motion['foot_targets'][limb+'_'+side]=list(rig.matrix_world.inverted() @ target.location)
        kinematics.setdefault(kind,[]).append(motion)
        if frame in [0,12,24] or (OUTPUT_NAME!='desktop_poses' and kind in ['Crouch','CrouchDown','Jump','Land','Descend']):
            body=bpy.data.objects['mesh_cat'].evaluated_get(bpy.context.evaluated_depsgraph_get())
            mesh=body.to_mesh()
            heights=[(body.matrix_world @ v.co).z for v in mesh.vertices]
            low_index=min(range(len(heights)),key=heights.__getitem__)
            low_vertex=mesh.vertices[low_index]
            anatomy.setdefault(kind,[]).append({'phase':t,'lowest_z':min(heights),'highest_z':max(heights),
                'lowest_position':list(body.matrix_world @ low_vertex.co),
                'rest_position':list(bpy.data.objects['mesh_cat'].data.vertices[low_index].co),
                'weights':{body.vertex_groups[g.group].name:g.weight for g in low_vertex.groups}})
            body.to_mesh_clear()
        sample = {}
        for b in evaluated.pose.bones:
            local = b.parent.matrix.inverted() @ b.matrix if b.parent else b.matrix
            rest_local = b.bone.parent.matrix_local.inverted() @ b.bone.matrix_local if b.parent else b.bone.matrix_local
            delta = rest_local.inverted() @ local
            p, q, s = delta.decompose()
            sample[b.name] = [[round(v, 8) for v in p], [round(q.x, 8), round(q.y, 8), round(q.z, 8), round(q.w, 8)]]
        samples.append(sample)
    poses[kind] = samples
out = ROOT / f'cats/{OUTPUT_NAME}.gd'
out.write_text('extends RefCounted\n# Generated by assets/models/blender/build_desktop_poses.py\nconst DURATIONS = '+json.dumps(DURATIONS,separators=(',',':'))+'\nconst DATA = ' + json.dumps(poses, separators=(',', ':')) + '\n', encoding='utf-8')
report={'output_name':OUTPUT_NAME,'source_blend_sha256':hashlib.sha256(Path(__file__).with_name('cat_reference.blend').read_bytes()).hexdigest(),
        'generator_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'output_sha256':hashlib.sha256(out.read_bytes()).hexdigest(),
        'durations':DURATIONS,'anatomy':anatomy,'kinematics':kinematics}
(ROOT/f'tests/results/{OUTPUT_NAME}-anatomy.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print('DESKTOP_POSES', out)
