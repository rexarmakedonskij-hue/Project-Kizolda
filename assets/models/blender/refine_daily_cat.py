"""Reproducible game derivative of Daily Lowpoly's CC BY 4.0 cat.

Run with Blender --background --python this_file. Keeps the source FBX intact.
"""
from pathlib import Path
import math
import random
import sys
import bpy
from mathutils import Vector, Matrix
from mathutils.kdtree import KDTree

ROOT = Path(__file__).resolve().parents[3]
REFERENCE_STYLE = '--reference-style' in sys.argv
FORM_PASS = '--form-pass-v1' in sys.argv
if FORM_PASS and not REFERENCE_STYLE:
    raise ValueError('The form pass requires --reference-style')
CONTINUOUS_TAIL = REFERENCE_STYLE and '--legacy-tail' not in sys.argv
REBUILT_CHEST = REFERENCE_STYLE and '--legacy-chest' not in sys.argv
MODEL_NAME = 'cat_reference' if REFERENCE_STYLE else 'cat_refined'
MODEL_NAME = next((a.split('=',1)[1] for a in sys.argv if a.startswith('--model-name=')), MODEL_NAME)
if not MODEL_NAME.replace('_','').replace('-','').isalnum():
    raise ValueError('Model name must be a plain asset identifier')
sys.path.insert(0, str(Path(__file__).resolve().parent))
OUT = ROOT / f'assets/models/glb/godot_mvp/{MODEL_NAME}.fbx'
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.fbx(filepath=str(ROOT / 'assets/third_party/daily_lowpoly_cat/cat_rigged.fbx'))
body = bpy.data.objects['mesh_cat']
rig = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')
rig.data.pose_position = 'REST'
bpy.context.view_layer.objects.active = body
bpy.ops.object.select_all(action='DESELECT')
body.select_set(True)
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.remove_doubles(threshold=.00001)
bpy.ops.object.mode_set(mode='OBJECT')
for name in ['sharp_edge','sharp_face','custom_normal']:
    attribute=body.data.attributes.get(name)
    if attribute: body.data.attributes.remove(attribute)
sub = body.modifiers.new('Rounded silhouette', 'SUBSURF')
sub.levels = 2
bpy.ops.object.modifier_move_up(modifier=sub.name)
bpy.ops.object.modifier_apply(modifier=sub.name)

def smooth(a, b, x):
    t = max(0., min(1., (x-a)/(b-a)))
    return t*t*(3-2*t)

def mix(a, b, t):
    return tuple(x*(1-t)+y*t for x,y in zip(a,b))

coat=(.55,.46,.37,1)
cream=(.83,.76,.64,1)
point=(.085,.059,.045,1)
white=(.92,.87,.77,1)
if REFERENCE_STYLE:
    coat=cream=(.010,.012,.016,1)
    point=(.006,.008,.011,1)
    white=coat
colors=body.data.color_attributes.new(name='Coat', type='FLOAT_COLOR', domain='POINT')
tail_segments=[]
tail_total=0.0
if REFERENCE_STYLE:
    for name in ['tail_1','tail_2','tail_3','tail_4','tail_4_end']:
        bone=rig.data.bones[name]
        a,b=bone.head_local.copy(),bone.tail_local.copy()
        length=(b-a).length
        tail_segments.append((name,a,b,tail_total,length))
        tail_total+=length
        if name not in body.vertex_groups: body.vertex_groups.new(name=name)
for v in body.data.vertices:
    x,y,z=v.co
    # Broader neck ruff and tail, with a continuous silhouette and shared skin weights.
    ruff=math.exp(-((x-.12)/.065)**2)*smooth(.07,.15,z)
    v.co.y *= 1 + (0 if REFERENCE_STYLE else .16)*ruff
    if REFERENCE_STYLE and x>.17 and z>.16:
        v.co.y *= 1.12
        if x>.22 and z<.26:
            v.co.x=.22+(x-.22)*.72
        # Replace the short source ears with a wider triangular silhouette.
        if z > .252 and abs(y) > .026:
            v.co.z = .252 + (z-.252)*.15
    if REFERENCE_STYLE:
        # The source has broad triangular lower legs. Shape their own skin
        # around the existing articulated chains before unioning the volumes.
        leg_groups={body.vertex_groups[g.group].name:g.weight for g in v.groups
                    if body.vertex_groups[g.group].name.startswith('leg_')}
        if leg_groups and .018<z<.180:
            owner=max(leg_groups,key=leg_groups.get)
            chain='_'.join(owner.split('_')[:3])
            limb=owner.split('_')[1]
            candidates=[]
            for segment in [1,2,3]:
                bone=rig.data.bones[f'{chain}_{segment}']
                a,b=bone.head_local,bone.tail_local
                axis=b-a
                t=max(0,min(1,(v.co-a).dot(axis)/axis.length_squared))
                point_on_axis=a+axis*t
                candidates.append(((v.co-point_on_axis).length,point_on_axis,t,segment))
            distance,point_on_axis,t,segment=min(candidates,key=lambda item:item[0])
            radii=[(.019,.012),(.012,.009),(.009,.011)] if limb=='front' else [(.031,.018),(.017,.012),(.012,.011)]
            r0,r1=radii[segment-1]
            radius=r0+(r1-r0)*t
            amount=smooth(.20,.85,sum(leg_groups.values()))*(1-smooth(.135,.180,z))*smooth(.018,.030,z)
            if distance>.0001:
                v.co=point_on_axis+(v.co-point_on_axis)*((distance+(radius-distance)*amount)/distance)
        tail_weight=sum(g.weight for g in v.groups if body.vertex_groups[g.group].name.startswith('tail_'))
        if tail_weight>0:
            closest=None
            for segment,(name,a,b,start,length) in enumerate(tail_segments):
                axis=b-a
                t=max(0,min(1,(v.co-a).dot(axis)/axis.length_squared))
                p=a+axis*t
                d=(v.co-p).length_squared
                if closest is None or d<closest[0]: closest=(d,p,start+t*length,segment)
            distance,nearest,arc,segment=closest
            radial=v.co-nearest
            # The source shares tail-root weights with its dorsal haunch.
            # Keep the tube independent: moving the tail must not lift a hip.
            keep=(1-smooth(.022,.035,radial.length)) if arc<.045 else 1.0
            if keep<1:
                inherited=[(body.vertex_groups[g.group].name,g.weight) for g in v.groups]
                removed=tail_weight*(1-keep)
                non_tail=sum(w for name,w in inherited if not name.startswith('tail_'))
                for name,weight in inherited:
                    if name.startswith('tail_'): weight*=keep
                    elif non_tail>.00001: weight+=removed*weight/non_tail
                    body.vertex_groups[name].add([v.index],weight,'REPLACE')
                if non_tail<=.00001: body.vertex_groups['pelvis'].add([v.index],removed,'REPLACE')
                tail_weight*=keep
            if tail_weight>.5:
                radius=.011-(.011-.0035)*smooth(0,tail_total,arc)
                if radial.length>.0001: v.co=nearest+radial.normalized()*radius
                # Blend across joints in arc space, avoiding a collar of vertices
                # following just one bone where the tail changes direction.
                blend={tail_segments[segment][0]:1.0}
                for joint in range(1,len(tail_segments)):
                    split=tail_segments[joint][3]
                    if abs(arc-split)<.013:
                        weight=smooth(split-.013,split+.013,arc)
                        blend={tail_segments[joint-1][0]:1-weight,tail_segments[joint][0]:weight}
                        break
                for group in body.vertex_groups:
                    if group.name.startswith('tail_'): group.remove([v.index])
                for name,weight in blend.items(): body.vertex_groups[name].add([v.index],weight*tail_weight,'REPLACE')
    if x < -.16 and not REFERENCE_STYLE:
        v.co.y *= 1.65
    c=mix(coat,cream,1-smooth(.10,.22,z))
    mask=smooth(.155,.22,x)*smooth(.13,.185,z)
    c=mix(c,point,mask)
    c=mix(c,point,1-smooth(-.18,-.13,x))
    bib=smooth(.055,.12,x)*(1-smooth(.15,.195,x))*(1-smooth(.14,.19,z))
    c=mix(c,white,bib)
    c=mix(c,white,1-smooth(.018,.048,z))
    colors.data[v.index].color=c
if REFERENCE_STYLE:
    from sculpt_cat_anatomy import sculpt_shoulders
    sculpt_shoulders(body,rig)
for p in body.data.polygons:
    p.use_smooth=True
body.data.normals_split_custom_set([(0.,0.,0.)] * len(body.data.loops))

def material(name, color, rough=.75):
    m=bpy.data.materials.new(name)
    m.diffuse_color=color
    m.use_nodes=True
    bs=m.node_tree.nodes.get('Principled BSDF')
    bs.inputs['Base Color'].default_value=color
    bs.inputs['Roughness'].default_value=rough
    return m

fur=material('Reference coat',coat)
vc=fur.node_tree.nodes.new('ShaderNodeVertexColor')
vc.layer_name='Coat'
fur.node_tree.links.new(vc.outputs['Color'],fur.node_tree.nodes.get('Principled BSDF').inputs['Base Color'])
body.data.materials.clear()
body.data.materials.append(fur)
parts=[body]
if CONTINUOUS_TAIL:
    from sculpt_cat_tail import replace_tail
    parts.append(replace_tail(body,rig,fur))

def ellipsoid(name, location, scale, color, rough=.7, direction=None, bone='head'):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=20, ring_count=12, location=location)
    obj=bpy.context.object
    obj.name=name
    obj.scale=scale
    if direction is not None:
        obj.rotation_mode='QUATERNION'
        obj.rotation_quaternion=Vector(direction).to_track_quat('X','Z')
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    obj.data.materials.append(material(name,color,rough))
    vg=obj.vertex_groups.new(name=bone)
    vg.add(list(range(len(obj.data.vertices))),1.,'REPLACE')
    for p in obj.data.polygons: p.use_smooth=True
    parts.append(obj)
    return obj

if REFERENCE_STYLE:
    # Broad cheek-to-cheek facial plane. A sphere behind the eye centres leaves
    # their outside edges unsupported and makes the face look like goggles.
    rings=[(.185,.218,.041,.034),(.220,.218,.067,.049),
           (.253,.218,.068,.047),(.270,.218,.061,.040)]
    verts=[]
    for x,z,width,height in rings:
        for i in range(16):
            angle=math.tau*i/16
            verts.append((x,width*math.cos(angle),z+height*math.sin(angle)))
    faces=[tuple(reversed(range(16))),tuple(range(48,64))]
    for ring in range(3):
        for i in range(16):
            a=ring*16+i; b=ring*16+(i+1)%16
            faces.append((a,b,b+16,a+16))
    mesh=bpy.data.meshes.new('Broad facial volume')
    mesh.from_pydata(verts,[],faces)
    forehead=bpy.data.objects.new('Broad facial volume',mesh)
    bpy.context.collection.objects.link(forehead)
    mesh.materials.append(fur)
    forehead.vertex_groups.new(name='head').add(list(range(len(verts))),1,'REPLACE')
    forehead['anatomical_core']=True
    parts.append(forehead)
    if FORM_PASS:
        from sculpt_cat_form import add_ears
        parts.extend(add_ears(body,rig,fur))
    else:
        for s in [-1,1]:
            outline=[(.245,s*.030,.247),(.235,s*.067,.250),(.226,s*.090,.298),(.237,s*.043,.275)]
            verts=outline+[(x-.015,y,z) for x,y,z in outline]
            mesh=bpy.data.meshes.new('Triangular ear')
            faces=[(0,1,2,3),(7,6,5,4),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)]
            mesh.from_pydata(verts,[],faces if s>0 else [tuple(reversed(f)) for f in faces])
            ear=bpy.data.objects.new('Triangular ear',mesh)
            bpy.context.collection.objects.link(ear)
            mesh.materials.append(material('Ear coat',coat))
            ear.vertex_groups.new(name='head').add(list(range(8)),1,'REPLACE')
            ear['anatomical_core']=True
            parts.append(ear)

for s in [-1,1]:
    normal=Vector((.985,s*.17,0) if REFERENCE_STYLE else (.75,s*.66,.10)).normalized()
    center=Vector((.272,s*.030,.225) if REFERENCE_STYLE else (.247,s*.035,.226))
    ellipsoid('Eye socket',center,(.0015,.017,.0185) if REFERENCE_STYLE else (.006,.013,.014),point,direction=normal)
    ellipsoid('Green iris' if REFERENCE_STYLE else 'Blue iris',center+normal*.003,
        (.0015,.014,.0155) if REFERENCE_STYLE else (.004,.009,.010),
        (.025,.65,.005,1) if REFERENCE_STYLE else (.22,.55,.69,1),.23,normal)
    pupil_center=center+normal*(.0048 if REFERENCE_STYLE else .006)
    if REFERENCE_STYLE: pupil_center.y-=s*.0025
    if REFERENCE_STYLE: pupil_center.y-=s*.002
    ellipsoid('Pupil',pupil_center,(.0008,.0140,.0160) if REFERENCE_STYLE else (.0015,.0035,.007),(.005,.008,.01,1),.2,normal)
    ellipsoid('Eye glint',center+normal*.008+Vector((0,-s*.004,.006) if REFERENCE_STYLE else (0,-.002,.003)),(.0012,.0018,.0018) if REFERENCE_STYLE else (.0012,.0014,.0014),(1,1,1,1),.15)
    if not REFERENCE_STYLE:
        ellipsoid('Muzzle',(.268,s*.012,.197),(.016,.017,.012),white)
    else:
        ellipsoid('Brow mark',(.271,s*.016,.249),(.0013,.003,.005),(.035,.039,.047,1))
    # Three light tapered whiskers per cheek, skinned to the head.
    for j in range(3):
        a=Vector((.275 if REFERENCE_STYLE else .272,s*.023,.199+j*.002))
        b=Vector((.283,s*(.090+j*.004),.185+j*.010) if REFERENCE_STYLE else (.254,s*(.075+j*.005),.194+j*.007))
        bpy.ops.mesh.primitive_cone_add(vertices=6, radius1=.00065,radius2=.00015,depth=(b-a).length,location=(a+b)/2)
        obj=bpy.context.object
        obj.name='Whisker'
        obj.rotation_mode='QUATERNION'
        obj.rotation_quaternion=(b-a).to_track_quat('Z','Y')
        obj.data.materials.append(material('Whisker cream',(.34,.37,.43,1) if REFERENCE_STYLE else white))
        obj.vertex_groups.new(name='head').add(list(range(len(obj.data.vertices))),1.,'REPLACE')
        parts.append(obj)
if REFERENCE_STYLE:
    mesh=bpy.data.meshes.new('Triangular nose')
    outline=[(-.011,.205),(-.006,.208),(.006,.208),(.011,.205),(.003,.202),(0,.198),(-.003,.202)]
    vertices=[(.281,y,z) for y,z in outline]+[(.276,y,z) for y,z in outline]
    faces=[tuple(reversed(range(7))),tuple(range(7,14))]
    for i in range(7):
        j=(i+1)%7
        faces.append((i,j,j+7,i+7))
    mesh.from_pydata(vertices,[],faces)
    nose=bpy.data.objects.new('Nose',mesh)
    bpy.context.collection.objects.link(nose)
    mesh.materials.append(material('Muted pink nose',(.16,.035,.08,1)))
    nose.vertex_groups.new(name='head').add(list(range(len(vertices))),1,'REPLACE')
    parts.append(nose)
    # A fine closed mouth, rather than two separate moustache-like bulges.
    for path in [[(.275,0,.198),(.275,0,.191)],
                 [(.275,0,.191),(.275,-.004,.189),(.274,-.010,.191)],
                 [(.275,0,.191),(.275,.004,.189),(.274,.010,.191)]]:
        curve=bpy.data.curves.new('Closed mouth','CURVE')
        curve.dimensions='3D'
        curve.bevel_depth=.00065
        curve.bevel_resolution=2
        spline=curve.splines.new('BEZIER')
        spline.bezier_points.add(len(path)-1)
        for p,co in zip(spline.bezier_points,path):
            p.co=co
            p.handle_left_type=p.handle_right_type='AUTO'
        obj=bpy.data.objects.new('Closed mouth',curve)
        bpy.context.collection.objects.link(obj)
        bpy.context.view_layer.objects.active=obj
        bpy.ops.object.select_all(action='DESELECT')
        obj.select_set(True)
        bpy.ops.object.convert(target='MESH')
        obj=bpy.context.object
        obj.data.materials.append(material('Mouth line',(.055,.030,.044,1)))
        obj.vertex_groups.new(name='head').add(list(range(len(obj.data.vertices))),1,'REPLACE')
        parts.append(obj)
else:
    ellipsoid('Nose',(.283,0,.205),(.006,.008,.0045),(.095,.054,.052,1),.45)
if not REFERENCE_STYLE:
    ellipsoid('Chin',(.263,0,.185),(.012,.016,.006),white)
if REFERENCE_STYLE:
    if FORM_PASS:
        from sculpt_cat_form import add_inner_ears
        parts.extend(add_inner_ears(body,rig,material('Muted violet inner ear',(.12,.045,.09,1))))
    else:
        for s in [-1,1]:
            mesh=bpy.data.meshes.new('Inner ear')
            mesh.from_pydata([(.243,s*.044,.258),(.235,s*.064,.261),(.229,s*.081,.286)],[],[(0,1,2)] if s>0 else [(2,1,0)])
            obj=bpy.data.objects.new('Inner ear',mesh)
            bpy.context.collection.objects.link(obj)
            mesh.materials.append(material('Muted violet inner ear',(.12,.045,.09,1)))
            obj.vertex_groups.new(name='head').add([0,1,2],1,'REPLACE')
            parts.append(obj)

# Four separately weighted paws: broad metacarpal/metatarsal pads and four toes.
for limb in ['front','back']:
    for side in ['left','right']:
        # Rounded upper/lower limbs follow the actual shoulder/elbow/wrist
        # and hip/knee/hock chains, rather than tapering into flat triangles.
        for segment in [1,2,3]:
            name=f'leg_{limb}_{side}_{segment}'
            joint=rig.data.bones[name]
            a,b=joint.head_local.copy(),joint.tail_local.copy()
            width=([.022,.014,.010] if limb=='front' else [.030,.017,.012])[segment-1]
            if REFERENCE_STYLE: width=([.018,.010,.009] if limb=='front' else [.022,.012,.010])[segment-1]
            if FORM_PASS: width=([.018,.011,.010] if limb=='front' else [.023,.015,.011])[segment-1]
            if REBUILT_CHEST and limb=='front' and segment==1:
                width=.014
            extension=width*(.78 if FORM_PASS else .5)
            leg=ellipsoid(name+'_volume',(a+b)/2,((b-a).length/2+extension,width,width),
                cream if segment==3 else coat,direction=b-a,bone=name)
            # Soften skinning near the parent joint; retain a single connected rig.
            parent=joint.parent
            if parent:
                group=leg.vertex_groups.new(name=parent.name)
                own=leg.vertex_groups.get(name)
                for v in leg.data.vertices:
                    world=leg.matrix_world @ v.co
                    t=max(0.,min(1.,(world-a).dot(b-a)/(b-a).length_squared))
                    w=.35*(1-smooth(0,.35,t))
                    group.add([v.index],w,'REPLACE')
                    own.add([v.index],1-w,'REPLACE')
        bone=f'leg_{limb}_{side}_4'
        b=rig.data.bones[bone]
        center=(b.head_local+b.tail_local)*.5
        center.z=.011
        ellipsoid(f'{limb}_{side}_paw',center,(.019,.014,.009) if REFERENCE_STYLE else (.019,.016,.010),white,bone=bone)
        for toe in range(4):
            pos=center+Vector((.011,(toe-1.5)*.0055,-.001) if REFERENCE_STYLE else (.014,(toe-1.5)*.0075,-.001))
            ellipsoid(f'{limb}_{side}_toe_{toe}',pos,(.006,.0038,.006) if REFERENCE_STYLE else (.009,.0048,.0075),white,bone=bone)
        ellipsoid(f'{limb}_{side}_pad',center+Vector((0,0,-.008)),(.010,.010,.0025),(.22,.12,.12,1),bone=bone)

if REBUILT_CHEST:
    from rebuild_cat_chest import rebuild_chest
    rebuild_chest(body,rig,fur)
if FORM_PASS:
    from sculpt_cat_form import add_jaw_bridge
    parts.append(add_jaw_bridge(body,rig,fur))

# Fuse the limb volumes into continuous skin. Retain the facial details as
# separate islands so the eyes and fine whiskers keep their crisp silhouette.
core=[o for o in parts if o==body or o.get('anatomical_core',False) or any(k in o.name for k in ['_volume','_paw','_toe_','_pad'])]
details=[o for o in parts if o not in core]
bpy.ops.object.select_all(action='DESELECT')
for obj in core:
    obj.select_set(True)
    if obj!=body:
        attr=obj.data.color_attributes.new(name='Coat',type='FLOAT_COLOR',domain='POINT')
        for datum in attr.data: datum.color=obj.data.materials[0].diffuse_color
bpy.context.view_layer.objects.active=body
bpy.ops.object.join()
source_positions=[v.co.copy() for v in body.data.vertices]
source_weights=[[(g.group,g.weight) for g in v.groups] for v in body.data.vertices]
source_colors=[tuple(c.color) for c in body.data.color_attributes['Coat'].data]
group_names=[g.name for g in body.vertex_groups]
tree=KDTree(len(source_positions))
for i,pos in enumerate(source_positions): tree.insert(pos,i)
tree.balance()
body.modifiers.clear()
remesh=body.modifiers.new('Continuous anatomical skin','REMESH')
remesh.mode='VOXEL'
remesh.voxel_size=.0025
remesh.use_smooth_shade=True
bpy.ops.object.modifier_apply(modifier=remesh.name)
relax=body.modifiers.new('Relax joints','SMOOTH')
relax.factor=.7
relax.iterations=12
bpy.ops.object.modifier_apply(modifier=relax.name)
decimate=body.modifiers.new('Game surface budget','DECIMATE')
decimate.ratio=.55
bpy.ops.object.modifier_apply(modifier=decimate.name)
body.vertex_groups.clear()
for name in group_names: body.vertex_groups.new(name=name)
old=body.data.color_attributes.get('Coat')
if old: body.data.color_attributes.remove(old)
attr=body.data.color_attributes.new(name='Coat',type='FLOAT_COLOR',domain='POINT')
pad_centers=[(b.head_local+b.tail_local)*.5 for b in rig.data.bones if b.name.startswith('leg_') and b.name.endswith('_4')]
for v in body.data.vertices:
    samples=tree.find_n(v.co,4)
    factors=[1/max(d,.00001)**2 for _,_,d in samples]
    total=sum(factors)
    weights={}
    color=[0.,0.,0.,0.]
    for (_,i,_),f in zip(samples,factors):
        f/=total
        for g,w in source_weights[i]: weights[g]=weights.get(g,0)+w*f
        for channel in range(4): color[channel]+=source_colors[i][channel]*f
    selected=sorted(weights.items(),key=lambda x:x[1],reverse=True)[:4]
    total_weight=sum(w for _,w in selected)
    for g,w in selected: body.vertex_groups[g].add([v.index],w/total_weight,'REPLACE')
    x,y,z=v.co
    c=mix(coat,cream,smooth(.12,.23,z)*.35)
    c=mix(c,point,smooth(.155,.22,x)*smooth(.13,.185,z))
    c=mix(c,point,1-smooth(-.18,-.13,x))
    bib=smooth(.045,.12,x)*(1-smooth(.155,.20,x))*(1-smooth(.155,.205,z))
    c=mix(c,white,bib)
    c=mix(c,white,1-smooth(.025,.075,z))
    if z<.006:
        for pad in pad_centers:
            radius=((x-pad.x)/.010)**2+((y-pad.y)/.010)**2
            if radius<1: c=mix((.24,.12,.13,1),c,smooth(.65,1,radius))
    attr.data[v.index].color=c
body.data.materials.clear()
body.data.materials.append(fur)
if CONTINUOUS_TAIL:
    from sculpt_cat_tail import reskin_tail
    reskin_tail(body,rig)
if REBUILT_CHEST:
    from rebuild_cat_chest import reskin_chest
    reskin_chest(body,rig)
if FORM_PASS:
    from sculpt_cat_form import reskin_leg_joints
    reskin_leg_joints(body,rig)
for poly in body.data.polygons: poly.material_index=0
armature=body.modifiers.new('Armature','ARMATURE')
armature.object=rig
# Short tapered coat fibres soften the outline without a particle system or
# millions of strands. They carry the same skin weights as their root.
rng=random.Random(20260922)
vertices=[]
faces=[]
fibre_colors=[]
fibre_weights=[]
candidates=[v for v in body.data.vertices if v.co.z>.095 and v.co.x<.205]
for root_vertex in rng.sample(candidates,min(0 if REFERENCE_STYLE else 900,len(candidates))):
    p=root_vertex.co.copy()
    n=root_vertex.normal.normalized()
    direction=(n*.8+Vector((-.2,0,-.25))).normalized()
    length=rng.uniform(.0015,.003) * (1.3 if p.x>.06 else 1.)
    width=rng.uniform(.00012,.00022)
    tangent=n.cross(Vector((0,0,1)))
    if tangent.length<.01: tangent=n.cross(Vector((0,1,0)))
    tangent.normalize()
    bitangent=n.cross(tangent).normalized()
    base=len(vertices)
    for ring in range(4):
        t=ring/3
        center=p+direction*(length*t)+n*(length*.15*math.sin(math.pi*t))
        radius=width*(1-t)+.00003
        for side in range(3):
            angle=math.tau*side/3
            vertices.append(center+radius*(tangent*math.cos(angle)+bitangent*math.sin(angle)))
            fibre_colors.append(tuple(attr.data[root_vertex.index].color))
            fibre_weights.append([(g.group,g.weight) for g in root_vertex.groups])
    for ring in range(3):
        for side in range(3):
            a=base+ring*3+side
            b=base+ring*3+(side+1)%3
            faces.append((a,b,b+3,a+3))
fibres_mesh=bpy.data.meshes.new('Short coat fibres')
fibres_mesh.from_pydata(vertices,[],faces)
fibres_mesh.materials.append(fur)
fibres=bpy.data.objects.new('Coat fibres',fibres_mesh)
bpy.context.collection.objects.link(fibres)
for group in body.vertex_groups: fibres.vertex_groups.new(name=group.name)
fibre_attr=fibres_mesh.color_attributes.new(name='Coat',type='FLOAT_COLOR',domain='POINT')
for i,weights in enumerate(fibre_weights):
    for group,weight in weights: fibres.vertex_groups[group].add([i],weight,'REPLACE')
    fibre_attr.data[i].color=fibre_colors[i]
parts=[body,fibres]+details
bpy.ops.object.select_all(action='DESELECT')
for obj in parts: obj.select_set(True)
bpy.context.view_layer.objects.active=body
bpy.ops.object.join()
for edge in body.data.edges: edge.use_edge_sharp=False
for poly in body.data.polygons: poly.use_smooth=True
custom=body.data.attributes.get('custom_normal')
if custom: body.data.attributes.remove(custom)
# Export vertex colors for every surface, including the facial details.
attr=body.data.color_attributes.get('Coat')
for poly in body.data.polygons:
    if poly.material_index:
        color=body.data.materials[poly.material_index].diffuse_color
        for vi in poly.vertices: attr.data[vi].color=color
if REFERENCE_STYLE:
    basis=body.shape_key_add(name='Basis')
    blink=body.shape_key_add(name='Blink',from_mix=False)
    blink.value=0
    eye_vertices=set()
    gaze_vertices=set()
    for polygon in body.data.polygons:
        name=body.data.materials[polygon.material_index].name
        if name.startswith(('Eye socket','Green iris','Pupil','Eye glint')):
            eye_vertices.update(polygon.vertices)
        if name.startswith(('Green iris','Pupil','Eye glint')):
            gaze_vertices.update(polygon.vertices)
    for vi in eye_vertices:
        blink.data[vi].co.z=.225+(blink.data[vi].co.z-.225)*.06
    hide=body.shape_key_add(name='HideIris',from_mix=False)
    hide.value=0
    for vi in range(len(body.data.vertices)): hide.data[vi].co=basis.data[vi].co
    for vi in gaze_vertices: hide.data[vi].co.x-=.014
    # The complete coloured disc moves within its stationary dark socket.
    # Horizontal gaze also composes with closed lids without a floating glint.
    for name,offset in [('LookLeft',.0025),('LookRight',-.0025)]:
        key=body.shape_key_add(name=name,from_mix=False)
        key.value=0
        # Blender may initialise from the active key; never inherit Blink.
        for vi in range(len(body.data.vertices)): key.data[vi].co=basis.data[vi].co
        for vi in gaze_vertices: key.data[vi].co.y+=offset
bpy.ops.object.select_all(action='DESELECT')
body.select_set(True)
rig.select_set(True)
rig.data.pose_position='POSE'
bpy.context.scene.frame_start=1
bpy.context.scene.frame_end=37
bpy.context.scene.render.fps=30

# Bake a grounded four-beat walk. IK targets keep each supporting paw on the
# floor during stance; the toe bones remain free for a gentle toe-off.
rig.animation_data_clear()
for bone in rig.pose.bones: bone.matrix_basis=Matrix.Identity(4)
bpy.context.view_layer.update()
for action in list(bpy.data.actions): bpy.data.actions.remove(action)
targets=[]
for limb,side,phase in [('front','left',0),('back','right',.25),('front','right',.5),('back','left',.75)]:
    bone=rig.pose.bones[f'leg_{limb}_{side}_3']
    target=bpy.data.objects.new('Gait target',None)
    bpy.context.collection.objects.link(target)
    target.location=rig.matrix_world @ bone.tail
    rest=target.location.copy()
    ik=bone.constraints.new('IK')
    ik.target=target
    ik.chain_count=3
    ik.use_stretch=False
    targets.append((target,rest,phase,ik,bone))
baked=[]
for frame in range(37):
    bpy.context.scene.frame_set(frame+1)
    if REFERENCE_STYLE:
        phase=math.tau*frame/36
        pelvis=rig.pose.bones['pelvis']
        # Lower the shoulder/hip line in global rig space. With a straight
        # source shoulder the last third of stance exceeded the foreleg reach,
        # so IK dragged the supposedly planted paw forward.
        shift=Vector((.0015*math.sin(phase),.001*math.cos(phase),-.026+.002*(1-math.cos(phase*2))))
        # Assign the complete matrix: mutating matrix.translation on the RNA
        # getter does not write the changed matrix back to the pose bone.
        pelvis.matrix=Matrix.Translation(shift) @ pelvis.bone.matrix_local
        bpy.context.view_layer.update()
        # Hind-leg and tail roots are separate root bones in the source rig.
        # They do not inherit the pelvis movement through the spine.
        for limb in ['front','back']:
            for side in ['left','right']:
                root=rig.pose.bones[f'leg_{limb}_{side}_1']
                root.matrix=Matrix.Translation(shift) @ root.bone.matrix_local
        tail_root=rig.pose.bones['tail_1']
        tail_root.matrix=Matrix.Translation(shift) @ tail_root.bone.matrix_local
        for i in range(1,5):
            tail=rig.pose.bones.get(f'tail_{i}')
            if tail:
                tail.rotation_mode='XYZ'
                tail.rotation_euler=(0,.12 if i==1 else .06,.07*math.sin(phase-i*.35))
    for target,rest,phase,ik,bone in targets:
        t=(frame/36+phase)%1
        if t < .65:
            x=.07-.14*t/.65
            z=0
        else:
            u=(t-.65)/.35
            x=-.07+.14*(u*u*(3-2*u))
            z=.035*math.sin(math.pi*u)**2
        target.location=rest+Vector((x,0,z))
    bpy.context.view_layer.update()
    for limb in ['front','back']:
        for side in ['left','right']:
            ankle=rig.pose.bones[f'leg_{limb}_{side}_3']
            foot=rig.pose.bones[f'leg_{limb}_{side}_4']
            planted=foot.bone.matrix_local.copy()
            planted.translation=ankle.tail
            foot.matrix=planted
    bpy.context.view_layer.update()
    evaluated=rig.evaluated_get(bpy.context.evaluated_depsgraph_get())
    baked.append({b.name:b.matrix.copy() for b in evaluated.pose.bones})
for target,rest,phase,ik,bone in targets:
    bone.constraints.remove(ik)
    bpy.data.objects.remove(target,do_unlink=True)
for bone in rig.pose.bones:
    bone.matrix_basis=Matrix.Identity(4)
    bone.keyframe_insert('location',frame=0)
    bone.keyframe_insert('rotation_quaternion',frame=0)
    bone.keyframe_insert('scale',frame=0)
for frame,poses in enumerate(baked,1):
    bpy.context.scene.frame_set(frame)
    for bone in rig.pose.bones:
        bone.matrix=poses[bone.name]
        bpy.context.view_layer.update()
        bone.rotation_mode='QUATERNION'
        bone.keyframe_insert('location',frame=frame)
        bone.keyframe_insert('rotation_quaternion',frame=frame)
        bone.keyframe_insert('scale',frame=frame)
rig.animation_data.action.name='Walk'
bpy.context.scene.frame_set(0)
OUT.parent.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(Path(__file__).with_name(f'{MODEL_NAME}.blend')))
bpy.ops.export_scene.fbx(filepath=str(OUT),use_selection=True,add_leaf_bones=False,bake_anim=True,
    bake_anim_use_all_actions=False,bake_anim_use_nla_strips=False,mesh_smooth_type='FACE',
    path_mode='AUTO',use_mesh_modifiers=True)
body.data.calc_loop_triangles()
print('REFINED_CAT',len(body.data.loop_triangles),'triangles',len(rig.data.bones),'bones',OUT)
