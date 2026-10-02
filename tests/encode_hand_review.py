"""Encode the captured Godot frames using Blender's bundled H.264 encoder."""
from pathlib import Path
import bpy
import sys
root=Path(__file__).resolve().parents[1]
bpy.ops.wm.read_factory_settings(use_empty=True)
scene=bpy.context.scene
scene.sequence_editor_create()
arguments=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
folder=root/'tests/results'/(arguments[1] if len(arguments)>1 else 'hand-review-frames')
files=sorted(folder.glob('[0-9][0-9][0-9][0-9].jpg'))
assert files, 'No captured frames'
assert all(file.name==f'{i:04d}.jpg' for i,file in enumerate(files)), 'Frame sequence has gaps'
strip=scene.sequence_editor.strips.new_image('Petting in Godot',str(files[0]),channel=1,frame_start=1)
for file in files[1:]: strip.elements.append(file.name)
scene.frame_start=1
scene.frame_end=len(files)
scene.render.resolution_x=1280
scene.render.resolution_y=720
scene.render.resolution_percentage=100
scene.render.fps=20
scene.render.image_settings.media_type='VIDEO'
scene.render.image_settings.file_format='FFMPEG'
scene.render.ffmpeg.format='MPEG4'
scene.render.ffmpeg.codec='H264'
scene.render.ffmpeg.constant_rate_factor='HIGH'
output = arguments[0] if arguments else 'cat-petting-close-2026-09-26.mp4'
scene.render.filepath=str(root/'builds'/output)
scene.view_settings.view_transform='Standard'
scene.render.use_sequencer=True
bpy.ops.render.render(animation=True)
