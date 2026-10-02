"""Check flight pose evidence and the actual root/mesh comparison independently."""
from pathlib import Path
import argparse
import json
import math

ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument('--trial-name',default='desktop_poses_trial_v5')
parser.add_argument('--capture-folder',default='desktop-flight-trial-v5')
options=parser.parse_args()
report=json.loads((ROOT/f'tests/results/{options.trial_name}-anatomy.json').read_text())
trial=json.loads((ROOT/f'cats/{options.trial_name}.gd').read_text().split('const DATA = ',1)[1])
active=json.loads((ROOT/'cats/desktop_poses.gd').read_text().split('const DATA = ',1)[1])
checks=[]
def check(ok,label,value=None):
    checks.append({'passed':bool(ok),'label':label,'value':value})
    print(('PASS: ' if ok else 'FAIL: ')+label, value if value is not None else '')
def distance(p,q): return math.sqrt(sum((x-y)**2 for x,y in zip(p,q)))

check(report['durations']['Jump']==.8 and report['durations']['Descend']==.7,'Flight timings stay .8/.7 seconds')
unchanged=['Sit','SitDown','Stand','Touch']
unchanged_error=max(abs(x-y) for name in unchanged for a,b in zip(trial[name],active[name]) for bone in a for channel in range(2) for x,y in zip(a[bone][channel],b[bone][channel]))
# Re-evaluating the current Blender rig can change its float rounding by 1e-7.
check(unchanged_error<1e-6,'Correct non-flight clips retain the same poses within bake precision',unchanged_error)
max_length_error=0
max_gap=0
lowest=math.inf
for name in ['Crouch','CrouchDown','Land','Jump','Descend']:
    check(len(report['kinematics'][name])==25,name+' has a full sampled pose sequence')
    for frame in report['kinematics'][name]:
        bones=frame['bones']
        max_length_error=max(max_length_error,max(abs(b['length']-b['rest_length'])for b in bones.values()))
        for limb in ['front','back']:
            for side in ['left','right']:
                for joint in range(1,4):
                    max_gap=max(max_gap,distance(bones[f'leg_{limb}_{side}_{joint}']['tail'],bones[f'leg_{limb}_{side}_{joint+1}']['head']))
    if name in ['Crouch','CrouchDown','Land']:
        lowest=min(lowest,min(frame['lowest_z']for frame in report['anatomy'][name]))
check(max_length_error<.000001,'Every bone retains its original length',max_length_error)
check(max_gap<.000001,'All limb joints remain connected',max_gap)
check(lowest>=0,'All anticipation and landing source-mesh phases stay above contact plane',lowest)
for name in ['Jump','Descend']:
    frames=report['kinematics'][name]
    gathering=[]
    for side in ['left','right']:
        def hip_to_paw(frame):
            b=frame['bones'];return distance(b[f'leg_back_{side}_1']['head'],b[f'leg_back_{side}_4']['head'])
        gathering.append(hip_to_paw(frames[3])-hip_to_paw(frames[12]))
    check(min(gathering)>.035,name+' gathers both hind paws after extension',gathering)
    forward=[frames[21]['bones'][f'leg_front_{side}_4']['head'][0]-frames[12]['bones'][f'leg_front_{side}_4']['head'][0]for side in ['left','right']]
    check(min(forward)>.045,name+' reaches both forepaws toward landing',forward)

folder=ROOT/'tests/results'/options.capture_folder
captures={name:json.loads((folder/name/'motion.json').read_text())for name in ['baseline','trial']}
baseline,candidate=captures['baseline'],captures['trial']
root_error=max(distance(a['root'],b['root'])for a,b in zip(baseline,candidate))
check(len(baseline)==len(candidate) and all(a['state']==b['state']for a,b in zip(baseline,candidate)) and root_error<.000001,'Actual root trajectory and action state timing remain identical',root_error)
floor=min(frame['skin']['floor_low']for frame in candidate)
table=min(frame['skin']['desk_low']for frame in candidate if frame['skin']['desk_low']is not None)
check(floor>-.003,'Actual skinned mesh stays above floor through crouch, flight and landing',floor)
check(table>.937,'Actual skinned mesh stays above .94m tabletop through all phases',table)
passed=all(item['passed']for item in checks)
(folder/'pose-contract.json').write_text(json.dumps({'passed':passed,'checks':checks},indent=2),encoding='utf-8')
raise SystemExit(0 if passed else 1)
