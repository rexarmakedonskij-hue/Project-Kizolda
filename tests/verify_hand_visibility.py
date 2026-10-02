"""Measure iris visibility against each identical rendered pose with hand hidden."""
from pathlib import Path
import hashlib
import json
import sys
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
folder=ROOT/'tests/results'/(sys.argv[1] if len(sys.argv)>1 else 'hand-visibility-pass6')
def iris_mask(image):
    pixels=np.asarray(image.convert('RGB')).astype(np.int16)
    h,w=pixels.shape[:2]
    region=np.zeros((h,w),dtype=bool)
    region[int(h*.22):int(h*.61),int(w*.31):int(w*.69)]=True
    red,green,blue=pixels[:,:,0],pixels[:,:,1],pixels[:,:,2]
    return region&(green>110)&(green>red+45)&(green>blue+30)
frames=[]
minimum=[1.,1.]
minimum_unoccluded=[1.,1.]
for uncovered_path in sorted(folder.glob('uncovered-*.png'),key=lambda p:int(p.stem.split('-')[-1])):
    frame=int(uncovered_path.stem.split('-')[-1])
    uncovered=iris_mask(Image.open(uncovered_path))
    visible_image=Image.open(folder/f'visible-{frame}.png').convert('RGB')
    visible=iris_mask(visible_image)
    red,green,blue=np.moveaxis(np.asarray(visible_image).astype(np.float64),-1,0)
    # Keep the bright-iris metric above unchanged. Darker green at the same
    # iris pixels is a shadow, whereas skin/sleeve pixels remove the green hue.
    green_hue=visible|((green>30)&(green>red*1.7)&(green>blue*1.7))
    midpoint=uncovered.shape[1]//2
    counts=[]
    seen=[]
    fractions=[]
    unoccluded=[]
    unoccluded_fractions=[]
    for region in (np.s_[:,:midpoint],np.s_[:,midpoint:]):
        count=int(uncovered[region].sum())
        observed=int((uncovered[region]&visible[region]).sum())
        # Closed eyes deliberately contain no useful iris area.
        fraction=observed/count if count>=30 else None
        counts.append(count)
        seen.append(observed)
        fractions.append(fraction)
        present=int((uncovered[region]&green_hue[region]).sum())
        unoccluded.append(present)
        unoccluded_fractions.append(present/count if count>=30 else None)
    for eye,fraction in enumerate(fractions):
        if fraction is not None: minimum[eye]=min(minimum[eye],fraction)
    for eye,fraction in enumerate(unoccluded_fractions):
        if fraction is not None: minimum_unoccluded[eye]=min(minimum_unoccluded[eye],fraction)
    frames.append({'frame':frame,'seconds':frame/20,'uncovered_iris_pixels':counts,'visible_iris_pixels':seen,'visible_fraction':fractions,'unoccluded_iris_pixels':unoccluded,'unoccluded_fraction':unoccluded_fractions})
sources=['player/petting_hand.gd','assets/models/glb/godot_mvp/player_arm.glb','assets/models/glb/godot_mvp/cat_reference.fbx','cats/cat.gd']
hashes={path:hashlib.sha256((ROOT/path).read_bytes()).hexdigest() for path in sources if (ROOT/path).exists()}
expected_frames=43 if (folder/'geometry-sequence.json').exists() else 33
passed=len(frames)==expected_frames and min(minimum_unoccluded)>=.99
report={'scope':'Actual first-person render across both strokes and withdrawal at20fps; compares same pose with hand hidden. Closed eye masks excluded. Bright-green mask retained; separate green-hue mask distinguishes cast shadow from skin/sleeve occlusion. Measures eye visibility only.','min_visible_iris_fraction':minimum,'all_open_eye_frames_over_99_percent':len(frames)==expected_frames and min(minimum)>=.99,'min_unoccluded_iris_fraction':minimum_unoccluded,'all_open_eye_frames_unoccluded_over_99_percent':passed,'source_sha256':hashes,'frames':frames}
(folder/'eye-visibility.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print(json.dumps({'passed':passed,'frames':len(frames),'minimum_visible_fraction':minimum,'minimum_unoccluded_fraction':minimum_unoccluded}))
sys.exit(0 if passed else 1)
