"""Export the reviewed B3 rig without rebuilding the accepted geometry."""
import bpy
from pathlib import Path
ROOT=Path(__file__).resolve().parents[4]
OUT=ROOT/'builds/b3-rig-review'
bpy.ops.wm.open_mainfile(filepath=str(OUT/'B3-rig-review.blend'))
rig=bpy.data.objects['CatRig']
bpy.ops.object.select_all(action='DESELECT')
rig.select_set(True)
for obj in rig.children:
 if obj.type=='MESH':obj.select_set(True)
bpy.context.view_layer.objects.active=rig
bpy.ops.export_scene.gltf(filepath=str(OUT/'B3-rig-review.glb'),export_format='GLB',use_selection=True,export_animation_mode='ACTIONS',export_force_sampling=True,export_anim_slide_to_zero=True)
print('B3_RIG_EXPORT_COMPLETE',flush=True)
