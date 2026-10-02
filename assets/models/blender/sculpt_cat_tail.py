"""Continuous tail surface with analytic arc-space skinning for the existing rig."""
import math
import bpy
import bmesh
from mathutils import Vector

NAMES = ['tail_1','tail_2','tail_3','tail_4','tail_4_end']

def segments(rig):
    output=[]
    arc=0.
    for name in NAMES:
        bone=rig.data.bones[name]
        a,b=bone.head_local.copy(),bone.tail_local.copy()
        length=(b-a).length
        output.append((name,a,b,arc,length))
        arc+=length
    return output,arc

def nearest(point,chain):
    samples=[]
    for name,a,b,start,length in chain:
        t=max(0.,min(1.,(point-a).dot(b-a)/(length*length)))
        axis=a+(b-a)*t
        samples.append(((point-axis).length,start+t*length,axis))
    return min(samples,key=lambda p:p[0])

def weights(arc,chain):
    for i in range(1,len(chain)):
        joint=chain[i][3]
        half=min(chain[i-1][4],chain[i][4])*.45
        if abs(arc-joint)<half:
            t=(arc-joint+half)/(half*2)
            t=t*t*(3-2*t)
            return {chain[i-1][0]:1-t,chain[i][0]:t}
    index=max(i for i,s in enumerate(chain) if arc>=s[3])
    return {chain[index][0]:1.}

def replace_tail(body,rig,material):
    chain,total=segments(rig)
    names={g.index:g.name for g in body.vertex_groups}
    remove=set()
    for vertex in body.data.vertices:
        weight=sum(g.weight for g in vertex.groups if names[g.group] in NAMES)
        distance,arc,_=nearest(vertex.co,chain)
        if weight>.5 and arc>.025:
            remove.add(vertex.index)
    mesh=bmesh.new()
    mesh.from_mesh(body.data)
    mesh.verts.ensure_lookup_table()
    bmesh.ops.delete(mesh,geom=[mesh.verts[i] for i in remove],context='VERTS')
    # A voxel union needs closed input volumes. Leaving the old tail cut open
    # lets the remesher classify the entire trunk as exterior.
    boundary=[edge for edge in mesh.edges if edge.is_boundary]
    if boundary: bmesh.ops.holes_fill(mesh,edges=boundary,sides=0)
    bmesh.ops.recalc_face_normals(mesh,faces=list(mesh.faces))
    mesh.to_mesh(body.data)
    mesh.free()
    vertices=[]
    faces=[]
    arcs=[]
    rings=100
    sides=16
    for ring in range(rings):
        arc=total*ring/(rings-1)
        section=max(i for i,s in enumerate(chain) if arc>=s[3])
        _,a,b,start,length=chain[section]
        center=a+(b-a)*((arc-start)/length)
        tangent=(b-a).normalized()
        lateral=Vector((0,1,0))
        upright=tangent.cross(lateral).normalized()
        # Rounded end instead of a thin, voxel-eroded spike.
        t=arc/total
        radius=.012-(.012-.005)*(t*t*(3-2*t))
        if t>.95: radius*=math.sqrt(max(.01,1-((t-.95)/.05)**2))
        for side in range(sides):
            angle=math.tau*side/sides
            vertices.append(center+radius*(lateral*math.cos(angle)+upright*math.sin(angle)))
            arcs.append(arc)
    for ring in range(rings-1):
        for side in range(sides):
            a=ring*sides+side
            b=ring*sides+(side+1)%sides
            faces.append((a,b,b+sides,a+sides))
    faces.extend([tuple(reversed(range(sides))),tuple(range((rings-1)*sides,rings*sides))])
    data=bpy.data.meshes.new('Continuous tail tube')
    data.from_pydata(vertices,[],faces)
    data.materials.append(material)
    tube=bpy.data.objects.new('Continuous tail tube',data)
    bpy.context.collection.objects.link(tube)
    tube['anatomical_core']=True
    for name in NAMES: tube.vertex_groups.new(name=name)
    for index,arc in enumerate(arcs):
        for name,weight in weights(arc,chain).items():
            tube.vertex_groups[name].add([index],weight,'REPLACE')
    print('TAIL_TUBE',{'removed_source_vertices':len(remove),'new_vertices':len(vertices)})
    return tube

def reskin_tail(body,rig):
    chain,total=segments(rig)
    names={g.index:g.name for g in body.vertex_groups}
    changed=0
    for vertex in body.data.vertices:
        distance,arc,_=nearest(vertex.co,chain)
        if arc<=.04 or distance>.018: continue
        old=sum(g.weight for g in vertex.groups if names[g.group] in NAMES)
        if old<.5: continue
        for group in body.vertex_groups: group.remove([vertex.index])
        for name,weight in weights(arc,chain).items():
            body.vertex_groups[name].add([vertex.index],weight,'REPLACE')
        changed+=1
    print('TAIL_RESKIN',changed)
