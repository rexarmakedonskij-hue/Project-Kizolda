"""Optional feline form pass for an isolated cat_reference_form_v1 build.

Keeps the source rig and face identity while rounding ear roots, the underside
of the jaw, and the four leg transitions. All coordinates are rig-rest space.
"""
import math

import bpy
import bmesh
from mathutils import Vector


def _smooth(a, b, value):
    t = max(0.0, min(1.0, (value - a) / (b - a)))
    return t * t * (3 - 2 * t)


def _mesh(name, vertices, faces, material, body):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.matrix_world = body.matrix_world.copy()
    mesh.materials.append(material)
    coat = mesh.color_attributes.new(name='Coat', type='FLOAT_COLOR', domain='POINT')
    for datum in coat.data:
        datum.color = material.diffuse_color
    return obj


def add_ears(body, rig, coat_material):
    """Create two upright, rounded-root ear shells for common voxel union."""
    into_body = body.matrix_world.inverted() @ rig.matrix_world
    ears = []
    for sign in [-1, 1]:
        # Both roots enter the crown. The near-vertical outer edge gives a
        # feline silhouette without preserving the source's folded ear wedge.
        outline = [
            (.240, .030, .244),
            (.239, .066, .245),
            (.237, .079, .261),
            (.233, .077, .286),
            (.229, .067, .311),
            (.234, .050, .284),
            (.238, .039, .260),
        ]
        front = [into_body @ Vector((x, sign * y, z)) for x, y, z in outline]
        back = [into_body @ Vector((x - .018, sign * y, z - .001))
                for x, y, z in outline]
        count = len(outline)
        faces = [tuple(range(count)), tuple(reversed(range(count, 2 * count)))]
        faces += [(i, (i + 1) % count, (i + 1) % count + count, i + count)
                  for i in range(count)]
        ear = _mesh(f'Upright {"left" if sign > 0 else "right"} ear',
                    front + back, faces, coat_material, body)
        ear.vertex_groups.new(name='head').add(list(range(count * 2)), 1.0, 'REPLACE')
        ear['anatomical_core'] = True
        bm = bmesh.new()
        bm.from_mesh(ear.data)
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        bm.to_mesh(ear.data)
        bm.free()
        ears.append(ear)
    return ears


def add_inner_ears(body, rig, material):
    """Inset front-facing ear details above the fused shell surface."""
    into_body = body.matrix_world.inverted() @ rig.matrix_world
    details = []
    for sign in [-1, 1]:
        points = [(.245, .043, .259), (.244, .067, .258),
                  (.240, .069, .278), (.236, .065, .295),
                  (.241, .052, .279)]
        vertices = [into_body @ Vector((x, sign * y, z)) for x, y, z in points]
        faces = [(0, 1, 2, 4), (4, 2, 3)]
        obj = _mesh(f'Inset {"left" if sign > 0 else "right"} ear',
                    vertices, faces if sign > 0 else [tuple(reversed(f)) for f in faces],
                    material, body)
        obj.vertex_groups.new(name='head').add(list(range(len(vertices))), 1.0, 'REPLACE')
        details.append(obj)
    return details


def add_jaw_bridge(body, rig, coat_material):
    """Connect the lower cheek to the rising neck without a cut-out under chin."""
    into_body = body.matrix_world.inverted() @ rig.matrix_world
    vertices, points, faces = [], [], []
    rings, sides = 20, 32
    center = Vector((.222, -.0003, .180))
    radii = Vector((.051, .030, .020))
    for ring in range(rings + 1):
        latitude = -math.pi / 2 + math.pi * ring / rings
        for side in range(sides):
            longitude = math.tau * side / sides
            p = center + Vector((
                math.sin(latitude) * radii.x,
                math.cos(latitude) * math.cos(longitude) * radii.y,
                math.cos(latitude) * math.sin(longitude) * radii.z,
            ))
            points.append(p)
            vertices.append(into_body @ p)
    for ring in range(rings):
        for side in range(sides):
            a = ring * sides + side
            b = ring * sides + (side + 1) % sides
            faces.append((a, b, b + sides, a + sides))
    jaw = _mesh('Lower cheek and throat bridge', vertices, faces, coat_material, body)
    head = jaw.vertex_groups.new(name='head')
    neck = jaw.vertex_groups.new(name='neck')
    for index, point in enumerate(points):
        head_share = .12 + .88 * _smooth(.187, .253, point.x)
        head.add([index], head_share, 'REPLACE')
        neck.add([index], 1 - head_share, 'REPLACE')
    for polygon in jaw.data.polygons:
        polygon.use_smooth = True
    jaw['anatomical_core'] = True
    return jaw


def reskin_leg_joints(body, rig):
    """Blend bone influence across leg joints over a physical arc length.

    Nearest-surface transfer gives almost rigid islands around an elbow or
    hock. Arc-space interpolation removes the hard switch while retaining the
    source shoulder/hip skin where a leg enters the torso.
    """
    into_rig = rig.matrix_world.inverted() @ body.matrix_world
    names = {group.index: group.name for group in body.vertex_groups}
    chains = {}
    for limb in ['front', 'back']:
        for side in ['left', 'right']:
            bones = [rig.data.bones[f'leg_{limb}_{side}_{i}'] for i in range(1, 5)]
            points = [bones[0].head_local.copy()] + [bone.tail_local.copy() for bone in bones]
            lengths = [bone.length for bone in bones]
            starts = [sum(lengths[:i]) for i in range(4)]
            chains[(limb, side)] = (bones, points, starts)
    modified = 0
    for vertex in body.data.vertices:
        point = into_rig @ vertex.co
        old = {names[group.group]: group.weight for group in vertex.groups}
        candidate = None
        for (limb, side), (bones, points, starts) in chains.items():
            chain_prefix = f'leg_{limb}_{side}_'
            ownership = sum(weight for name, weight in old.items()
                            if name.startswith(chain_prefix))
            if ownership < .08:
                continue
            outer = ((point.y > .006) if side == 'left' else (point.y < -.006))
            if not outer:
                continue
            ceiling = .133 if limb == 'front' else .160
            if not (.014 < point.z < ceiling):
                continue
            nearest = None
            for index in range(4):
                a, b = points[index], points[index + 1]
                axis = b - a
                fraction = max(0.0, min(1.0, (point - a).dot(axis) / axis.length_squared))
                distance = (point - a.lerp(b, fraction)).length
                if nearest is None or distance < nearest[0]:
                    nearest = distance, starts[index] + axis.length * fraction
            distance, arc = nearest
            if distance > (.028 if limb == 'front' else .032):
                continue
            joint_arcs = starts[1:]
            desired = {}
            if arc <= joint_arcs[0]:
                base = 0
            elif arc <= joint_arcs[1]:
                base = 1
            elif arc <= joint_arcs[2]:
                base = 2
            else:
                base = 3
            desired[bones[base].name] = 1.0
            for joint in range(3):
                mid = joint_arcs[joint]
                blend_width = .012 if limb == 'front' else .014
                if abs(arc - mid) < blend_width:
                    share = _smooth(mid - blend_width, mid + blend_width, arc)
                    desired = {bones[joint].name: 1 - share,
                               bones[joint + 1].name: share}
                    break
            fade_height = (1 - _smooth(ceiling - .022, ceiling, point.z))
            fade_floor = _smooth(.014, .022, point.z)
            strength = (_smooth(.08, .55, ownership) * fade_height * fade_floor
                        * (1 - _smooth(.022, .032, distance)))
            if candidate is None or strength > candidate[0]:
                candidate = strength, desired
        if candidate is None or candidate[0] < 1e-5:
            continue
        strength, desired = candidate
        combined = {name: weight * (1 - strength) for name, weight in old.items()}
        for name, weight in desired.items():
            combined[name] = combined.get(name, 0) + weight * strength
        selected = sorted(combined.items(), key=lambda pair: pair[1], reverse=True)[:4]
        total = sum(weight for _, weight in selected)
        for name in old:
            body.vertex_groups[name].remove([vertex.index])
        for name, weight in selected:
            if weight > 1e-8:
                body.vertex_groups[name].add([vertex.index], weight / total, 'REPLACE')
        modified += 1
    maximum_error = max(abs(sum(group.weight for group in vertex.groups) - 1)
                        for vertex in body.data.vertices)
    assert maximum_error < 1e-5
    print('FORM_LEG_RESKIN', {'vertices': modified, 'max_weight_error': maximum_error})
    return modified
