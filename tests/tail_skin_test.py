"""Verify real tail deformation without modifying the saved Blender asset.

Run Blender --background --python tests/tail_skin_test.py -- --review-pass=pass5.
Selections use rest-space anatomy, so a remesh cannot silently invalidate the
test through changed vertex indices. Armature evaluation is the evidence;
matching bone positions alone would miss a tail that also drags the haunch.
"""
from pathlib import Path
import hashlib
import json
import math
import sys

import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]
model_name = next((a.split('=', 1)[1] for a in sys.argv
                   if a.startswith('--model-name=')), 'cat_reference')
SOURCE = ROOT / f'assets/models/blender/{model_name}.blend'
FBX = ROOT / f'assets/models/glb/godot_mvp/{model_name}.fbx'
GAME_SCALE = 1.65
RUMP_LIMIT_M = .003
review_pass = next((a.split('=', 1)[1] for a in sys.argv
                    if a.startswith('--review-pass=')), 'pass5')
report_path = ROOT / f'tests/results/tail-skin-{review_pass}.json'
report = {
    'passed': False,
    'blend_sha256': hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
    'fbx_sha256': hashlib.sha256(FBX.read_bytes()).hexdigest(),
    'game_scale': GAME_SCALE,
    'rump_displacement_limit_m': RUMP_LIMIT_M,
    'selection': {
        'rump': 'distance to rest tail > .035; tail-root x minus .03 to plus .10; z above root minus .10',
        'shaft': 'distance to rest tail < .016; arc after .04 and before tip minus .02',
    },
    'states': {},
}


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def nearest_tail(point, segments):
    candidates = []
    for a, b, start, length in segments:
        axis = b - a
        fraction = max(0, min(1, (point - a).dot(axis) / axis.length_squared))
        candidates.append(((point - (a + axis * fraction)).length,
                           start + fraction * length))
    return min(candidates, key=lambda item: item[0])


try:
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    rig = next(obj for obj in bpy.context.scene.objects if obj.type == 'ARMATURE')
    mesh_object = bpy.data.objects['mesh_cat']
    rig.animation_data_clear()
    rig.data.pose_position = 'POSE'
    for bone in rig.pose.bones:
        for constraint in bone.constraints:
            constraint.influence = 0
        bone.matrix_basis = Matrix.Identity(4)
    if mesh_object.data.shape_keys:
        for key in mesh_object.data.shape_keys.key_blocks:
            key.value = 0
    bpy.context.view_layer.update()
    require(any(modifier.type == 'ARMATURE' and modifier.object == rig
                for modifier in mesh_object.modifiers),
            'The test requires actual Armature deformation of the game mesh')

    groups = {group.index: group.name for group in mesh_object.vertex_groups}
    bone_names = set(rig.data.bones.keys())
    max_sum_error = 0.0
    for vertex in mesh_object.data.vertices:
        require(all(math.isfinite(value) for value in vertex.co),
                f'Invalid coordinate at vertex {vertex.index}')
        total = 0.0
        for group in vertex.groups:
            require(math.isfinite(group.weight) and 0 <= group.weight <= 1,
                    f'Invalid weight at vertex {vertex.index}')
            if group.weight > 0:
                require(groups[group.group] in bone_names,
                        f'Nonzero weight refers to missing bone at vertex {vertex.index}')
            total += group.weight
        max_sum_error = max(max_sum_error, abs(total - 1))
    require(max_sum_error < .00001, 'Every mesh vertex must have normalized nonzero weights')
    report['vertices_checked'] = len(mesh_object.data.vertices)
    report['maximum_weight_sum_error'] = max_sum_error

    segments = []
    tail_length = 0.0
    for name in ['tail_1', 'tail_2', 'tail_3', 'tail_4', 'tail_4_end']:
        bone = rig.data.bones[name]
        a, b = bone.head_local.copy(), bone.tail_local.copy()
        length = (b - a).length
        require(length > 0, 'Tail bones must have nonzero length')
        segments.append((a, b, tail_length, length))
        tail_length += length
    tail_root = segments[0][0]
    into_rig = rig.matrix_world.inverted() @ mesh_object.matrix_world
    rump, shaft = [], []
    for vertex in mesh_object.data.vertices:
        point = into_rig @ vertex.co
        distance, arc = nearest_tail(point, segments)
        if (distance > .035 and tail_root.x - .03 < point.x < tail_root.x + .10
                and point.z > tail_root.z - .10):
            rump.append(vertex.index)
        if distance < .016 and .04 < arc < tail_length - .02:
            shaft.append(vertex.index)
    require(len(rump) > 100, 'Geometric rump selection must cover an anatomical region')
    require(len(shaft) > 50, 'Geometric shaft selection must contain real tail skin')
    report['rump_vertices'] = len(rump)
    report['shaft_vertices'] = len(shaft)

    def evaluated_points():
        bpy.context.view_layer.update()
        evaluated = mesh_object.evaluated_get(bpy.context.evaluated_depsgraph_get())
        mesh = evaluated.to_mesh()
        try:
            require(len(mesh.vertices) == len(mesh_object.data.vertices),
                    'Evaluation must preserve vertex correspondence')
            transform = rig.matrix_world.inverted() @ evaluated.matrix_world
            points = [transform @ vertex.co for vertex in mesh.vertices]
            require(all(math.isfinite(value) for point in points for value in point),
                    'Armature produced invalid vertex coordinates')
            return points
        finally:
            evaluated.to_mesh_clear()

    baseline = evaluated_points()
    tail = rig.pose.bones['tail_1']
    rest = tail.matrix.copy()
    original = (segments[0][1] - tail_root).normalized()
    goals = {
        'raised': Vector((-math.cos(1.15), 0, math.sin(1.15))),
        'seated': Vector((-math.cos(.85) * math.cos(-.7),
                          -math.sin(.85) * math.cos(-.7), math.sin(-.7))),
    }
    for state, direction in goals.items():
        for bone in rig.pose.bones:
            bone.matrix_basis = Matrix.Identity(4)
        bpy.context.view_layer.update()
        placed = original.rotation_difference(direction).to_matrix().to_4x4() @ rest
        placed.translation = tail_root
        tail.matrix = placed
        posed = evaluated_points()
        displacements = [(point - before).length * GAME_SCALE
                         for point, before in zip(posed, baseline)]
        rump_max = max(displacements[index] for index in rump)
        shaft_values = sorted(displacements[index] for index in shaft)
        shaft_median = shaft_values[len(shaft_values) // 2]
        report['states'][state] = {
            'maximum_rump_displacement_m': rump_max,
            'median_shaft_displacement_m': shaft_median,
            'maximum_shaft_displacement_m': shaft_values[-1],
            'rump_vertices_over_limit': sum(displacements[index] >= RUMP_LIMIT_M for index in rump),
        }
        require(rump_max < RUMP_LIMIT_M,
                f'{state} tail pulls the off-tail rump by {rump_max:.6f} m')
        require(shaft_median > .03,
                f'{state} test did not demonstrably deform the tail shaft')
    report['passed'] = True
    print('TAIL_SKIN_TEST_OK', json.dumps(report['states']))
except Exception as error:
    report['error'] = str(error)
    raise
finally:
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2), encoding='utf-8')
