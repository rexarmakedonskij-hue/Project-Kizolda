"""Run with Blender --background --python assets/models/blender/build_mvp.py."""
import bpy, math, random
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
OUT=ROOT/'assets/models/glb/godot_mvp'
SRC=Path(__file__).parent
random.seed(8)
def reset():
    bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
def mat(name, color):
    m=bpy.data.materials.new(name); m.diffuse_color=(*color,1); m.use_nodes=True
    bs=next((n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED'),None)
    if bs is None:
        bs=m.node_tree.nodes.new('ShaderNodeBsdfPrincipled'); out=m.node_tree.nodes.new('ShaderNodeOutputMaterial'); m.node_tree.links.new(bs.outputs['BSDF'],out.inputs['Surface'])
    bs.inputs['Base Color'].default_value=(*color,1); bs.inputs['Roughness'].default_value=.7
    return m
def coord(p): return (p[0],-p[2],p[1])
def box(name,p,s,m,bevel=.04):
    bpy.ops.mesh.primitive_cube_add(size=1,location=coord(p)); o=bpy.context.object; o.name=name; o.dimensions=(s[0],s[2],s[1]); bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    o.data.materials.append(m)
    if bevel:
        b=o.modifiers.new('Soft edges','BEVEL'); b.width=bevel; b.segments=3
        bpy.context.view_layer.objects.active=o; bpy.ops.object.modifier_apply(modifier=b.name)
    return o
def sphere(name,p,s,m):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=20,ring_count=12,location=coord(p)); o=bpy.context.object; o.name=name; o.scale=(s[0]/2,s[2]/2,s[1]/2); o.data.materials.append(m)
    for f in o.data.polygons:f.use_smooth=True
    return o
def tube(name,points,r,m):
    c=bpy.data.curves.new(name,'CURVE'); c.dimensions='3D'; c.bevel_depth=r; c.bevel_resolution=3
    sp=c.splines.new('BEZIER'); sp.bezier_points.add(len(points)-1)
    for v,p in zip(sp.bezier_points,points): v.co=coord(p); v.handle_left_type='AUTO'; v.handle_right_type='AUTO'
    o=bpy.data.objects.new(name,c); bpy.context.collection.objects.link(o); o.data.materials.append(m)
    bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o;bpy.ops.object.convert(target='MESH')
    return o
def save(name):
    bpy.ops.wm.save_as_mainfile(filepath=str(SRC/(name+'.blend')))
    bpy.ops.export_scene.gltf(filepath=str(OUT/(name+'.glb')),export_format='GLB',export_yup=True)
reset()
wood=mat('Honey oak',(.64,.43,.25)); pale=mat('Pale oak',(.86,.68,.43)); trim=mat('Oak edges',(.46,.28,.16)); green=mat('Sage walls',(.4,.58,.49)); cream=mat('Warm linen',(.9,.85,.71)); white=mat('Porcelain',(.97,.94,.84)); dark=mat('Charcoal',(.065,.12,.14)); mint=mat('Mint',(.28,.72,.58)); coral=mat('Terracotta',(.79,.32,.22)); sky=mat('Afternoon sky',(.43,.73,.83)); leaf=mat('Leaves',(.16,.4,.23)); gold=mat('Brass',(.72,.5,.17))
box('Floor foundation',(0,-.13,-1),(12,.2,12),trim)
for row in range(15):
 for col in range(6): box('Oak floorboard',(-5+col*2,-.03,-6.5+row*.75),(1.985,.06,.735),wood,.015)
box('Back wallpaper',(0,2.6,-5),(12,5.2,.15),cream)
for side in [-1,1]:
 box('Sage side wall',(side*6,2.6,0),(.15,5.2,10),green)
 box('Side skirting',(side*5.91,.06,0),(.03,.12,10),white,.006)
box('Back skirting',(0,.06,-4.91),(12,.12,.03),white,.006)
# Subtle wallpaper rhythm, remains legible at a distance.
for i in range(39):box('Wallpaper stripe',(-5.8+i*.3,2.65,-4.913),(.025,4.75,.008),pale,.0)
box('Rounded woven rug',(0,.0013,-1),(5.3,.0026,4.3),green,.001)
for i in range(17):box('Rug weave',(-2.4+i*.3,.0028,-1),(.018,.0004,4),cream,0)
# Desk with drawer, feet and raised rear shelf.
box('Rounded oak desktop',(0,.86,-1.7),(3.65,.16,1.55),pale,.075)
box('Desktop dark underside',(0,.77,-1.7),(3.5,.06,1.4),trim)
for x in [-1.5,1.5]:
 for z in [-2.25,-1.15]:
  box('Sturdy desk leg',(x,.38,z),(.16,.75,.16),wood)
  box('Brass foot',(x,.09,z),(.18,.14,.18),gold,.02)
box('Drawer housing',(1.03,.65,-1.65),(.8,.27,1.2),wood)
box('Drawer face',(1.03,.66,-1.025),(.77,.23,.07),pale,.025)
box('Drawer handle',(1.03,.66,-.96),(.25,.035,.07),gold,.01)
box('Raised rear shelf',(0,1.05,-2.25),(3.38,.1,.4),pale)
for x in [-1.45,1.45]:box('Shelf support',(x,.95,-2.25),(.09,.2,.25),wood)
# Laptop and readable keyboard, webcam.
box('Laptop base',(0,.98,-1.7),(1.52,.055,.85),dark,.035)
box('Laptop display frame',(0,1.46,-2.08),(1.56,.96,.07),dark)
box('Laptop luminous screen',(0,1.46,-2.033),(1.4,.8,.018),mint,.025)
for row in range(4):
 for col in range(11):box('Keyboard key',(-.64+col*.126,1.014,-1.91+row*.135),(.09,.012,.09),cream,.008)
box('Trackpad',(0,1.015,-1.42),(.45,.01,.18),wood,.02)
box('Webcam',(0,1.99,-2.08),(.19,.09,.09),dark,.02)
sphere('Webcam lens',(0,1.99,-2.025),(.04,.04,.018),sky)
for row in range(4):box('Display task line',(-.07,1.7-row*.15,-2.018),(.93-row*.12,.033,.007),white,.005)
# Coffee and spray bottle.
sphere('Coffee cup',(-1.15,1.1,-1.45),(.27,.33,.27),white)
tube('Cup handle',[(-1.26,1.2,-1.45),(-1.4,1.16,-1.45),(-1.4,1.03,-1.45),(-1.26,1.02,-1.45)],.025,white)
sphere('Coffee surface',(-1.15,1.245,-1.45),(.19,.01,.19),trim)
box('Notebook',(-1.05,.985,-1.97),(.5,.035,.32),coral,.01)
box('Spray bottle',(1.36,1.14,-1.58),(.2,.4,.17),mint,.06)
box('Spray trigger',(1.36,1.39,-1.58),(.27,.13,.12),coral,.025)
# Window.
box('Window outer frame',(-3.05,2.8,-4.78),(2.6,2.3,.16),wood)
box('Window sky',(-3.05,2.8,-4.68),(2.39,2.09,.03),sky)
for x in [-4.27,-3.05,-1.83]:box('Window mullion',(x,2.8,-4.64),(.09,2.16,.06),white,.01)
box('Window cross',(-3.05,2.8,-4.63),(2.45,.08,.07),white,.01)
box('Window sill',(-3.05,1.66,-4.56),(2.9,.12,.49),pale)
for x in [-4.58,-1.52]:
 for k in range(5):box('Curtain fold',(x+k*.08,2.88,-4.52),(.12,2.55,.14),green,.055)
# Shelf, books, framed cat illustration.
box('Wall shelf',(2.8,2.62,-4.62),(2.5,.12,.55),wood)
for i in range(8):box('Book',(1.83+i*.2,2.94,-4.6),(.15,.52+(i%3)*.06,.3),[mint,coral,pale][i%3],.015)
box('Frame',(0,3.2,-4.78),(1.4,1.3,.14),wood)
box('Print',(0,3.2,-4.69),(1.2,1.1,.02),green)
sphere('Print cat face',(0,3.23,-4.66),(.52,.45,.025),cream)
for x in [-.19,.19]:box('Print ears',(x,3.46,-4.655),(.13,.17,.02),cream,.015)
for x in [-.11,.11]:sphere('Print eyes',(x,3.25,-4.64),(.045,.065,.015),dark)
# Plant and cat bed.
sphere('Plant pot',(3.5,.36,-4.25),(.65,.7,.65),coral)
for i in range(7):
 a=i*math.tau/7
 tip=(3.5+math.cos(a)*.46,1.2+random.random()*.45,-4.25+math.sin(a)*.35)
 tube('Plant stem',[(3.5,.65,-4.25),tip],.025,leaf); sphere('Plant leaf',tip,(.36,.6,.22),leaf)
sphere('Cat bed',(4.6,.15,-2.1),(1.3,.25,.9),coral)
sphere('Bed cushion',(4.6,.27,-2.1),(1.08,.1,.7),cream)
save('office')
reset()
import runpy
point, white_fur = runpy.run_path(str(SRC/'cat_model.py'))['build_cat'](bpy, sphere, tube, mat, coord)
runpy.run_path(str(SRC/'rig_cat.py'))['rig_cat'](bpy, math, sphere, coord, point, white_fur)
save('cat')
print('BLENDER_MVP_EXPORT_OK')
