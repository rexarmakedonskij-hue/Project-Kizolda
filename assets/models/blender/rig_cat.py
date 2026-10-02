"""Build the cat's editable armature and baked scratch loop; called by build_mvp.py."""
from mathutils import Vector, Matrix, Euler


def rig_cat(bpy, math, sphere, coord, point_fur, white_fur):
    def point(x, y, z):
        return Vector(coord((x, y, z)))

    def arm_points(side, phase, drop=0.0):
        # Slow lift, two-frame hold, fast drag, relaxed return. 30 fps / 40 frames.
        keys = [(0, .76, .30), (.35, 1.12, .44), (.40, 1.12, .44),
                (.60, .72, .44), (.76, .68, .30), (1, .76, .30)]
        for a, b in zip(keys, keys[1:]):
            if a[0] <= phase <= b[0]:
                t = (phase - a[0]) / (b[0] - a[0])
                # Drag starts immediately; recovery and lift have eased endpoints.
                if a[0] != .40:
                    t = t * t * (3 - 2 * t)
                height, reach = a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t
                break
        shoulder = point(side * .25, .75 + drop, .10)
        paw = point(side * .29, height, reach)
        axis = (paw - shoulder).normalized()
        outward = Vector((side, 0, 0))
        bend = (outward - axis * outward.dot(axis)).normalized()
        distance = (paw - shoulder).length
        elbow = (paw + shoulder) / 2 + bend * math.sqrt(max(0, .35 ** 2 - (distance / 2) ** 2))
        return shoulder, elbow, paw

    for obj in list(bpy.context.scene.objects):
        if obj.name.startswith('Front paw'):
            bpy.data.objects.remove(obj, do_unlink=True)
    pieces = list(bpy.context.scene.objects)
    bpy.ops.object.armature_add()
    rig = bpy.context.object
    rig.name = 'CatRig'
    rig.show_in_front = True
    bpy.ops.object.mode_set(mode='EDIT')
    rig.data.edit_bones.remove(rig.data.edit_bones[0])

    def bone(name, head, tail, parent='root'):
        item = rig.data.edit_bones.new(name)
        item.head, item.tail = head, tail
        if parent:
            item.parent = rig.data.edit_bones[parent]

    bone('root', point(0, 0, 0), point(0, .2, 0), None)
    bone('body', point(0, .3, 0), point(0, .8, 0))
    bone('head', point(0, .85, .035), point(0, 1.25, .035), 'body')
    bone('tail', point(0, .22, -.22), point(.35, .65, -.6))
    rest = {}
    for side, suffix in [(-1, 'L'), (1, 'R')]:
        a, b, c = arm_points(side, 0 if side == -1 else .5)
        rest[suffix] = (a, b, c)
        bone('upper_' + suffix, a, b)
        bone('fore_' + suffix, b, c)
        bone('paw_' + suffix, c, c + point(0, .13, 0))
        bone('hind_' + suffix, point(side * .22, .29, -.03), point(side * .22, .09, .15))
    bpy.ops.object.mode_set(mode='OBJECT')

    def bind(obj, name):
        bpy.ops.object.select_all(action='DESELECT')
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        group = obj.vertex_groups.new(name=name)
        group.add(list(range(len(obj.data.vertices))), 1.0, 'REPLACE')
        modifier = obj.modifiers.new('Cat skeleton', 'ARMATURE')
        modifier.object = rig
        obj.parent = rig

    for obj in pieces:
        name = (('hind_L' if obj.location.x < 0 else 'hind_R') if obj.name.startswith(('Back paw', 'Hind sock', 'Hind haunch'))
                else 'tail' if obj.name.startswith(('Curled tail', 'Tail tip'))
                else 'body' if obj.name.startswith(('Body', 'Belly', 'Chest ruff'))
                else 'head')
        bind(obj, name)
    for side, suffix in [(-1, 'L'), (1, 'R')]:
        a, b, c = rest[suffix]
        for name, start, end in [('upper_', a, b), ('fore_', b, c)]:
            middle = (start + end) / 2
            obj = sphere(name + suffix, (middle.x, middle.z, -middle.y), (.18, (end-start).length + .08, .18), point_fur)
            obj.rotation_mode = 'QUATERNION'
            obj.rotation_quaternion = (end-start).to_track_quat('Z', 'Y')
            bind(obj, name + suffix)
        paw = sphere('Paw_' + suffix, (c.x, c.z, -c.y), (.21, .18, .15), white_fur)
        bind(paw, 'paw_' + suffix)

    bpy.context.view_layer.objects.active = rig
    rig.animation_data_create()
    action = bpy.data.actions.new('Scratch')
    rig.animation_data.action = action
    scene = bpy.context.scene
    scene.render.fps = 30
    scene.frame_start, scene.frame_end = 1, 41
    for frame in range(1, 42):
        phase = (frame - 1) / 40
        drop = -.025 * (1 - math.cos(phase * math.tau * 2))
        for name in ['hind_L', 'hind_R']:
            p = rig.pose.bones[name]
            p.rotation_mode = 'QUATERNION'
            p.location = (0, 0, 0)
            p.rotation_quaternion = (1, 0, 0, 0)
            p.scale = (1, 1, 1)
            for prop in ['location', 'rotation_quaternion', 'scale']:
                p.keyframe_insert(prop, frame=frame)
        for name in ['body', 'head', 'tail']:
            p = rig.pose.bones[name]
            p.rotation_mode = 'QUATERNION'
            p.location = (0, drop, 0) if name == 'body' else (0, 0, 0)
            p.rotation_quaternion = Euler((0, 0, .08 * math.sin(phase * math.tau)) if name == 'tail' else (0, 0, 0)).to_quaternion()
            p.keyframe_insert('location', frame=frame)
            p.keyframe_insert('rotation_quaternion', frame=frame)
        for side, suffix in [(-1, 'L'), (1, 'R')]:
            a, b, c = arm_points(side, (phase + (0 if side == -1 else .5)) % 1, drop)
            for name, start, end in [('upper_', a, b), ('fore_', b, c), ('paw_', c, c + point(0, .13, 0))]:
                p = rig.pose.bones[name + suffix]
                p.rotation_mode = 'QUATERNION'
                p.matrix = Matrix.Translation(start) @ (end-start).to_track_quat('Y', 'Z').to_matrix().to_4x4()
                p.keyframe_insert('location', frame=frame)
                p.keyframe_insert('rotation_quaternion', frame=frame)
                p.keyframe_insert('scale', frame=frame)
    scratch_action = action
    rig.animation_data.action = bpy.data.actions.new('Walk')
    for p in rig.pose.bones:
        p.matrix_basis = Matrix.Identity(4)
    for frame in range(1, 26):
        phase = (frame - 1) / 24
        sway = .012 * math.sin(phase * math.tau * 2)
        for name in ['body', 'head', 'tail']:
            p = rig.pose.bones[name]
            p.rotation_mode = 'QUATERNION'
            p.location = (0, sway, 0) if name == 'body' else (0, 0, 0)
            p.rotation_quaternion = Euler((math.pi / 3, 0, 0) if name == 'body'
                                else (-math.pi / 3, 0, 0) if name == 'head'
                                else (0, 0, .10 * math.sin(phase * math.tau))).to_quaternion()
            p.keyframe_insert('location', frame=frame)
            p.keyframe_insert('rotation_quaternion', frame=frame)
        for side, suffix in [(-1, 'L'), (1, 'R')]:
            step = (phase + (0 if side == -1 else .5)) % 1
            # Diagonal pairs: planted feet travel backwards while the cat moves forwards.
            stride = .16 - .64 * step if step < .5 else -.16 + .64 * (step - .5)
            lift = .10 * math.sin((step - .5) * math.tau) if step >= .5 else 0
            shoulder = point(side * .25, .55 + sway, .39)
            paw = point(side * .29, .10 + lift, .60 + stride)
            axis = (paw - shoulder).normalized()
            outward = Vector((side, 0, 0))
            bend = (outward - axis * outward.dot(axis)).normalized()
            elbow = (paw + shoulder) / 2 + bend * math.sqrt(max(0, .35 ** 2 - ((paw - shoulder).length / 2) ** 2))
            for name, start, end in [('upper_', shoulder, elbow), ('fore_', elbow, paw), ('paw_', paw, paw + point(0, .13, 0))]:
                p = rig.pose.bones[name + suffix]
                p.rotation_mode = 'QUATERNION'
                p.matrix = Matrix.Translation(start) @ (end-start).to_track_quat('Y', 'Z').to_matrix().to_4x4()
                for prop in ['location', 'rotation_quaternion', 'scale']:
                    p.keyframe_insert(prop, frame=frame)
            p = rig.pose.bones['hind_' + suffix]
            p.rotation_mode = 'QUATERNION'
            p.location = (0, 0, 0)
            p.rotation_quaternion = (1, 0, 0, 0)
            hind_step = (step + .5) % 1
            hind_stride = .16 - .64 * hind_step if hind_step < .5 else -.16 + .64 * (hind_step - .5)
            hind_lift = .10 * math.sin((hind_step - .5) * math.tau) if hind_step >= .5 else 0
            p.matrix = Matrix.Translation(point(0, hind_lift, -.20 + hind_stride)) @ p.bone.matrix_local
            for prop in ['location', 'rotation_quaternion', 'scale']:
                p.keyframe_insert(prop, frame=frame)
    walk_action = rig.animation_data.action
    scene.frame_set(1)
    walk_pose = {p.name: p.matrix_basis.copy() for p in rig.pose.bones}
    rig.animation_data.action = bpy.data.actions.new('Jump')
    for frame, squash in [(1, .82), (7, 1.06), (14, 1.02), (19, .88), (21, 1.0)]:
        for p in rig.pose.bones:
            p.matrix_basis = walk_pose[p.name]
            p.rotation_mode = 'QUATERNION'
            if p.name == 'root': p.scale.y = squash
            for prop in ['location', 'rotation_quaternion', 'scale']:
                p.keyframe_insert(prop, frame=frame)
    for clip in ['Sit', 'Swipe']:
        rig.animation_data.action = bpy.data.actions.new(clip)
        for p in rig.pose.bones: p.matrix_basis = Matrix.Identity(4)
        for frame in range(1, 32):
            phase = (frame - 1) / 30
            for p in rig.pose.bones:
                p.matrix_basis = Matrix.Identity(4)
                p.rotation_mode = 'QUATERNION'
            for side, suffix in [(-1, 'L'), (1, 'R')]:
                reach = .22
                height = .14
                lateral = side * .29
                if clip == 'Swipe' and side == -1:
                    lift = math.sin(min(1, phase / .35) * math.pi / 2) if phase <= .35 else max(0, 1 - (phase - .35) / .45)
                    height += .17 * lift
                    reach += .22 * lift
                    lateral += .29 * lift
                a = point(side * .25, .75, .1)
                c = point(lateral, height, reach)
                axis = (c-a).normalized()
                outward = Vector((side, 0, 0))
                bend = (outward - axis * outward.dot(axis)).normalized()
                b = (a+c) / 2 + bend * math.sqrt(max(0, .35 ** 2 - ((c-a).length / 2) ** 2))
                for name, start, end in [('upper_', a, b), ('fore_', b, c), ('paw_', c, c + point(0, .13, 0))]:
                    rig.pose.bones[name + suffix].matrix = Matrix.Translation(start) @ (end-start).to_track_quat('Y', 'Z').to_matrix().to_4x4()
            for p in rig.pose.bones:
                for prop in ['location', 'rotation_quaternion', 'scale']:
                    p.keyframe_insert(prop, frame=frame)
    rig.animation_data.action = scratch_action
    for p in rig.pose.bones:
        p.matrix_basis = Matrix.Identity(4)
    scene.frame_set(1)
