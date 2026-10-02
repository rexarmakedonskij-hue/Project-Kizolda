"""Render three real-time scratch cycles and measure the loop seam."""
import bpy,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[4];OUT=ROOT/'builds/b3-rig-review'
bpy.ops.wm.open_mainfile(filepath=str(OUT/'B3-rig-review.blend'))
scene=bpy.context.scene;rig=bpy.data.objects['CatRig'];action=bpy.data.actions['Scratch'];rig.animation_data.action=action
positions={};matrices={}
for frame in [1,2,40,41]:
 scene.frame_set(frame);bpy.context.view_layer.update();positions[frame]={p.name:p.matrix.translation.copy() for p in rig.pose.bones};matrices[frame]={p.name:p.matrix.copy() for p in rig.pose.bones}
seam=max((positions[1][n]-positions[41][n]).length for n in positions[1]);assert seam<1e-5,seam
matrix_error=max(abs(matrices[1][n][i][j]-matrices[41][n][i][j]) for n in matrices[1] for i in range(4) for j in range(4));assert matrix_error<1e-5,matrix_error
report={'matrix_seam_max_error':matrix_error,'loop_seam_max_distance':seam,'duration_seconds':40/30,'fps':30,'repeats':3}
(OUT/'loop-validation.json').write_text(json.dumps(report,indent=2));print('LOOP_VALIDATION',report,flush=True)
rig.animation_data.action=None
for track in rig.animation_data.nla_tracks:
 track.mute=track.name!='Scratch'
 if track.name=='Scratch':track.strips[0].repeat=3
scene.frame_start=1;scene.frame_end=120;scene.render.fps=30;scene.render.resolution_x=480;scene.render.resolution_y=540;scene.cycles.samples=8
settings=scene.render.image_settings
formats=[x.identifier for x in settings.bl_rna.properties['file_format'].enum_items]
print('FORMATS',formats,flush=True)
if hasattr(settings,'media_type'):settings.media_type='VIDEO'
elif hasattr(scene.render,'media_type'):scene.render.media_type='VIDEO'
settings.file_format='FFMPEG'
scene.render.ffmpeg.format='MPEG4';scene.render.ffmpeg.codec='H264';scene.render.ffmpeg.constant_rate_factor='MEDIUM'
scene.render.filepath=str(OUT/'B3-scratch-loop.mp4');bpy.ops.render.render(animation=True)
print('B3_LOOP_VIDEO_COMPLETE',flush=True)
