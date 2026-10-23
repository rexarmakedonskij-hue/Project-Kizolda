"""Read local reference trailer frames through Blender's bundled video decoder."""
from pathlib import Path
import bpy
import sys
ROOT=Path(__file__).resolve().parents[1]
source=Path(r'C:\Users\rexar\Downloads\Little Kitty, Big City – Launch Trailer – Nintendo Switch_1080p.mp4')
motion='--motion' in sys.argv
out=ROOT/('tests/results/reference-motion' if motion else 'tests/results/reference-trailer')
out.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
clip=bpy.data.movieclips.load(str(source))
print('REFERENCE_METADATA',clip.size[:],clip.frame_duration,clip.fps)
scene=bpy.context.scene
seq=scene.sequence_editor_create()
strip=seq.strips.new_movie('User reference candidate',str(source),channel=1,frame_start=1)
strip.transform.scale_x=.5
strip.transform.scale_y=.5
scene.render.resolution_x=960
scene.render.resolution_y=540
scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'
scene.render.use_sequencer=True
scene.view_settings.view_transform='Standard'
for i in range(20 if motion else 16):
    frame=round((20.8+i*.1)*clip.fps) if motion else int(1+(clip.frame_duration-2)*(i+.5)/16)
    scene.frame_set(frame)
    scene.render.filepath=str(out/f'{i:02d}-{frame/clip.fps:.1f}s.png')
    bpy.ops.render.render(write_still=True)
print('REFERENCE_FRAMES_READY')
