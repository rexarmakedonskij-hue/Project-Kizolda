"""Round the source cat's shoulder attachment before anatomical mesh fusion.

The imported skin contains a broad flat web between the ventral chest and each
foreleg. Adding cylinders over it does not remove that silhouette. This pass
reshapes that skin in rig rest space; it never changes bones or skin weights.
"""
import math

from mathutils import Vector


def _smooth(start, end, value):
    fraction = max(0.0, min(1.0, (value - start) / (end - start)))
    return fraction * fraction * (3 - 2 * fraction)


def sculpt_shoulders(body, rig):
    """Mutate only the source-body shoulder/web coordinates, returning metrics.

    Call after source per-vertex shaping and before joining/remeshing additions.
    Chest, shoulder and elbow blend continuously. Face, paw, hindquarter and
    dorsal surfaces are outside the sculpt; existing colors/groups are retained.
    """
    into_rig = rig.matrix_world.inverted() @ body.matrix_world
    into_body = into_rig.inverted()
    group_names = {group.index: group.name for group in body.vertex_groups}
    shoulders = {}
    for side in ['left', 'right']:
        bone = rig.data.bones[f'leg_front_{side}_1']
        shoulders[side] = (bone.head_local.copy(), bone.tail_local.copy())
    spine = rig.data.bones['body_2']
    spine_start, spine_end = spine.head_local, spine.tail_local
    neck = rig.data.bones['neck']
    chest_center_y = (spine_start.y + spine_end.y) / 2
    elbow_x = sum(end.x for _, end in shoulders.values()) / 2
    shoulder_z = sum(start.z for start, _ in shoulders.values()) / 2
    modified, web_modified, maximum = 0, 0, 0.0

    for vertex in body.data.vertices:
        original = into_rig @ vertex.co
        weights = {group_names[group.group]: group.weight for group in vertex.groups}
        front = sum(weight for name, weight in weights.items()
                    if name.startswith('leg_front_'))
        protected = sum(weight for name, weight in weights.items()
                        if name.startswith(('head', 'ear_', 'leg_back_', 'tail_')))
        # A neck-dominant throat remains intact; a mixed body/foreleg attachment
        # still participates, unlike the earlier leg-only radial contraction.
        # The unwanted lower chest is partly neck-owned. A bone-weight-only
        # mask misses that surface even when its position lies below the neck.
        # Give the lower anterior thorax geometric ownership, tapering away
        # before head, dorsal neck, or lateral body surfaces are reached.
        lower_chest = (_smooth(.112, .132, original.x)
                       * (1 - _smooth(.173, .195, original.x))
                       * (1 - _smooth(.164, .188, original.z))
                       * (1 - _smooth(.045, .060,
                                      abs(original.y - chest_center_y))))
        ownership = max(_smooth(.08, .42, front), lower_chest)
        ownership *= 1 - _smooth(.20, .55, protected)
        longitudinal = (_smooth(elbow_x - .065, elbow_x - .045, original.x)
                        * (1 - _smooth(elbow_x + .070, elbow_x + .100, original.x)))
        vertical = (_smooth(.065, .083, original.z)
                    * (1 - _smooth(shoulder_z + .024, shoulder_z + .051, original.z)))
        strength = ownership * longitudinal * vertical
        if strength < .00001:
            continue
        side = max(shoulders, key=lambda candidate: sum(
            weight for name, weight in weights.items()
            if name.startswith(f'leg_front_{candidate}_')))
        start, end = shoulders[side]
        axis = end - start
        fraction = max(0.0, min(1.0, (original - start).dot(axis) / axis.length_squared))
        center = start + axis * fraction
        radial = original - center
        distance = radial.length
        # A rounded shoulder tapers to the elbow, with no abrupt collar.
        radius = .023 + (.013 - .023) * _smooth(0, 1, fraction)
        point = original.copy()

        # Keep the underside of the trunk where it belongs instead of drawing
        # its mixed-weight web forward into the arm. The actual upper-leg tube
        # is excluded from this lift by radial distance and medial position.
        spine_fraction = max(0.0, min(1.0,
            (original.x - spine_start.x) / (spine_end.x - spine_start.x)))
        spine_z = spine_start.z + (spine_end.z - spine_start.z) * spine_fraction
        # The chest continues into an ascending neck. Clamping its floor at
        # body_2's endpoint left the forward diagonal sheet completely intact.
        neck_fraction = max(0.0, min(1.0,
            (original.x - neck.head_local.x)
            / (neck.tail_local.x - neck.head_local.x)))
        if original.x > neck.head_local.x:
            spine_z = neck.head_local.z + (
                neck.tail_local.z - neck.head_local.z) * neck_fraction
        lateral = min(.99, abs(original.y - chest_center_y) / .056)
        depth = .042 + (.035 - .042) * _smooth(0, 1, neck_fraction)
        ventral_z = spine_z - depth * math.sqrt(1 - lateral * lateral)
        behind = 1 - _smooth(elbow_x - .022, elbow_x + .002, original.x)
        medial = 1 - _smooth(.010, .022, abs(original.y - chest_center_y))
        off_leg = _smooth(.002, .016, distance - radius)
        # Rear and medial web is returned to the trunk. The forward lateral
        # sheet belongs to the arm contour instead: lifting it alone retains
        # a diagonal sheet from throat to elbow even though the belly improves.
        web = max(behind, medial) * off_leg
        if point.z < ventral_z and web > .00001:
            point.z += (ventral_z - point.z) * strength * web
            web_modified += 1

        # Shape the limb's side surfaces around its anatomical upper segment.
        # Fade into the rear chest, and retain the lifted trunk surface above.
        limb = _smooth(elbow_x - .023, elbow_x + .004, original.x) * (1 - web)
        limb_strength = strength * limb
        if distance > .00001 and limb_strength > .00001:
            target = center + radial.normalized() * radius
            point = point.lerp(target, limb_strength)
        difference = (point - original).length
        if difference > .000001:
            vertex.co = into_body @ point
            modified += 1
            maximum = max(maximum, difference)

    result = {'shoulder_vertices_sculpted': modified,
              'ventral_web_vertices_sculpted': web_modified,
              'maximum_rest_space_displacement': maximum}
    print('SHOULDER_SCULPT', result)
    return result
