"""Check the exported source face keys without changing the accepted asset."""
from pathlib import Path
import json
import hashlib
import bpy
import sys

root=Path(__file__).resolve().parents[1]
source=root/'assets/models/blender/cat_reference.blend'
fbx=root/'assets/models/glb/godot_mvp/cat_reference.fbx'
bpy.ops.wm.open_mainfile(filepath=str(source))
mesh=bpy.data.objects['mesh_cat'].data
keys=mesh.shape_keys.key_blocks
assert set(keys.keys())=={'Basis','Blink','HideIris','LookLeft','LookRight'}
assert all(keys[name].value==0 for name in ['Blink','HideIris','LookLeft','LookRight']), 'Default face must have open eyes'
for name in ['LookLeft','LookRight']:
    for original,key in zip(keys['Basis'].data,keys[name].data):
        change=key.co-original.co
        assert abs(change.x)<1e-7 and abs(change.z)<1e-7, 'Gaze must not inherit a blink'
for original,left,right in zip(keys['Basis'].data,keys['LookLeft'].data,keys['LookRight'].data):
    assert ((left.co-original.co)+(right.co-original.co)).length<1e-7
iris=set()
for face in mesh.polygons:
    if mesh.materials[face.material_index].name.startswith('Green iris'):
        iris.update(face.vertices)
assert iris
for vertex in iris:
    assert abs(keys['LookLeft'].data[vertex].co.y-keys['Basis'].data[vertex].co.y-.0025)<1e-7
    assert abs(keys['Blink'].data[vertex].co.x-keys['Basis'].data[vertex].co.x)<1e-7
    assert abs(keys['HideIris'].data[vertex].co.x-keys['Basis'].data[vertex].co.x+.014)<1e-7
report={'passed':True,'gaze_changes_only_lateral_coordinates':True,'default_keys_are_zero':True,
        'iris_vertices_checked':len(iris),'blend_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
        'fbx_sha256':hashlib.sha256(fbx.read_bytes()).hexdigest()}
review_pass=next((a.split('=',1)[1] for a in sys.argv if a.startswith('--review-pass=')),'pass3')
(root/f'tests/results/face-asset-{review_pass}.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print('FACE_ASSET_CONTRACT_OK',len(iris))
