"""Reduce groom geometry in a separate game candidate, preserving source and rig."""
import bpy
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
OUT = ROOT / 'builds/b3-rig-review'
bpy.ops.wm.open_mainfile(filepath=str(OUT / 'B3-rig-review.blend'))
report = []
for obj in list(bpy.data.objects):
    if obj.type != 'MESH' or 'groom fibers' not in obj.name:
        continue
    old = obj.data
    assert len(old.vertices) % 18 == 0, obj.name
    # Each original strand consists of six triangular rings. Keep its curved
    # centreline at root, middle and tip, keeping alternate whole strands.
    indices = [strand * 18 + ring * 3 + side
               for strand in range(0, len(old.vertices) // 18, 2)
               for ring in (0, 2, 5) for side in range(3)]
    vertices = [old.vertices[i].co[:] for i in indices]
    faces = [(base + ring * 3 + side, base + ring * 3 + (side + 1) % 3,
              base + (ring + 1) * 3 + (side + 1) % 3, base + (ring + 1) * 3 + side)
             for base in range(0, len(indices), 9) for ring in range(2) for side in range(3)]
    mesh = bpy.data.meshes.new(old.name + '_game')
    mesh.from_pydata(vertices, [], faces)
    for material in old.materials:
        mesh.materials.append(material)
    for attr in old.color_attributes:
        assert attr.domain == 'POINT', obj.name
        target = mesh.color_attributes.new(name=attr.name, type=attr.data_type, domain='POINT')
        target.data.foreach_set('color', [channel for i in indices for channel in attr.data[i].color])
    weights = {}
    for target_index, source_index in enumerate(indices):
        for group in old.vertices[source_index].groups:
            weights.setdefault((group.group, group.weight), []).append(target_index)
    group_names = [group.name for group in obj.vertex_groups]
    obj.data = mesh
    obj.vertex_groups.clear()
    for name in group_names:
        obj.vertex_groups.new(name=name)
    for (group, weight), members in weights.items():
        obj.vertex_groups[group].add(members, weight, 'REPLACE')
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    report.append({'mesh': obj.name, 'before_vertices': len(old.vertices), 'after_vertices': len(mesh.vertices)})
    bpy.data.meshes.remove(old)

for obj in list(bpy.data.objects):
    if obj.type != 'MESH' or 'groom fibers' in obj.name or len(obj.data.vertices) < 20000:
        continue
    before = len(obj.data.vertices)
    bpy.context.view_layer.objects.active = obj
    modifier = obj.modifiers.new('Game surface reduction', 'DECIMATE')
    modifier.ratio = .1
    while obj.modifiers.find(modifier.name) > 0:
        bpy.ops.object.modifier_move_up(modifier=modifier.name)
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    report.append({'mesh': obj.name, 'before_vertices': before, 'after_vertices': len(obj.data.vertices)})

rig = bpy.data.objects['CatRig']
bpy.ops.object.select_all(action='DESELECT')
meshes = [obj for obj in rig.children if obj.type == 'MESH']
for obj in meshes:
    obj.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
bpy.ops.object.join()
bpy.context.object.name = 'Cat game surface'
bpy.ops.wm.save_as_mainfile(filepath=str(OUT / 'B3-game.blend'))
bpy.ops.object.select_all(action='DESELECT')
rig.select_set(True)
for obj in rig.children:
    if obj.type == 'MESH':
        obj.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.export_scene.gltf(filepath=str(OUT / 'B3-game.glb'), export_format='GLB', use_selection=True,
                         export_animation_mode='ACTIONS', export_force_sampling=True, export_anim_slide_to_zero=True)
(OUT / 'optimization.json').write_text(json.dumps(report, indent=2))
print('B3_OPTIMIZATION_COMPLETE', flush=True)
