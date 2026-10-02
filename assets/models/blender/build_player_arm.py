"""Create a visible forearm and hand; hidden arm bones retain reach control."""
from pathlib import Path
import math
import re
import sys
import bpy
from mathutils import Vector
from mathutils.kdtree import KDTree

ROOT = Path(__file__).resolve().parents[3]
MODEL_NAME = 'player_arm'
ANATOMY_V9 = '--anatomy-v9' in sys.argv
for argument in sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []:
    if argument.startswith('--model-name='):
        MODEL_NAME = argument.split('=',1)[1]
if not re.fullmatch(r'[a-z][a-z0-9_]*', MODEL_NAME):
    raise ValueError('Model name must contain lowercase letters, digits and underscores.')
UPPER_LENGTH = .30
FOREARM_LENGTH = .34
WRIST_Z = UPPER_LENGTH + FOREARM_LENGTH
HAND_SIZE = .68 if ANATOMY_V9 else .76
HAND_WIDTH = .82 if ANATOMY_V9 else 1.0
PALM_THICKNESS = .65 if ANATOMY_V9 else 1.0
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)

def material(name, color):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (*color, 1)
    bsdf.inputs['Roughness'].default_value = .78
    return m

skin = material('Warm skin', (.67, .40, .25))
sleeve = material('Teal cotton', (.08, .25, .25))
cuff = material('Ribbed cuff', (.055, .17, .17))
nail = material('Soft nails', (.76, .51, .39))
rig_data = bpy.data.armatures.new('Right arm skeleton')
rig = bpy.data.objects.new('RightArm', rig_data)
bpy.context.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig
rig.select_set(True)
bpy.ops.object.mode_set(mode='EDIT')

def xyz(p):
    # Godot x,y,z -> Blender x,-z,y.
    # Compact arm for the closer seated position; preserve the hand dimensions.
    z = p[2]
    hand_mix=max(0,min(1,(z-1.20)/.06))
    hand_mix=hand_mix*hand_mix*(3-2*hand_mix)
    width_scale=1+(HAND_SIZE-1)*hand_mix
    if z >= 1.26: z = WRIST_Z + (z - 1.26)*HAND_SIZE
    elif z >= .58: z = UPPER_LENGTH + (z-.58)*(FOREARM_LENGTH/.68)
    else: z *= UPPER_LENGTH/.58
    width_aspect=1+(HAND_WIDTH-1)*hand_mix
    depth_aspect=1+(PALM_THICKNESS-1)*hand_mix
    return Vector((-p[0]*width_scale*width_aspect, -z, p[1]*width_scale*depth_aspect))

def bone(name, a, b, parent=None):
    bb = rig_data.edit_bones.new(name)
    bb.head, bb.tail = xyz(a), xyz(b)
    if parent: bb.parent = rig_data.edit_bones[parent]
    return bb

bone('upper_arm', (0,0,0), (0,0,.58))
bone('forearm', (0,0,.58), (0,0,1.26), 'upper_arm')
bone('elbow_helper', (0,0,.58), (0,0,.64), 'upper_arm')
bone('palm', (0,0,1.26), (0,0,1.42), 'forearm')
finger_points = {}
for i, (x, start, length) in enumerate([(-.058,1.395,.105),(-.021,1.415,.13),(.019,1.413,.12),(.055,1.392,.095)]):
    pts = [(x, -.003, start), (x,-.008,start+length*.44), (x,-.019,start+length*.77), (x,-.03,start+length)]
    finger_points[i] = pts
    for j in range(3): bone(f'finger_{i}_{j}', pts[j], pts[j+1], 'palm' if j==0 else f'finger_{i}_{j-1}')
thumb = [(-.061,0,1.30),(-.094,-.004,1.335),(-.12,-.014,1.38),(-.128,-.026,1.41)]
for j in range(3): bone(f'thumb_{j}',thumb[j],thumb[j+1],'palm' if j==0 else f'thumb_{j-1}')
bpy.ops.object.mode_set(mode='OBJECT')
rig.select_set(False)

def bind(obj, name, mat):
    obj.data.materials.append(mat)
    group = obj.vertex_groups.new(name=name)
    group.add(list(range(len(obj.data.vertices))), 1, 'REPLACE')
    mod = obj.modifiers.new('Arm deform', 'ARMATURE')
    mod.object = rig
    obj.parent = rig
    for face in obj.data.polygons: face.use_smooth = True

def ellipsoid(name, center, scale, owner, mat):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=10, location=xyz(center))
    obj=bpy.context.object
    obj.name=name
    hand_scale=HAND_SIZE if center[2]>=1.26 else 1
    obj.scale=(scale[0]*hand_scale*(HAND_WIDTH if center[2]>=1.26 else 1),scale[2]*hand_scale,scale[1]*hand_scale*(PALM_THICKNESS if center[2]>=1.26 else 1))
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    bind(obj,owner,mat)
    return obj

def tube(name, points, owner, mat):
    verts=[]
    faces=[]
    for z, rx, ry in points:
        for k in range(16):
            a=math.tau*k/16
            verts.append(xyz((math.cos(a)*rx, math.sin(a)*ry, z)))
    for j in range(len(points)-1):
        for k in range(16):
            a=j*16+k; b=j*16+(k+1)%16
            faces.append((a,b,b+16,a+16))
    faces.append(tuple(reversed(range(16))))
    faces.append(tuple((len(points)-1)*16+k for k in range(16)))
    mesh=bpy.data.meshes.new(name)
    mesh.from_pydata(verts,[],faces)
    obj=bpy.data.objects.new(name,mesh)
    bpy.context.collection.objects.link(obj)
    bind(obj,owner,mat)

# No visible shoulder, upper arm or elbow bulge in the first-person model.
tube('Forearm sleeve',[(.58,.049,.047),(.74,.048,.044),(1.08,.042,.038),(1.14,.042,.037)],'forearm',sleeve)
tube('Cuff',[(1.08,.044,.04),(1.15,.044,.04)],'forearm',cuff)
tube('Wrist',[(1.13,.028,.020),(1.20,.030,.020),(1.28,.036,.024)],'forearm',skin)
if ANATOMY_V9:
    # One taper from the wrist heel to the knuckles. The broad, shallow palm
    # has human hand proportions instead of overlapping spherical bulges.
    tube('Palm',[(1.248,.032,.020),(1.277,.043,.027),(1.315,.065,.030),
                 (1.350,.071,.029),(1.384,.068,.026),(1.413,.060,.019)],'palm',skin)
else:
    ellipsoid('Palm',(0,0,1.337),(.078,.032,.092),'palm',skin)
    ellipsoid('Metacarpal arch',(0,-.002,1.380),(.071,.028,.048),'palm',skin)
ellipsoid('Wrist joint',(0,0,1.26),(.033,.022,.04),'palm',skin)
ellipsoid('Thumb base',(-.047,-.003,1.316),(.037,.031,.049),'palm',skin)
def smoothstep(a,b,value):
    t=max(0,min(1,(value-a)/(b-a)))
    return t*t*(3-2*t)

def digit_surface(index, points):
    """A softly tapered finger, rather than three bead-shaped phalanges."""
    centers = [xyz(p) for p in points]
    segments = [(b-a).length for a,b in zip(centers,centers[1:])]
    cumulative = [0]
    for length in segments: cumulative.append(cumulative[-1]+length)
    length = cumulative[-1]
    base_radius = (.016 if index!='thumb' else .020)*HAND_SIZE
    names = [f'finger_{index}_{j}' if index!='thumb' else f'thumb_{j}' for j in range(3)]
    verts, faces, vertex_weights = [], [], []
    rings = []
    for step in range(25):
        arc = length*step/24
        j = min(2,next((j for j in range(3) if arc<=cumulative[j+1]),2))
        t = (arc-cumulative[j])/segments[j]
        a,b = centers[j],centers[j+1]
        previous = centers[max(0,j-1)]
        following = centers[min(3,j+2)]
        tangent_a = (b-previous)*(.5 if j else 1)
        tangent_b = (following-a)*(.5 if j<2 else 1)
        center = (2*t**3-3*t*t+1)*a+(t**3-2*t*t+t)*tangent_a+(-2*t**3+3*t*t)*b+(t**3-t*t)*tangent_b
        tangent = ((6*t*t-6*t)*a+(3*t*t-4*t+1)*tangent_a+(-6*t*t+6*t)*b+(3*t*t-2*t)*tangent_b).normalized()
        # Broad first knuckle, then a gradual taper without narrow waist rings.
        radius = base_radius*(1-.24*smoothstep(0,length,arc))
        influence = {names[j]:1}
        for joint in (1,2):
            half_width=.010*HAND_SIZE
            if abs(arc-cumulative[joint]) < half_width:
                blend=smoothstep(cumulative[joint]-half_width,cumulative[joint]+half_width,arc)
                influence={names[joint-1]:1-blend,names[joint]:blend}
        rings.append((center,tangent,radius,influence))
    last_center,last_tangent,last_radius,_ = rings[-1]
    for cap in range(1,5):
        angle=math.pi/2*cap/5
        rings.append((last_center+last_tangent*last_radius*math.sin(angle),last_tangent,last_radius*math.cos(angle),{names[2]:1}))
    for center,tangent,radius,influence in rings:
        axis=tangent.cross(Vector((0,0,1))).normalized()
        across=tangent.cross(axis).normalized()
        for k in range(16):
            angle=math.tau*k/16
            verts.append(center+(axis*math.cos(angle)+across*math.sin(angle))*radius)
            vertex_weights.append(influence)
    for j in range(len(rings)-1):
        for k in range(16):
            a=j*16+k; b=j*16+(k+1)%16
            faces.append((a,b,b+16,a+16))
    faces.append(tuple(reversed(range(16))))
    verts.append(last_center+last_tangent*last_radius)
    vertex_weights.append({names[2]:1})
    tip=len(verts)-1
    for k in range(16):
        faces.append(((len(rings)-1)*16+k,(len(rings)-1)*16+(k+1)%16,tip))
    mesh=bpy.data.meshes.new(f'Digit {index}')
    mesh.from_pydata(verts,[],faces)
    obj=bpy.data.objects.new(f'Digit {index}',mesh)
    bpy.context.collection.objects.link(obj)
    bind(obj,names[0],skin)
    obj.vertex_groups.clear()
    for name in names: obj.vertex_groups.new(name=name)
    for i,influence in enumerate(vertex_weights):
        for name,weight in influence.items():
            if weight>0: obj.vertex_groups[name].add([i],weight,'REPLACE')

for index, points in list(finger_points.items())+[('thumb',thumb)]:
    digit_surface(index, points)

def continuous_surface(name, parts, voxel, mat):
    """Union overlapping sculpt volumes and preserve a blended anatomical skin."""
    bpy.ops.object.select_all(action='DESELECT')
    for obj in parts: obj.select_set(True)
    bpy.context.view_layer.objects.active=parts[0]
    bpy.ops.object.join()
    obj=bpy.context.object
    obj.name=name
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    positions=[v.co.copy() for v in obj.data.vertices]
    names=[group.name for group in obj.vertex_groups]
    weights=[[(names[g.group],g.weight) for g in v.groups] for v in obj.data.vertices]
    tree=KDTree(len(positions))
    for i,p in enumerate(positions): tree.insert(p,i)
    tree.balance()
    obj.modifiers.clear()
    remesh=obj.modifiers.new('Continuous sculpt surface','REMESH')
    remesh.mode='VOXEL'
    remesh.voxel_size=voxel
    remesh.use_smooth_shade=True
    bpy.ops.object.modifier_apply(modifier=remesh.name)
    relax=obj.modifiers.new('Relax knuckles and joints','SMOOTH')
    relax.factor=.55
    relax.iterations=5
    bpy.ops.object.modifier_apply(modifier=relax.name)
    decimate=obj.modifiers.new('Game silhouette budget','DECIMATE')
    decimate.ratio=.62
    bpy.ops.object.modifier_apply(modifier=decimate.name)
    obj.vertex_groups.clear()
    for bone_name in names: obj.vertex_groups.new(name=bone_name)
    thumb_centers=[xyz(p) for p in thumb]
    thumb_lengths=[(b-a).length for a,b in zip(thumb_centers,thumb_centers[1:])]
    thumb_arcs=[0]
    for length in thumb_lengths: thumb_arcs.append(thumb_arcs[-1]+length)
    for v in obj.data.vertices:
        samples=tree.find_n(v.co,8)
        blend={}
        for _,i,d in samples:
            factor=1/max(d,.0001)**2
            for bone_name,w in weights[i]: blend[bone_name]=blend.get(bone_name,0)+w*factor
        z=-v.co.y
        if name=='Sleeve':
            blend={'forearm':1}
        elif z < WRIST_Z+.075:
            t=smoothstep(WRIST_Z-.07,WRIST_Z+.04,z)
            # Use one continuous wrist field; the thumb web is assigned below.
            blend={'forearm':1-t,'palm':t}
        if name=='HandSkin':
            # The voxel union joins the thumb web to the palm. Nearest source
            # samples switch between their overlapping surfaces; assign a
            # continuous lateral web field instead of inheriting that switch.
            profile_z=WRIST_Z+(z-WRIST_Z)*.76/HAND_SIZE
            width_ratio=HAND_SIZE*HAND_WIDTH/.76
            web_boundary=min(.072,.035+.55*(profile_z-(WRIST_Z+.030)))*width_ratio
            thumb_weight=smoothstep(web_boundary-.015*width_ratio,web_boundary+.015*width_ratio,v.co.x)*smoothstep(WRIST_Z+.010,WRIST_Z+.073,profile_z)
            nonthumb={bone_name:w for bone_name,w in blend.items() if not bone_name.startswith('thumb_')}
            total_nonthumb=sum(nonthumb.values())
            blend={bone_name:w/max(total_nonthumb,1e-12)*(1-thumb_weight) for bone_name,w in nonthumb.items()}
            if total_nonthumb<1e-12: blend={'palm':1-thumb_weight}
            nearest=None
            for joint,(a,b) in enumerate(zip(thumb_centers,thumb_centers[1:])):
                t=max(0,min(1,(v.co-a).dot(b-a)/(b-a).length_squared))
                point=a.lerp(b,t)
                item=((v.co-point).length,thumb_arcs[joint]+t*thumb_lengths[joint],joint)
                if nearest is None or item[0]<nearest[0]: nearest=item
            arc=nearest[1]
            thumb_blend={f'thumb_{nearest[2]}':1}
            for joint in (1,2):
                half_width=.012
                if abs(arc-thumb_arcs[joint])<half_width:
                    t=smoothstep(thumb_arcs[joint]-half_width,thumb_arcs[joint]+half_width,arc)
                    thumb_blend={f'thumb_{joint-1}':1-t,f'thumb_{joint}':t}
            for bone_name,w in thumb_blend.items(): blend[bone_name]=w*thumb_weight
        selected=sorted(blend.items(),key=lambda item:item[1],reverse=True)[:4]
        total=sum(w for _,w in selected)
        for bone_name,w in selected:
            if w>0: obj.vertex_groups[bone_name].add([v.index],w/total,'REPLACE')
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    for polygon in obj.data.polygons:
        polygon.use_smooth=True
        polygon.material_index=0
    armature=obj.modifiers.new('Continuous deformation','ARMATURE')
    armature.object=rig
    obj.parent=rig
    obj.data.calc_loop_triangles()
    print('CONTINUOUS_ARM',name,len(obj.data.loop_triangles),'triangles')
    return obj

meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
skin_parts=[o for o in meshes if o.data.materials[0]==skin]
sleeve_parts=[o for o in meshes if o.data.materials[0]==sleeve]
continuous_surface('HandSkin',skin_parts,.0024,skin)
continuous_surface('Sleeve',sleeve_parts,.0035,sleeve)

bpy.ops.object.select_all(action='DESELECT')
rig.select_set(True)
bpy.context.view_layer.objects.active=rig
bpy.ops.object.mode_set(mode='POSE')
# A preview action for relaxed fingers; gameplay places shoulder/elbow/wrist dynamically.
for frame, curl in [(1,0),(17,.06),(50,.10),(67,0)]:
    for pb in rig.pose.bones:
        pb.rotation_mode='XYZ'
        pb.rotation_euler=(curl if 'finger' in pb.name or 'thumb' in pb.name else 0,0,0)
        pb.keyframe_insert('rotation_euler',frame=frame)
rig.animation_data.action.name='RelaxedPettingHand'
bpy.ops.object.mode_set(mode='OBJECT')
bpy.context.scene.render.fps=30
bpy.context.scene.frame_end=67
bpy.context.scene.frame_set(1)
bpy.ops.wm.save_as_mainfile(filepath=str(Path(__file__).with_name(MODEL_NAME+'.blend')))
bpy.ops.export_scene.gltf(filepath=str(ROOT/'assets/models/glb/godot_mvp'/ (MODEL_NAME+'.glb')),export_format='GLB',export_animations=True)
print('PLAYER_ARM_READY',len(rig.data.bones),'bones')
