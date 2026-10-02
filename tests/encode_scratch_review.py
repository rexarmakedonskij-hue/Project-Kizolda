"""Encode a gameplay rendering of the revised scratching loop."""
from pathlib import Path
import bpy
import sys
root=Path(__file__).resolve().parents[1]
frames=sorted((root/'builds/scratch-review-frames').glob('frame*.png'))
assert len(frames)==81
scene=bpy.context.scene
editor=scene.sequence_editor_create()
strip=editor.strips.new_image('Revised scratch',str(frames[0]),channel=1,frame_start=1)
for frame in frames[1:]: strip.elements.append(frame.name)
scene.frame_start=1
scene.frame_end=len(frames)
scene.render.resolution_x=1280
scene.render.resolution_y=720
scene.render.resolution_percentage=100
scene.render.fps=30
scene.render.image_settings.media_type='VIDEO'
scene.render.image_settings.file_format='FFMPEG'
scene.render.ffmpeg.format='MPEG4'
scene.render.ffmpeg.codec='H264'
scene.render.ffmpeg.constant_rate_factor='HIGH'
output=sys.argv[sys.argv.index('--')+1] if '--' in sys.argv else 'cat-scratch-revised-2026-09-24.mp4'
scene.render.filepath=str(root/'builds'/output)
scene.view_settings.view_transform='Standard'
scene.render.use_sequencer=True
bpy.ops.render.render(animation=True)
print('SCRATCH_REVIEW_VIDEO_OK',scene.render.filepath)
