"""Actual mesh studies of approved B. Blender --background --python build.py -- B1."""
import bpy, math, random, sys, bisect, json
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[4]
OUT=ROOT/'builds/cat-b-variants'
variant=sys.argv[sys.argv.index('--')+1] if '--' in sys.argv else 'B1'
width, fur_scale = {'B1':(1.,1.),'B2':(.93,.72),'B3':(1.06,1.28)}[variant]
random.seed(371)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
def co(p): return Vector((p[0]*width,-p[2],p[1]))
def mat(name,c,rough=.65):
 m=bpy.data.materials.new(name);m.diffuse_color=(*c,1);m.use_nodes=True
 s=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED');s.inputs['Base Color'].default_value=(*c,1);s.inputs['Roughness'].default_value=rough
 return m
coat=mat('Taupe',(.28,.205,.17));cream=mat('Ivory',(.72,.65,.53));dark=mat('Seal',(.075,.048,.039));white=mat('Mittens',(.84,.8,.7));pink=mat('Ear interior',(.16,.105,.083));black=mat('Pupil',(.006,.009,.012),.19)
def ball(name,p,size,material):
 bpy.ops.mesh.primitive_uv_sphere_add(segments=40,ring_count=28,location=co(p));o=bpy.context.object;o.name=name;o.scale=(size[0]*width/2,size[2]/2,size[1]/2)
 bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.data.materials.append(material)
 for f in o.data.polygons:f.use_smooth=True
 return o

def mesh(name,v,f,material):
 m=bpy.data.meshes.new(name);m.from_pydata(v,[],f);m.update();o=bpy.data.objects.new(name,m);bpy.context.collection.objects.link(o);m.materials.append(material)
 for p in m.polygons:p.use_smooth=True
 return o

def tube(name,points,r,material):
 c=bpy.data.curves.new(name,'CURVE');c.dimensions='3D';c.bevel_depth=r;c.bevel_resolution=2;c.resolution_u=12
 s=c.splines.new('BEZIER');s.bezier_points.add(len(points)-1)
 for b,p in zip(s.bezier_points,points):b.co=co(p);b.handle_left_type='AUTO';b.handle_right_type='AUTO'
 o=bpy.data.objects.new(name,c);bpy.context.collection.objects.link(o);c.materials.append(material)
 bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o;bpy.ops.object.convert(target='MESH');return o

def union(name,parts,voxel):
 bpy.ops.object.select_all(action='DESELECT')
 for o in parts:o.select_set(True)
 bpy.context.view_layer.objects.active=parts[0];bpy.ops.object.join();o=bpy.context.object;o.name=name
 bpy.ops.object.transform_apply(location=True,rotation=True,scale=True);o.data.remesh_voxel_size=voxel;bpy.ops.object.voxel_remesh()
 m=o.modifiers.new('Organic surface','SMOOTH');m.factor=.8;m.iterations=7;bpy.ops.object.modifier_apply(modifier=m.name)
 m=o.modifiers.new('Fine surface','SUBSURF');m.levels=1;bpy.ops.object.modifier_apply(modifier=m.name)
 for p in o.data.polygons:p.use_smooth=True
 return o

def mix(a,b,t):return tuple(x+(y-x)*max(0,min(1,t)) for x,y in zip(a,b))
def color(p,part):
 x,y,z=p.x/width,-p.y,p.z
 if part=='head':
  mask=math.exp(-((x/.255)**4+((z-1.245)/.235)**4))*max(0,min(1,(y-.03)*10))
  c=mix((.35,.275,.22),(.095,.065,.052),mask)
  muzzle=max(0,min(1,(1.18-z)*25))*max(0,min(1,(y-.20)*16))
  return mix(c,(.46,.39,.31),muzzle)
 if part=='tail':return (.11,.073,.052)
 c=mix((.30,.235,.19),(.72,.65,.53),max(0,min(1,(y-.01)*10))*max(0,1-(abs(x)/.29)**3)*max(0,min(1,(z-.25)*4)))
 return mix(c,(.84,.8,.7),max(0,min(1,(.18-z)*32)))

def paint(o,part):
 m=mat(part+' painted coat',(1,1,1));n=m.node_tree.nodes.new('ShaderNodeVertexColor');n.layer_name='CoatColor';m.node_tree.links.new(n.outputs['Color'],next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED').inputs['Base Color'])
 o.data.materials.clear();o.data.materials.append(m);a=o.data.color_attributes.new(name='CoatColor',type='FLOAT_COLOR',domain='POINT')
 for v,d in zip(o.data.vertices,a.data):d.color=(*color(o.matrix_world@v.co,part),1)

parts=[ball('Pelvis',(0,.40,-.08),(.60,.72,.55),coat),ball('Ribcage',(0,.72,.005),(.45,.64,.42),coat),ball('Neck',(0,.995,.015),(.34,.45,.33),coat)]
for s in [-1,1]:
 parts += [ball('Haunch',(s*.225,.28,-.04),(.29,.44,.40),coat),ball('Rear foot',(s*.26,.082,.17),(.18,.155,.31),white),ball('Shoulder',(s*.15,.72,.105),(.17,.43,.21),coat),ball('Foreleg',(s*.14,.39,.20),(.115,.57,.13),coat),ball('Wrist',(s*.14,.16,.23),(.13,.21,.14),white),ball('Forepaw',(s*.14,.074,.28),(.17,.14,.24),white)]
 for j in [-1,0,1]:parts.append(ball('Toe',(s*.14+j*.043,.056,.345),(.057,.088,.10),white))
body=union('Body_anatomy',parts,.009);paint(body,'body')
head=union('Head_anatomy',[ball('Cranium',(0,1.205,.035),(.435,.375,.345),coat),ball('Brow',(0,1.25,.11),(.37,.22,.27),coat),ball('Nasal bridge',(0,1.19,.222),(.105,.17,.16),coat),ball('Chin',(0,1.079,.217),(.16,.10,.15),cream)]+[ball('Cheek',(s*.142,1.135,.075),(.20,.235,.255),coat) for s in [-1,1]]+[ball('Muzzle',(s*.058,1.117,.248),(.14,.103,.13),cream) for s in [-1,1]],.0055);paint(head,'head')
tail=tube('Tail',[(.16,.18,-.26),(.40,.13,-.29),(.47,.10,-.04),(.37,.09,.28),(.13,.09,.43),(-.18,.09,.41)],.069,dark);paint(tail,'tail')
# Ear pinnae: tapered curved shells with a recessed warm interior.
ears=[]
for side in [-1,1]:
 v=[];f=[]
 for row in range(21):
  t=row/20;half=.090*(1-t)**.72+.002
  for col in range(13):
   u=col/6-1;x=side*(.16+.055*t)+u*half;z=1.315+.195*t
   y=.045-.045*t-.036*(1-u*u)*math.sin(math.pi*t)
   v.append(co((x,z,y)))
 for row in range(20):
  for col in range(12):
   a=row*13+col;f.append((a,a+1,a+14,a+13))
 o=mesh('Ear pinna',v,f,pink);solid=o.modifiers.new('Ear thickness','SOLIDIFY');solid.thickness=.014;bev=o.modifiers.new('Soft ear','SUBSURF');bev.levels=2
 ears.append(o)
 tube('Ear rim',[(side*.07,1.315,.045),(side*.15,1.425,.005),(side*.215,1.51,0),(side*.245,1.385,.025),(side*.25,1.315,.045)],.009,dark)
 # Almond eyes with a curved corneal surface, radial iris detail and vertical pupils.
 v=[];f=[]
 for row in range(13):
  r=row/12
  for j in range(65):
   a=j*math.tau/64;xx=.066*math.cos(a)*r;zz=.037*math.sin(a)*abs(math.sin(a))**.28*r
   v.append(co((side*.108+xx,1.238+zz+side*xx*.16,.218+.024*(1-r*r))))
 for row in range(12):
  for j in range(64):
   a=row*65+j;f.append((a,a+1,a+66,a+65))
 eye=mesh('Almond eye',v,f,mat('Eye outer limbus',(.025,.055,.065),.22))
 # Iris fan, varied radial pigmentation.
 v=[co((side*.108,1.238,.246))];f=[]
 iris_mats=[mat('Iris fiber %s %d'%(side,k),mix((.13,.28,.35),(.19,.36,.44),k/15),.28) for k in range(16)]
 for j in range(129):
  a=j*math.tau/128;v.append(co((side*.108+.038*math.cos(a),1.238+.034*math.sin(a),.242)))
 for j in range(128):f.append((0,j+1,j+2))
 iris=mesh('Iris radial fibers',v,f,iris_mats[0])
 for m in iris_mats[1:]:iris.data.materials.append(m)
 for p in iris.data.polygons:p.material_index=random.randrange(16)
 ball('Vertical pupil',(side*.108,1.238,.249),(.013,.047,.009),black)
 for upper in [-1,1]:
  pts=[]
  for j in range(17):
   a=j*math.pi/16;xx=.066*math.cos(a);zz=upper*.037*math.sin(a)**1.28
   pts.append((side*.108+xx,1.238+zz+side*xx*.16,.218))
  tube('Eyelid',pts,.0035,dark)
 ball('Corneal highlight',(side*.108-.012,1.252,.255),(.006,.008,.004),white)
 for j in range(8):
  x=side*(.038+random.random()*.06);z=1.116+random.uniform(-.019,.019)
  ball('Whisker follicle',(x,z,.306),(.0035,.0035,.002),dark)
 for j in range(6):
  tube('Whisker',[(side*.07,1.114-j*.003,.305),(side*.22,1.12-j*.012,.32),(side*(.35+random.random()*.075),1.17-j*.024+random.uniform(-.025,.025),.30)],.0005,cream)
# Compact triangular nose with a split lip.
mesh('Nose leather',[co(p) for p in [(-.033,1.165,.305),(.033,1.165,.305),(0,1.133,.325),(-.023,1.164,.325),(.023,1.164,.325)]],[(0,1,4,3),(3,4,2),(0,3,2),(1,2,4)],dark)
tube('Philtrum',[(0,1.136,.322),(0,1.112,.307)],.002,dark)
for s in [-1,1]:tube('Lip',[(0,1.112,.307),(s*.027,1.102,.303),(s*.058,1.11,.295)],.0018,dark)
# Exportable tapered mesh fibers sampled over the actual anatomical surfaces.
def fur(o,part,count):
 bpy.context.view_layer.update();o.data.calc_loop_triangles();tri=list(o.data.loop_triangles);weights=[];total=0
 for t in tri:total+=t.area;weights.append(total)
 verts=[];faces=[];colors=[]
 for i in range(count):
  t=tri[bisect.bisect_left(weights,random.random()*total)];a,b,c=[o.matrix_world@o.data.vertices[k].co for k in t.vertices]
  u=math.sqrt(random.random());v=random.random();p=a*(1-u)+b*(u*(1-v))+c*(u*v)
  n=(b-a).cross(c-a).normalized()
  if n.length<.1:continue
  if part=='head':
   # Keep eye openings and nose free; cheeks comb out and down.
   if -p.y>.17 and any(((p.x/width-s*.108)/.070)**2+((p.z-1.238)/.042)**2<1.15 for s in [-1,1]):continue
   length=(.010 if -p.y>.20 else .040)*fur_scale
   flow=Vector((p.x*2.5,0,-.5))
  elif part=='tail':length=.052*fur_scale;flow=Vector((-.7,0,-.15))
  else:
   length=(.045 if p.z>.42 else .021)*fur_scale
   if -p.y>.12 and .6<p.z<1.05:length=.075*fur_scale
   flow=Vector((p.x*.25,0,-1))
  length*=random.uniform(.65,1.4)
  direction=(n*.48+flow*.75).normalized();tangent=n.cross(Vector((0,0,1)))
  if tangent.length<.01:tangent=Vector((1,0,0))
  tangent.normalize();across=direction.cross(tangent).normalized()
  start=len(verts);radius=random.uniform(.00065,.00115)
  for row in range(4):
   q=row/3;center=p+n*.001+direction*length*q+n*(math.sin(q*math.pi)*length*.12)
   for k in range(3):
    angle=k*math.tau/3;verts.append(center+(tangent*math.cos(angle)+across*math.sin(angle))*radius*(1-q*.97))
  col=color(p,part);shade=random.uniform(.8,1.12);colors.extend([(*[min(1,x*shade) for x in col],1)]*12)
  for row in range(3):
   for k in range(3):faces.append((start+row*3+k,start+row*3+(k+1)%3,start+(row+1)*3+(k+1)%3,start+(row+1)*3+k))
 hair=mesh(part+' groom fibers',verts,faces,o.data.materials[0]);attr=hair.data.color_attributes.new(name='CoatColor',type='FLOAT_COLOR',domain='POINT')
 for d,c in zip(attr.data,colors):d.color=c
 return hair
fur(body,'body',42000);fur(head,'head',18000);fur(tail,'tail',9000)
# Small airy ear furnishings.
for side in [-1,1]:
 for j in range(240):
  t=random.random();x=side*(.10+.13*random.random()*(1-t)+.10*t);z=1.325+.17*t
  tube('Ear furnishing',[(x,z,.040),(x-side*random.uniform(.005,.020),z+.008,.055),(x-side*random.uniform(.015,.035),z+random.uniform(.018,.05),.045)],.00045,cream)
cat_objects=list(bpy.context.scene.objects)
# Neutral identical studio for honest comparison.
bpy.ops.mesh.primitive_plane_add(size=200);floor=bpy.context.object;floor.name='Studio floor';floor.data.materials.append(mat('Studio',(.20,.22,.23)))
world=bpy.context.scene.world;world.use_nodes=True;next(n for n in world.node_tree.nodes if n.type=='BACKGROUND').inputs[0].default_value=(.27,.30,.34,1);next(n for n in world.node_tree.nodes if n.type=='BACKGROUND').inputs[1].default_value=.35
for name,pos,power,size in [('Key',(-3,-4,5),450,4),('Fill',(3,-2,3),180,3),('Rim',(1,3,4),500,3)]:
 bpy.ops.object.light_add(type='AREA',location=pos);o=bpy.context.object;o.name=name;o.data.energy=power;o.data.shape='DISK';o.data.size=size;o.rotation_euler=(Vector((0,0,.8))-o.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(location=(2.2,-4.9,2.05));camera=bpy.context.object;camera.rotation_euler=(Vector((0,-.01,.80))-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.type='ORTHO';camera.data.ortho_scale=1.93;bpy.context.scene.camera=camera
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=32;scene.cycles.use_denoising=True;scene.render.resolution_x=900;scene.render.resolution_y=1000;scene.render.resolution_percentage=100
scene.view_settings.view_transform='AgX';scene.render.image_settings.file_format='PNG'
OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.object.select_all(action='DESELECT')
for o in cat_objects:o.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(OUT/(variant+'.glb')),export_format='GLB',use_selection=True,export_apply=True)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/(variant+'.blend')))
scene.render.filepath=str(OUT/(variant+'-three-quarter.png'));bpy.ops.render.render(write_still=True)
camera.location=(0,-5,1.65);camera.rotation_euler=(Vector((0,0,.8))-camera.location).to_track_quat('-Z','Y').to_euler()
scene.render.filepath=str(OUT/(variant+'-front.png'));bpy.ops.render.render(write_still=True)
print('CAT_VARIANT_COMPLETE',variant,flush=True)
