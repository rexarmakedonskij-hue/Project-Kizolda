"""CPU-only anatomical and skin diagnostics for a generated cat .blend file.

Run with Blender --background model.blend --python analyze_cat_form.py -- report.json.
"""
import json
import math
import sys
from collections import Counter, deque
from pathlib import Path

import bpy
from mathutils import Vector


def percentile(values, fraction):
    if not values:
        return None
    values = sorted(values)
    return values[round((len(values) - 1) * fraction)]


def component_labels(mesh):
    links = [[] for _ in mesh.vertices]
    for edge in mesh.edges:
        a, b = edge.vertices
        links[a].append(b)
        links[b].append(a)
    labels = [-1] * len(mesh.vertices)
    sizes = []
    for seed in range(len(mesh.vertices)):
        if labels[seed] >= 0:
            continue
        label = len(sizes)
        queue = deque([seed])
        labels[seed] = label
        size = 0
        while queue:
            a = queue.popleft()
            size += 1
            for b in links[a]:
                if labels[b] < 0:
                    labels[b] = label
                    queue.append(b)
        sizes.append(size)
    return labels, sizes


body = bpy.data.objects['mesh_cat']
rig = next(obj for obj in bpy.data.objects if obj.type == 'ARMATURE')
mesh = body.data
labels, sizes = component_labels(mesh)
core = max(range(len(sizes)), key=sizes.__getitem__)
group_names = {group.index: group.name for group in body.vertex_groups}
in_core = [labels[i] == core for i in range(len(mesh.vertices))]
weights = [sum(group.weight for group in vertex.groups) for vertex in mesh.vertices]
edge_faces = Counter()
for face in mesh.polygons:
    if labels[face.vertices[0]] != core:
        continue
    vertices = face.vertices
    for i in range(len(vertices)):
        edge_faces[tuple(sorted((vertices[i], vertices[(i + 1) % len(vertices)])))] += 1

bone_names = ['pelvis', 'body_1', 'body_2', 'neck', 'head']
for limb in ['front', 'back']:
    for side in ['left', 'right']:
        bone_names.extend(f'leg_{limb}_{side}_{i}' for i in range(1, 5))
bones = {name: {
    'head': list(rig.data.bones[name].head_local),
    'tail': list(rig.data.bones[name].tail_local),
} for name in bone_names}

sections = {}
into_rig = rig.matrix_world.inverted() @ body.matrix_world
for limb in ['front', 'back']:
    for side in ['left', 'right']:
        for segment in [1, 2, 3]:
            name = f'leg_{limb}_{side}_{segment}'
            bone = rig.data.bones[name]
            a, b = bone.head_local, bone.tail_local
            axis = (b - a).normalized()
            center = a.lerp(b, .5)
            radial_distances = []
            max_owner = []
            for vertex in mesh.vertices:
                if not in_core[vertex.index]:
                    continue
                p = into_rig @ vertex.co
                projection = (p - center).dot(axis)
                radial = (p - center - axis * projection).length
                if abs(projection) > min(.009, bone.length * .14) or radial > .033:
                    continue
                groups = sorted(vertex.groups, key=lambda item: item.weight, reverse=True)
                owner = group_names[groups[0].group] if groups else ''
                if owner.startswith(f'leg_{limb}_{side}_'):
                    radial_distances.append(radial)
                    max_owner.append(groups[0].weight)
            sections[name] = {
                'sample_vertices': len(radial_distances),
                'radial_p10': percentile(radial_distances, .1),
                'radial_median': percentile(radial_distances, .5),
                'radial_p90': percentile(radial_distances, .9),
                'owner_weight_median': percentile(max_owner, .5),
            }

focus = {}
for limb in ['front', 'back']:
    for side in ['left', 'right']:
        key = f'{limb}_{side}'
        indices = set()
        for vertex in mesh.vertices:
            if not in_core[vertex.index]:
                continue
            p = into_rig @ vertex.co
            if limb == 'front':
                inside = .070 < p.x < .155 and .018 < p.z < .155
            else:
                inside = -.16 < p.x < -.07 and .018 < p.z < .17
            if inside and ((p.y > .008) if side == 'left' else (p.y < -.008)):
                indices.add(vertex.index)
        focus[key] = indices

rest_positions = [body.matrix_world @ v.co for v in mesh.vertices]
pose_ratios = {key: [] for key in focus}
pose_max = {key: (0, -1, 0, 0) for key in focus}
for frame in [1, 10, 19, 28, 37]:
    bpy.context.scene.frame_set(frame)
    bpy.context.view_layer.update()
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = body.evaluated_get(depsgraph)
    posed_mesh = evaluated.to_mesh()
    posed = [evaluated.matrix_world @ v.co for v in posed_mesh.vertices]
    for edge in mesh.edges:
        a, b = edge.vertices
        if not in_core[a] or not in_core[b]:
            continue
        rest = (rest_positions[a] - rest_positions[b]).length
        if rest < 1e-7:
            continue
        ratio = (posed[a] - posed[b]).length / rest
        for key, indices in focus.items():
            if a in indices and b in indices:
                pose_ratios[key].append(ratio)
                if ratio > pose_max[key][0]:
                    pose_max[key] = (ratio, frame, a, b)
    evaluated.to_mesh_clear()

result = {
    'asset': bpy.data.filepath,
    'vertices': len(mesh.vertices),
    'triangles': sum(len(poly.vertices) - 2 for poly in mesh.polygons),
    'bones': len(rig.data.bones),
    'core_vertices': sizes[core],
    'core_boundary_edges': sum(count == 1 for count in edge_faces.values()),
    'core_nonmanifold_edges': sum(count != 2 for count in edge_faces.values()),
    'component_sizes_largest': sorted(sizes, reverse=True)[:10],
    'unweighted_vertices': sum(value < 1e-7 for value in weights),
    'weight_sum_max_error': max(abs(value - 1) for value in weights),
    'max_influences': max(len(vertex.groups) for vertex in mesh.vertices),
    'bones_rest': bones,
    'sections': sections,
    'deformation': {key: {
        'edge_samples': len(values),
        'stretch_p99': percentile(values, .99),
        'stretch_p999': percentile(values, .999),
        'stretch_max': pose_max[key],
    } for key, values in pose_ratios.items()},
}
destination = next((Path(arg) for arg in reversed(sys.argv) if arg.endswith('.json')), None)
if destination:
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(result, indent=2), encoding='utf-8')
print('CAT_FORM_DIAGNOSTICS', json.dumps({key: result[key] for key in ['vertices', 'triangles', 'bones', 'core_vertices', 'core_boundary_edges', 'core_nonmanifold_edges', 'unweighted_vertices', 'weight_sum_max_error', 'max_influences']}))
