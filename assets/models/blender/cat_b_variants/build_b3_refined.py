"""Actual mesh studies of approved B. Blender --background --python build.py -- B1."""
import bpy, math, random, sys, bisect, json
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[4]
OUT=ROOT/'builds/cat-b3-refined'
variant='B3-refined'
width, fur_scale = 1.06, 1.12
random.seed(371)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
def co(p): return Vector((p[0]*width,-p[2],p[1]))
def mat(name,c,rough=.65):
 m=bpy.data.materials.new(name);m.diffuse_color=(*c,1);m.use_nodes=True
 s=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED');s.inputs['Base Color'].default_value=(*c,1);s.inputs['Roughness'].default_value=rough
 if rough<.3:s.inputs['Coat Weight'].default_value=.4
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
 m=o.modifiers.new('Organic surface','SMOOTH');m.factor=.8;m.iterations=12;bpy.ops.object.modifier_apply(modifier=m.name)
 m=o.modifiers.new('Fine surface','SUBSURF');m.levels=1;bpy.ops.object.modifier_apply(modifier=m.name)
 for p in o.data.polygons:p.use_smooth=True
 return o

def mix(a,b,t):return tuple(x+(y-x)*max(0,min(1,t)) for x,y in zip(a,b))
def color(p,part):
 x,y,z=p.x/width,-p.y,p.z
 if part in ('head','socket'):
  mask=math.exp(-((x/.255)**4+((z-1.245)/.235)**4))*max(0,min(1,(y-.03)*10))
  c=mix((.35,.275,.22),(.095,.065,.052),mask)
  muzzle=max(0,min(1,(1.18-z)*25))*max(0,min(1,(y-.20)*16))
  return mix(c,(.46,.39,.31),muzzle)
 if part=='ear':
  return mix((.12,.075,.056),(.26,.175,.14),max(0,1-abs(x-.19*(1 if x>0 else -1))/.07))
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
head=union('Head_anatomy',[ball('Cranium',(0,1.205,.035),(.45,.365,.345),coat),ball('Brow',(0,1.25,.11),(.37,.22,.27),coat),ball('Nasal bridge',(0,1.19,.222),(.105,.17,.16),coat),ball('Chin',(0,1.079,.217),(.16,.10,.15),cream)]+[ball('Cheek',(s*.142,1.135,.075),(.22,.23,.255),coat) for s in [-1,1]]+[ball('Muzzle',(s*.058,1.117,.248),(.137,.105,.125),cream) for s in [-1,1]],.0055);paint(head,'head')
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
 # Orbital opening and surrounding skin share a spherical contour.
 def eye_point(xx, zz, lift=0):
  return co((side*.108+xx,1.238+zz+side*xx*.13,.202+.80*math.sqrt(max(.0001,.073**2-xx**2-zz**2))+lift))
 v=[];f=[]
 for row in range(15):
  r=row/14
  for j in range(97):
   a=j*math.tau/96;xx=.068*math.cos(a)*r;zz=.049*math.sin(a)*abs(math.sin(a))**.15*r
   v.append(eye_point(xx,zz))
 for row in range(14):
  for j in range(96):
   a=row*97+j;f.append((a,a+1,a+98,a+97))
 mesh('Curved eyeball',v,f,mat('Limbus',(.038,.08,.085),.18))
 # Curved annular iris: no flat disc or triangular fan over the eye.
 iris_mats=[mat('Iris pigment %s %d'%(side,k),mix((.12,.27,.33),(.28,.46,.51),k/23),.2) for k in range(24)]
 v=[];f=[]
 for row in range(11):
  t=row/10
  for j in range(193):
   a=j*math.tau/192
   xx=(.019*(1-t)+.046*t)*math.cos(a)
   zz=(.032*(1-t)+.046*t)*math.sin(a)
   v.append(eye_point(xx,zz,.0005))
 for row in range(10):
  for j in range(192):
   a=row*193+j;f.append((a,a+1,a+194,a+193))
 iris=mesh('Spherical iris',v,f,iris_mats[0])
 iris.data.materials.clear()
 iris_material=mat('Iris continuous pigment',(.2,.4,.5),.34)
 iris.data.materials.append(iris_material)
 attribute=iris.data.color_attributes.new(name='CoatColor',type='FLOAT_COLOR',domain='POINT')
 for i,datum in enumerate(attribute.data):
  row=i//193;angle=(i%193)*math.tau/192
  pigment=.5+.10*math.sin(angle*47)+.05*math.sin(angle*91)+.12*math.sin(row*math.pi/10)
  datum.color=(*mix((.09,.22,.28),(.25,.44,.51),pigment),1)
 node=iris_material.node_tree.nodes.new('ShaderNodeVertexColor');node.layer_name='CoatColor'
 iris_material.node_tree.links.new(node.outputs['Color'],next(n for n in iris_material.node_tree.nodes if n.type=='BSDF_PRINCIPLED').inputs['Base Color'])
 v=[eye_point(0,0,.001)]+[eye_point(.019*math.cos(j*math.tau/96),.032*math.sin(j*math.tau/96),.001) for j in range(97)]
 mesh('Pupil',v,[(0,j+1,j+2) for j in range(96)],black)
 # A soft flesh rim joins the eye opening to the head, avoiding an inserted-button look.
 v=[];f=[]
 for row in range(6):
  t=row/5
  for j in range(97):
   a=j*math.tau/96;xx=(.069+.013*t)*math.cos(a);zz=(.05+.013*t)*math.sin(a)*abs(math.sin(a))**.15
   q=eye_point(xx,zz,-.018*t);v.append(q)
 for row in range(5):
  for j in range(96):
   a=row*97+j;f.append((a,a+1,a+98,a+97))
 socket=mesh('Soft orbital rim',v,[tuple(reversed(face)) for face in f],coat);paint(socket,'head')
 for upper in [-1,1]:
  pts=[]
  for j in range(25):
   a=j*math.pi/24;xx=.068*math.cos(a);zz=upper*.049*math.sin(a)**1.15
   q=eye_point(xx,zz,.001)
   pts.append((q.x/width,q.z,-q.y))
  tube('Fine lid margin',pts,.0016,dark)
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
  n=(o.data.vertices[t.vertices[0]].normal*(1-u)+o.data.vertices[t.vertices[1]].normal*(u*(1-v))+o.data.vertices[t.vertices[2]].normal*(u*v)).normalized()
  if n.length<.1:continue
  if part in ('head','socket'):
   # Keep eye openings and nose free; cheeks comb out and down.
   if part=='head' and -p.y>.17 and any(((p.x/width-s*.108)/.078)**2+((p.z-1.238)/.063)**2<1.15 for s in [-1,1]):continue
   length=(.007 if part=='socket' else (.006 if -p.y>.19 else .035))*fur_scale
   flow=Vector((p.x*2.5,0,-.5))
  elif part=='ear':length=.006;flow=Vector((0,0,1))
  elif part=='tail':length=.052*fur_scale;flow=Vector((-.7,0,-.15))
  else:
   length=(.045 if p.z>.42 else .021)*fur_scale
   if -p.y>.12 and .6<p.z<1.05:length=.075*fur_scale
   flow=Vector((p.x*.25,0,-1))
  length*=random.uniform(.65,1.4)
  direction=(n*.48+flow*.75).normalized();tangent=n.cross(Vector((0,0,1)))
  if tangent.length<.01:tangent=Vector((1,0,0))
  tangent.normalize();across=direction.cross(tangent).normalized()
  start=len(verts);radius=random.uniform(.00030,.00055)
  for row in range(6):
   q=row/5;center=p+n*.001+direction*length*q+n*(math.sin(q*math.pi)*length*.12)
   for k in range(3):
    angle=k*math.tau/3;verts.append(center+(tangent*math.cos(angle)+across*math.sin(angle))*radius*(1-q*.97))
  col=color(p,part);shade=random.uniform(.93,1.05);colors.extend([(*[min(1,x*shade) for x in col],1)]*18)
  for row in range(5):
   for k in range(3):faces.append((start+row*3+k,start+row*3+(k+1)%3,start+(row+1)*3+(k+1)%3,start+(row+1)*3+k))
 hair=mesh(part+' groom fibers',verts,faces,o.data.materials[0]);attr=hair.data.color_attributes.new(name='CoatColor',type='FLOAT_COLOR',domain='POINT')
 for d,c in zip(attr.data,colors):d.color=c
 return hair
for socket in [o for o in bpy.data.objects if o.name.startswith('Soft orbital rim')]:fur(socket,'socket',6500)
fur(body,'body',85000);fur(head,'head',48000);fur(tail,'tail',17000)
# Fine down covers the shell and breaks the ear edge without a thick rim pipe.
for ear in ears:
 bpy.ops.object.select_all(action='DESELECT');ear.select_set(True);bpy.context.view_layer.objects.active=ear
 for modifier in list(ear.modifiers):bpy.ops.object.modifier_apply(modifier=modifier.name)
 paint(ear,'ear');fur(ear,'ear',6000)
for side in [-1,1]:
 for j in range(55):
  t=random.random()*.75;x=side*(.10+.12*random.random()*(1-t)+.10*t);z=1.327+.15*t
  w=tube('Fine ear wisp',[(x,z,.018),(x-side*.012,z+.010,.035),(x-side*.02,z+random.uniform(.015,.03),.03)],.00025,cream)
from mathutils import Matrix
pivot=Vector((0,0,1.03))
pose=Matrix.Translation(pivot) @ Matrix.Rotation(math.radians(-5),4,'Y') @ Matrix.Rotation(math.radians(-4),4,'Z') @ Matrix.Translation(-pivot)
for obj in list(bpy.context.scene.objects):
 if obj.name not in ('Body_anatomy','Tail','body groom fibers','tail groom fibers'):
  obj.matrix_world=pose @ obj.matrix_world
cat_objects=list(bpy.context.scene.objects)
# Neutral identical studio for honest comparison.
bpy.ops.mesh.primitive_plane_add(size=200);floor=bpy.context.object;floor.name='Studio floor';floor.data.materials.append(mat('Studio',(.20,.22,.23)))
world=bpy.context.scene.world;world.use_nodes=True;next(n for n in world.node_tree.nodes if n.type=='BACKGROUND').inputs[0].default_value=(.27,.30,.34,1);next(n for n in world.node_tree.nodes if n.type=='BACKGROUND').inputs[1].default_value=.35
for name,pos,power,size in [('Key',(-3,-4,5),450,4),('Fill',(3,-2,3),180,3),('Rim',(1,3,4),500,3)]:
 bpy.ops.object.light_add(type='AREA',location=pos);o=bpy.context.object;o.name=name;o.data.energy=power;o.data.shape='DISK';o.data.size=size;o.rotation_euler=(Vector((0,0,.8))-o.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(location=(2.2,-4.9,2.05));camera=bpy.context.object;camera.rotation_euler=(Vector((0,-.01,.80))-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.type='ORTHO';camera.data.ortho_scale=1.93;bpy.context.scene.camera=camera
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=64;scene.cycles.use_denoising=True;scene.render.resolution_x=900;scene.render.resolution_y=1000;scene.render.resolution_percentage=100
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
