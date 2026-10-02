"""Decode the exported review videos and preserve reproducible QA evidence."""
from pathlib import Path
import json
import hashlib
import bpy
import sys

root=Path(__file__).resolve().parents[1]
review_pass='pass5' if '--pass5' in sys.argv else ('pass3' if '--pass3' in sys.argv else 'pass2')
folder=root/f'tests/results/video-review-{review_pass}'
folder.mkdir(parents=True,exist_ok=True)
(folder/'.gdignore').touch()
report={}
expected={'petting':(100,20),'desk':(280,20),'cup':(160,20),'scratch':(81,30)}
if review_pass=='pass3': expected={'petting':(100,20),'floor':(260,20)}
if review_pass=='pass5': expected={'petting':(47,20),'floor':(260,20)}
for label,(frames,fps) in expected.items():
    date='2026-09-27' if review_pass=='pass5' else '2026-09-26'
    source=root/f'builds/reference-{label}-{review_pass}-{date}.mp4'
    if review_pass=='pass5' and label=='petting': source=root/f'builds/reference-petting-visibility-{date}.mp4'
    bpy.ops.wm.read_factory_settings(use_empty=True)
    clip=bpy.data.movieclips.load(str(source))
    assert list(clip.size)==[1280,720], (label,clip.size[:])
    assert clip.frame_duration==frames and abs(clip.fps-fps)<.01,(label,clip.frame_duration,clip.fps)
    scene=bpy.context.scene
    strip=scene.sequence_editor_create().strips.new_movie(label,str(source),channel=1,frame_start=1)
    strip.transform.scale_x=.75
    strip.transform.scale_y=.75
    scene.render.resolution_x=960
    scene.render.resolution_y=540
    scene.render.resolution_percentage=100
    scene.render.image_settings.file_format='PNG'
    scene.render.use_sequencer=True
    scene.view_settings.view_transform='Standard'
    destination=folder/label
    destination.mkdir(exist_ok=True)
    samples=[]
    for i in range(16):
        frame=1+round((frames-1)*i/15)
        scene.frame_set(frame)
        scene.render.filepath=str(destination/f'{i:02d}.png')
        bpy.ops.render.render(write_still=True)
        samples.append(frame)
    report[label]={'frames':frames,'fps':fps,'seconds':frames/fps,'size':list(clip.size),
        'decoded_samples':samples,'sha256':hashlib.sha256(source.read_bytes()).hexdigest()}
(folder/'verification.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print('REVIEW_VIDEOS_VERIFIED',list(report))
