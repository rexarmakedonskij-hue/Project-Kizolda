"""Encode Godot capture frames with Blender's bundled FFmpeg."""
from pathlib import Path
import bpy

root=Path(__file__).resolve().parents[1]
frames=sorted((root/'builds/cat-review-frames').glob('frame*.png'))
assert len(frames)==120, 'Run lowpoly_cat_capture.gd -- --movie-frames first'
scene=bpy.context.scene
editor=scene.sequence_editor_create()
strip=editor.strips.new_image('Godot walk preview',str(frames[0]),channel=1,frame_start=1)
for frame in frames[1:]: strip.elements.append(frame.name)
scene.frame_start=1
scene.frame_end=len(frames)
scene.render.resolution_x=960
scene.render.resolution_y=960
scene.render.resolution_percentage=100
scene.render.fps=30
scene.render.image_settings.media_type='VIDEO'
scene.render.image_settings.file_format='FFMPEG'
scene.render.ffmpeg.format='MPEG4'
scene.render.ffmpeg.codec='H264'
scene.render.ffmpeg.constant_rate_factor='HIGH'
scene.render.filepath=str(root/'builds/refined-cat-walk.mp4')
scene.view_settings.view_transform='Standard'
scene.render.use_sequencer=True
bpy.ops.render.render(animation=True)
print('CAT_REVIEW_VIDEO_OK',scene.render.filepath)
