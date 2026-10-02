"""Replace the low-poly cat's sternum web with articulated rounded volumes.

Call rebuild_chest(body, rig, material) after source shaping and material setup,
before the common voxel fusion. The existing bone rest state is not modified.
"""
import math

import bpy
import bmesh
from mathutils import Vector


def _smooth(start, end, value):
    t = max(0.0, min(1.0, (value - start) / (end - start)))
    return t * t * (3.0 - 2.0 * t)


def _fraction(point, a, b):
    return max(0.0, min(1.0, (point - a).dot(b - a) / (b - a).length_squared))


def _mesh(name, vertices, faces, body):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.matrix_world = body.matrix_world.copy()
    return obj


def rebuild_chest(body, rig, material):
    """Cut the old chest web; join rounded, explicitly weighted replacement.

    The cut's sloping anterior roof protects the existing face and chin. Its
    lower edge preserves wrists and paws. Overlapping trunk, neck and shoulder
    volumes reconnect both boundaries before the caller's common skin fusion.
    """
    into_body = body.matrix_world.inverted() @ rig.matrix_world
    into_rig = into_body.inverted()
    original_bones = {
        bone.name: (bone.head_local.copy(), bone.tail_local.copy(), bone.length)
        for bone in rig.data.bones
    }
    original_count = len(body.data.vertices)
    # This removes the central sternum as well as the outer triangle. Merely
    # contracting foreleg-owned vertices leaves the neck-owned medial sheet.
    profile = [(.055, .078), (.055, .190), (.135, .210), (.155, .202),
               (.177, .179), (.195, .157), (.195, .078)]
    cutter_vertices = [into_body @ Vector((x, y, z))
                       for y in [-.090, .090] for x, z in profile]
    count = len(profile)
    cutter_faces = [tuple(reversed(range(count))), tuple(range(count, count * 2))]
    cutter_faces += [(i, (i + 1) % count, (i + 1) % count + count, i + count)
                     for i in range(count)]
    cutter = _mesh('Chest source web cutter', cutter_vertices, cutter_faces, body)
    bm = bmesh.new()
    bm.from_mesh(cutter.data)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(cutter.data)
    bm.free()
    bpy.ops.object.select_all(action='DESELECT')
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    cut = body.modifiers.new('Remove inherited sternum web', 'BOOLEAN')
    cut.operation = 'DIFFERENCE'
    cut.solver = 'EXACT'
    cut.object = cutter
    # Work on raw rest geometry, before any existing armature modifier. The
    # caller reapplies skin after voxel fusion, so this ordering is explicit.
    while body.modifiers[0] != cut:
        bpy.ops.object.modifier_move_up(modifier=cut.name)
    bpy.ops.object.modifier_apply(modifier=cut.name)
    bpy.data.objects.remove(cutter, do_unlink=True)
    retained_count = len(body.data.vertices)

    # Boolean cap vertices may lack source groups. They are internal after
    # fusion, but still receive normalized skin so nearest-surface transfer is
    # well-defined. Existing outside skin weights are left as authored.
    cap_vertices = 0
    for vertex in body.data.vertices:
        if sum(group.weight for group in vertex.groups) < 1e-7:
            body.vertex_groups.get('body_2').add([vertex.index], 1.0, 'REPLACE')
            cap_vertices += 1
    coat = body.data.color_attributes.get('Coat')
    if coat:
        for datum in coat.data:
            if datum.color[3] < .001:
                datum.color = material.diffuse_color

    additions = []
    added_count = 0
    def ellipsoid(name, center, radii, weights, direction=None, taper=None):
        nonlocal added_count
        rotation = (Vector(direction).to_track_quat('X', 'Z')
                    if direction is not None else None)
        vertices, points, faces = [], [], []
        rings, sides = 20, 32
        for ring in range(rings + 1):
            latitude = -math.pi / 2 + math.pi * ring / rings
            for side in range(sides):
                longitude = math.tau * side / sides
                lateral = 1.0
                if taper is not None:
                    longitudinal = (math.sin(latitude) + 1) * .5
                    lateral = 1 + (taper - 1) * _smooth(0, 1, longitudinal)
                local = Vector((math.sin(latitude) * radii[0],
                                math.cos(latitude) * math.cos(longitude) * radii[1] * lateral,
                                math.cos(latitude) * math.sin(longitude) * radii[2] * lateral))
                point = Vector(center) + (rotation @ local if rotation else local)
                points.append(point)
                vertices.append(into_body @ point)
        for ring in range(rings):
            for side in range(sides):
                a = ring * sides + side
                b = ring * sides + (side + 1) % sides
                faces.append((a, b, b + sides, a + sides))
        obj = _mesh(name, vertices, faces, body)
        obj.data.materials.append(material)
        attr = obj.data.color_attributes.new(name='Coat', type='FLOAT_COLOR', domain='POINT')
        for datum in attr.data:
            datum.color = material.diffuse_color
        for index, point in enumerate(points):
            values = weights(point)
            total = sum(values.values())
            for group, value in values.items():
                if value <= 0:
                    continue
                vg = obj.vertex_groups.get(group) or obj.vertex_groups.new(name=group)
                vg.add([index], value / total, 'REPLACE')
        for polygon in obj.data.polygons:
            polygon.use_smooth = True
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=1e-8)
        bmesh.ops.dissolve_degenerate(bm, edges=list(bm.edges), dist=1e-10)
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        bm.to_mesh(obj.data)
        bm.free()
        additions.append(obj)
        added_count += len(obj.data.vertices)

    # The thorax is a rounded barrel; its front pole curves upward instead of
    # extending a flat diagonal sheet down to the elbow.
    def thorax_weights(point):
        neck_share = .20 * _smooth(.125, .160, point.x) * _smooth(.165, .198, point.z)
        rear_share = .35 * (1 - _smooth(.050, .105, point.x))
        return {'body_1': rear_share, 'body_2': 1 - rear_share - neck_share,
                'neck': neck_share}
    ellipsoid('Rebuilt rounded thorax', (.071, -.000327, .165),
              (.100, .054, .044), thorax_weights)

    neck = rig.data.bones['neck']
    neck_a, neck_b = neck.head_local.copy(), neck.tail_local.copy()
    def neck_weights(point):
        t = _fraction(point, neck_a, neck_b)
        head_share = .28 * _smooth(.55, 1.0, t)
        torso_share = .45 * (1 - _smooth(0, .60, t))
        return {'body_2': torso_share, 'neck': 1 - torso_share - head_share,
                'head': head_share}
    ellipsoid('Rebuilt rising neck', (neck_a + neck_b) * .5,
              ((neck_b - neck_a).length * .5 + .012, .033, .026),
              neck_weights, direction=neck_b - neck_a)

    for side in ['left', 'right']:
        name = f'leg_front_{side}_1'
        bone = rig.data.bones[name]
        a, b = bone.head_local.copy(), bone.tail_local.copy()
        def shoulder_weights(point, a=a, b=b, side=side, name=name):
            t = _fraction(point, a, b)
            chest_share = .35 * (1 - _smooth(0, .40, t))
            elbow_share = .25 * _smooth(.55, 1, t)
            return {'body_2': chest_share, name: 1 - chest_share - elbow_share,
                    f'leg_front_{side}_2': elbow_share}
        ellipsoid(f'Rebuilt {side} articulated shoulder', (a + b) * .5,
                  ((b - a).length * .5 + .009, .016, .016),
                  shoulder_weights, direction=b - a, taper=.010 / .016)

    bpy.ops.object.select_all(action='DESELECT')
    body.select_set(True)
    for obj in additions:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()
    for name, (head, tail, length) in original_bones.items():
        bone = rig.data.bones[name]
        assert (bone.head_local - head).length < 1e-9
        assert (bone.tail_local - tail).length < 1e-9
        assert abs(bone.length - length) < 1e-9
    missing = sum(sum(group.weight for group in vertex.groups) < 1e-7
                  for vertex in body.data.vertices)
    assert missing == 0, 'Chest source skin contains an unweighted vertex'
    result = {'source_vertices_before_cut': original_count,
              'source_vertices_after_cut': retained_count,
              'replacement_vertices': added_count,
              'replacement_volumes': 4,
              'new_cap_vertices_weighted': cap_vertices,
              'unweighted_vertices': missing,
              'unchanged_bone_rest_state': True}
    print('CHEST_REBUILD', result)
    return result


def reskin_chest(body, rig):
    """Set coherent weights on the fused chest, avoiding Boolean-cap transfer.

    The generic nearest-point transfer cannot distinguish a new outer shoulder
    from a nearby internal cut cap. Soft union distances select the anatomical
    volume continuously and preserve source skin outside the replacement.
    """
    into_rig = rig.matrix_world.inverted() @ body.matrix_world
    neck = rig.data.bones['neck']
    neck_a, neck_b = neck.head_local.copy(), neck.tail_local.copy()
    neck_center = (neck_a + neck_b) * .5
    neck_rotation = (neck_b - neck_a).to_track_quat('X', 'Z').inverted()
    neck_radii = Vector(((neck_b - neck_a).length * .5 + .012, .033, .026))
    torso_center, torso_radii = Vector((.071, -.000327, .165)), Vector((.100, .054, .044))
    names = {group.index: group.name for group in body.vertex_groups}

    def ellipse_distance(point, center, radii, rotation=None):
        local = point - center
        if rotation is not None:
            local = rotation @ local
        return (Vector((local.x / radii.x, local.y / radii.y,
                        local.z / radii.z)).length - 1) * min(radii)

    modified = 0
    for vertex in body.data.vertices:
        point = into_rig @ vertex.co
        original = {names[group.group]: group.weight for group in vertex.groups}
        protected = sum(weight for name, weight in original.items()
                        if name.startswith(('head', 'ear_', 'leg_back_', 'tail_')))
        amount = (_smooth(.040, .055, point.x)
                  * (1 - _smooth(.181, .203, point.x))
                  # Cover the cut's .078 lower cap completely. Fading here
                  # left isolated cap vertices following the chest on a moving
                  # lower foreleg, producing actual visible spikes.
                  * _smooth(.045, .060, point.z)
                  * (1 - _smooth(.205, .224, point.z))
                  * (1 - _smooth(.060, .074, abs(point.y)))
                  * (1 - _smooth(.40, .75, protected)))
        if amount < 1e-5:
            continue
        neck_share = .20 * _smooth(.125, .160, point.x) * _smooth(.165, .198, point.z)
        rear_share = .35 * (1 - _smooth(.050, .105, point.x))
        candidates = [(ellipse_distance(point, torso_center, torso_radii),
                       {'body_1': rear_share, 'body_2': 1 - rear_share - neck_share,
                        'neck': neck_share})]
        t = _fraction(point, neck_a, neck_b)
        head_share = .28 * _smooth(.55, 1, t)
        torso_share = .45 * (1 - _smooth(0, .60, t))
        candidates.append((ellipse_distance(point, neck_center, neck_radii, neck_rotation),
                           {'body_2': torso_share, 'neck': 1 - torso_share - head_share,
                            'head': head_share}))
        for side in ['left', 'right']:
            name = f'leg_front_{side}_1'
            bone = rig.data.bones[name]
            a, b = bone.head_local, bone.tail_local
            t = _fraction(point, a, b)
            radius = .016 + (.010 - .016) * t
            distance = (point - a.lerp(b, t)).length - radius
            chest_share = .35 * (1 - _smooth(0, .40, t))
            elbow_share = .25 * _smooth(.55, 1, t)
            candidates.append((distance, {'body_2': chest_share,
                               name: 1 - chest_share - elbow_share,
                               f'leg_front_{side}_2': elbow_share}))
            lower = rig.data.bones[f'leg_front_{side}_2']
            lower_t = _fraction(point, lower.head_local, lower.tail_local)
            lower_distance = (point - lower.head_local.lerp(lower.tail_local, lower_t)).length - .010
            upper_share = .25 * (1 - _smooth(0, .30, lower_t))
            candidates.append((lower_distance, {name: upper_share,
                               f'leg_front_{side}_2': 1 - upper_share}))
        closest = min(distance for distance, _ in candidates)
        factors = [math.exp(max(-50, -(distance - closest) / .004))
                   for distance, _ in candidates]
        total = sum(factors)
        desired = {}
        for (_, values), factor in zip(candidates, factors):
            for name, value in values.items():
                desired[name] = desired.get(name, 0) + value * factor / total
        combined = {name: value * (1 - amount) for name, value in original.items()}
        for name, value in desired.items():
            combined[name] = combined.get(name, 0) + value * amount
        selected = sorted(combined.items(), key=lambda item: item[1], reverse=True)[:4]
        total = sum(value for _, value in selected)
        for name in original:
            body.vertex_groups[name].remove([vertex.index])
        for name, value in selected:
            if value > 1e-8:
                body.vertex_groups[name].add([vertex.index], value / total, 'REPLACE')
        modified += 1
    maximum_error = max(abs(sum(group.weight for group in vertex.groups) - 1)
                        for vertex in body.data.vertices)
    assert maximum_error < 1e-5
    result = {'vertices_reskinned': modified, 'maximum_weight_sum_error': maximum_error}
    print('CHEST_RESKIN', result)
    return result
