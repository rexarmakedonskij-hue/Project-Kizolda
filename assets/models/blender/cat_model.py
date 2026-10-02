"""Soft sculpted cat shapes using the approved palette and the square photo reference."""
from mathutils import Vector
import math


def build_cat(bpy, sphere, tube, mat, coord):
    coat = mat('Warm taupe coat', (.52, .43, .39))
    cream = mat('Cream chest', (.91, .86, .75))
    white = mat('White mittens', (.96, .93, .85))
    point = mat('Seal point markings', (.22, .17, .17))
    blue = mat('Icy blue irises', (.48, .72, .82))
    pupil = mat('Deep pupils', (.018, .025, .028))
    nose = mat('Velvet nose', (.16, .11, .12))
    pink = mat('Inner ear velvet', (.51, .31, .33))

    def union(name, pieces, voxel=.018):
        bpy.ops.object.select_all(action='DESELECT')
        for obj in pieces: obj.select_set(True)
        bpy.context.view_layer.objects.active = pieces[0]
        bpy.ops.object.join()
        obj = bpy.context.object
        obj.name = name
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        obj.data.remesh_voxel_size = voxel
        bpy.ops.object.voxel_remesh()
        smooth = obj.modifiers.new('Soft sculpt', 'SMOOTH')
        smooth.factor, smooth.iterations = .7, 4
        bpy.ops.object.modifier_apply(modifier=smooth.name)
        subdivision = obj.modifiers.new('Smooth skin', 'SUBSURF')
        subdivision.levels = 1
        bpy.ops.object.modifier_apply(modifier=subdivision.name)
        for face in obj.data.polygons: face.use_smooth = True
        return obj

    def painted(obj, name, color_fn):
        material = mat(name, (.7, .6, .5))
        shader = next(n for n in material.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
        colors = material.node_tree.nodes.new('ShaderNodeVertexColor')
        colors.layer_name = 'CoatColor'
        material.node_tree.links.new(colors.outputs['Color'], shader.inputs['Base Color'])
        obj.data.materials.clear()
        obj.data.materials.append(material)
        attribute = obj.data.color_attributes.new(name='CoatColor', type='FLOAT_COLOR', domain='POINT')
        for vertex, datum in zip(obj.data.vertices, attribute.data):
            world = obj.matrix_world @ vertex.co
            datum.color = (*color_fn(world.x, world.z, -world.y), 1)

    def blend(a, b, t):
        t = max(0, min(1, t))
        return tuple(x + (y-x)*t for x, y in zip(a, b))

    def tuft(name, start, end, width, material):
        a, b = Vector(coord(start)), Vector(coord(end))
        axis = (b-a).normalized()
        tangent = Vector((1, 0, 0))
        if abs(axis.dot(tangent)) > .9: tangent = Vector((0, 0, 1))
        across = (tangent - axis * tangent.dot(axis)).normalized()
        normal = axis.cross(across)
        vertices, faces = [], []
        rings = [(0, .65), (.25, 1), (.55, .8), (.82, .4), (1, .025)]
        for t, profile in rings:
            center = a.lerp(b, t) + normal * math.sin(math.pi*t) * width * .4
            for j in range(8):
                angle = j * math.tau / 8
                vertices.append(center + across * math.cos(angle) * width * profile + normal * math.sin(angle) * width * profile * .6)
        for row in range(4):
            for j in range(8):
                faces.append((row*8+j, row*8+(j+1)%8, (row+1)*8+(j+1)%8, (row+1)*8+j))
        faces += [tuple(reversed(range(8))), tuple(range(32, 40))]
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata(vertices, [], faces)
        mesh.materials.append(material)
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.collection.objects.link(obj)
        for face in mesh.polygons: face.use_smooth = True
        return obj

    body = union('Body', [sphere('Torso', (0, .48, -.025), (.66, .86, .61), coat),
                          sphere('Shoulders', (0, .77, .015), (.49, .38, .44), coat)])
    painted(body, 'Soft coat and chest', lambda x, y, z: blend((.52, .43, .39), (.91, .86, .75),
            (z-.12)*9 * max(0, 1-abs(x)/.26)))
    head = union('Head', [sphere('Skull', (0, 1.055, .035), (.65, .55, .52), cream),
                          sphere('Left cheek', (-.17, .985, .14), (.32, .28, .35), cream),
                          sphere('Right cheek', (.17, .985, .14), (.32, .28, .35), cream),
                          sphere('Muzzle left', (-.066, .965, .292), (.19, .14, .17), cream),
                          sphere('Muzzle right', (.066, .965, .292), (.19, .14, .17), cream)], .011)

    def head_color(x, y, z):
        mask = math.exp(-((x/.29)**4 + ((y-1.115)/.24)**4)) * max(0, min(1, (z-.10)*12))
        base = blend((.72, .66, .58), (.22, .17, .17), mask)
        muzzle = max(0, min(1, (.999-y)*30)) * max(0, min(1, (z-.23)*20))
        return blend(base, (.91, .86, .75), muzzle)
    painted(head, 'Blended seal point face', head_color)

    for side in [-1, 1]:
        # Rounded triangular shell, with a smaller inset velvet surface.
        vertices = [(side*.14, 1.15, .06), (side*.34, 1.18, .015), (side*.29, 1.48, .025),
                    (side*.14, 1.15, -.07), (side*.34, 1.18, -.08), (side*.29, 1.48, -.035)]
        mesh = bpy.data.meshes.new('Ear shell')
        mesh.from_pydata([coord(p) for p in vertices], [], [(0,1,2), (5,4,3), (0,3,4,1), (1,4,5,2), (2,5,3,0)])
        mesh.materials.append(point)
        ear = bpy.data.objects.new('Soft ear', mesh)
        bpy.context.collection.objects.link(ear)
        bevel = ear.modifiers.new('Rounded ear rim', 'BEVEL')
        bevel.width, bevel.segments = .028, 4
        for face in mesh.polygons: face.use_smooth = True
        tuft('Inner ear', (side*.24, 1.225, .071), (side*.29, 1.42, .044), .050, pink)
        for j in range(3):
            tuft('Ear fur', (side*(.18+j*.028), 1.215, .082), (side*(.22+j*.020), 1.28+j*.023, .09), .011, cream)
        # Eyes sit close to the head surface; lids define an almond contour.
        sphere('Eye', (side*.143, 1.084, .274), (.164, .153, .072), blue)
        sphere('Pupil', (side*.143, 1.084, .310), (.067, .116, .018), pupil)
        sphere('Catchlight', (side*.143-.023, 1.12, .324), (.026, .025, .012), white)
        sphere('Small catchlight', (side*.143+.023, 1.052, .321), (.012, .012, .009), white)
        tube('Upper eyelid', [(side*.055,1.065,.278), (side*.095,1.142,.287), (side*.17,1.154,.283), (side*.229,1.09,.240)], .011, point)
        tube('Lower eyelid', [(side*.055,1.065,.278), (side*.14,1.009,.28), (side*.229,1.09,.240)], .006, point)
        for j in range(5):
            tuft('Cheek fur', (side*.245, 1.025-j*.025, .13), (side*(.36-j*.008), 1.005-j*.033, .17), .035, coat if j < 2 else cream)
        sphere('Hind haunch', (side*.22, .285, -.045), (.32, .47, .37), coat)
        sphere('Hind sock', (side*.22, .18, .095), (.23, .28, .25), white)
        sphere('Back paw', (side*.22, .09, .15), (.255, .18, .35), white)
        for j in range(3):
            tube('Whisker', [(side*.10,.966,.366), (side*.24,.985-j*.027,.375), (side*.43,1.005-j*.042,.34)], .0025, white)
    nose_obj = sphere('Nose', (0, .997, .377), (.081, .048, .032), nose)
    for vertex in nose_obj.data.vertices:
        vertex.co.x *= .6 + .4 * (vertex.co.z + 1) / 2
    tube('Philtrum', [(0,.98,.379),(0,.95,.374)], .0035, nose)
    for side in [-1, 1]:
        tube('Mouth curve', [(0,.95,.374),(side*.035,.938,.367),(side*.073,.952,.359)], .003, nose)
    for row in range(5):
        y = .82-row*.082
        width = .16 + .045*math.sin(row*.9)
        for col in range(-2, 3):
            x = col*width/2.5 + .012*math.sin(row*2.3+col)
            z = .23 + .055*math.sin(row*.7)
            stagger = .022*math.sin(row+col*2.2)
            length = .12 + .025*math.cos(col+row)
            tuft('Chest ruff', (x, y+stagger, z), (x*.86, y-length+stagger, z+.023), .029, cream)
    tail = tube('Curled tail', [(0,.22,-.25),(.32,.20,-.58),(.60,.18,-.32),(.59,.15,.035),(.39,.145,.20)], .125, point)
    for face in tail.data.polygons: face.use_smooth = True
    for j in range(7):
        tuft('Curled tail fluff', (.52,.17,-.38+j*.07), (.68,.16,-.35+j*.07), .055, point)
    return point, white
