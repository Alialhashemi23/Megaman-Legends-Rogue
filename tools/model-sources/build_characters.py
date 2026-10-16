"""Preserve the supplied COLLADA skins/textures and author playable GLB clips.

No Blender installation required. Original ZIPs stay untouched next to this file.
Output uses standard glTF 2.0 meshes, inverse binds, joints, and animation tracks.
"""
from pathlib import Path
import xml.etree.ElementTree as ET
import numpy as np
import math
import struct
import json
import hashlib

ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path(__file__).resolve().parent
OUT = ROOT / "assets/characters"

NAMES = {"Bone000":"Hips", "Bone008":"Pelvis", "Bone001":"Head",
         "Bone002":"LeftUpperArm", "Bone003":"LeftForeArm", "Bone004":"LeftHand",
         "Bone005":"RightUpperArm", "Bone006":"RightForeArm", "Bone007":"RightHand",
         "Bone009":"LeftUpperLeg", "Bone010":"LeftLowerLeg", "Bone011":"LeftFoot",
         "Bone012":"RightUpperLeg", "Bone013":"RightLowerLeg", "Bone014":"RightFoot",
         "Bone015":"Face", "Bone016":"Eyes", "Bone018":"Mouth"}
# Tron's cutscene rig matches the others apart from one fewer face joint. The
# Servbot has one joint per limb: no elbows, knees, hands or feet.
TRON_NAMES = {**{k:v for k,v in NAMES.items() if k not in ("Bone016","Bone018")}, "Bone017":"Mouth"}
SERVBOT_NAMES = {"Bone000":"Hips", "Bone001":"Head", "Bone006":"Face", "Bone002":"LeftUpperArm",
                 "Bone003":"RightUpperArm", "Bone004":"LeftUpperLeg", "Bone005":"RightUpperLeg"}
CLIPS = {"idle":2.8,"run":.48,"backpedal":.56,"strafe_left":.56,"strafe_right":.56,
         "jump":.6,"fall":.7,"dash":.36,"dash_back":.36,"dash_left":.36,"dash_right":.36,
         "land":.26,"hurt":.32,"fire":.18,"victory":2.0,"defeat":.8}

def quat(x=0,y=0,z=0):
    # Intrinsic XYZ rotations, encoded as glTF xyzw quaternions.
    sx,cx = math.sin(x/2),math.cos(x/2)
    sy,cy = math.sin(y/2),math.cos(y/2)
    sz,cz = math.sin(z/2),math.cos(z/2)
    return [sx*cy*cz-cx*sy*sz,cx*sy*cz+sx*cy*sz,cx*cy*sz-sx*sy*cz,cx*cy*cz+sx*sy*sz]

def as_quat(value):
    """Pose values are XYZ Euler tuples, or xyzw quaternions from the leg solver."""
    return list(value) if len(value)==4 else quat(*value)

def quat_matrix(value):
    x,y,z,w=as_quat(value)
    return np.array([[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],
                     [2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],
                     [2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]])

def matrix_quat(m):
    trace=m[0,0]+m[1,1]+m[2,2]
    if trace>0:
        k=2*math.sqrt(trace+1)
        return [(m[2,1]-m[1,2])/k,(m[0,2]-m[2,0])/k,(m[1,0]-m[0,1])/k,k/4]
    i=int(np.argmax([m[0,0],m[1,1],m[2,2]])); j,k=(i+1)%3,(i+2)%3
    r=2*math.sqrt(1+m[i,i]-m[j,j]-m[k,k])
    q=[0,0,0,0]; q[i]=r/4; q[j]=(m[j,i]+m[i,j])/r; q[k]=(m[k,i]+m[i,k])/r; q[3]=(m[k,j]-m[j,k])/r
    return q

def unit(v):
    return v/np.linalg.norm(v)

def basis(direction,hinge):
    """Orthonormal frame whose first axis is direction and second lies along hinge."""
    a=unit(direction); b=unit(hinge-a*np.dot(a,hinge))
    return np.column_stack([a,b,np.cross(a,b)])

def pitch(angle):
    # Rotation about X: +angle lifts the toe of a foot that points along -Z.
    c,s=math.cos(angle),math.sin(angle)
    return np.array([[1,0,0],[0,c,-s],[0,s,c]])

def cycle_curve(keys, phase):
    """Periodic cubic Hermite: distinct contact/recovery timing, smooth velocity."""
    phase %= 1.0
    points = keys[:-1]
    for i, (time,value) in enumerate(points):
        next_time,next_value = keys[i+1]
        if phase <= next_time:
            previous_time,previous_value = points[i-1] if i else (points[-1][0]-1,points[-1][1])
            after_time,after_value = points[(i+2)%len(points)]
            if after_time <= next_time: after_time += 1
            m0=(next_value-previous_value)/(next_time-previous_time)
            m1=(after_value-value)/(after_time-time)
            t=(phase-time)/(next_time-time)
            span=next_time-time
            return (2*t**3-3*t*t+1)*value+(t**3-2*t*t+t)*span*m0+(-2*t**3+3*t*t)*next_value+(t**3-t*t)*span*m1
    return keys[0][1]

HIP_KEYS=[(0,.61),(.12,.32),(.28,-.30),(.40,-.62),(.55,-.44),(.70,.17),(.84,.69),(1,.61)]
KNEE_KEYS=[(0,-.16),(.12,-.32),(.28,-.18),(.40,-.22),(.55,-.95),(.70,-1.10),(.84,-.60),(1,-.16)]
SOLE_KEYS=[(0,.12),(.12,0),(.28,-.04),(.40,-.26),(.55,-.40),(.70,-.26),(.84,.04),(1,.12)]

# Planted run/backpedal legs (rigs with knees). The stance sweep matches the
# digger's ground speed, so a planted boot stays put while the body passes over
# it; a short airborne moment between steps gives a running stride its length.
RUN_SPEED=6.2      # player.gd base_speed; playback scales with the digger's speed
PLANTED={"run":{"travel":-1,"stride":.88,"lift":.30,"heel":.28,"toe":.75},
         "backpedal":{"travel":1,"stride":.80,"lift":.18,"heel":-.22,"toe":.45}}

# Dash key poses. Axes: the diggers face -Z, so +X on Hips leans the torso back and
# +X on a leg swings it forward. +Z swings a hanging limb toward the digger's right
# (+X) and tips the upright torso toward its left.
# Hips carries the torso, arms and head; Pelvis carries the legs.
# Phases: onset crouch (.10), travel (.24-.50, the 0.19 s dash), plant (.66), settle.
DASH_FORWARD={
    "onset":{"Hips":(-.22,0,0),"Pelvis":(.10,0,0),"Head":(.15,0,0),
             "LeftUpperLeg":(.45,0,-.04),"LeftLowerLeg":(-.75,0,0),"LeftFoot":(.30,0,0),
             "RightUpperLeg":(-.20,0,.04),"RightLowerLeg":(-.55,0,0),"RightFoot":(.40,0,0),
             "LeftUpperArm":(-.25,0,-.10),"LeftForeArm":(.30,0,0),"RightUpperArm":(-.35,0,.12),"RightForeArm":(.30,0,0)},
    "travel":{"Hips":(-.50,0,0),"Pelvis":(.18,0,0),"Head":(.38,0,0),
              "LeftUpperLeg":(.95,0,-.04),"LeftLowerLeg":(-1.30,0,0),"LeftFoot":(.45,0,0),
              "RightUpperLeg":(-.55,0,.05),"RightLowerLeg":(-.70,0,0),"RightFoot":(.55,0,0),
              "LeftUpperArm":(-.70,0,-.22),"LeftForeArm":(.40,0,0),"RightUpperArm":(-.95,0,.28),"RightForeArm":(.45,0,0)},
    "glide":{"Hips":(-.45,0,0),"Pelvis":(.16,0,0),"Head":(.34,0,0),
             "LeftUpperLeg":(.85,0,-.04),"LeftLowerLeg":(-1.15,0,0),"LeftFoot":(.40,0,0),
             "RightUpperLeg":(-.62,0,.05),"RightLowerLeg":(-.62,0,0),"RightFoot":(.55,0,0),
             "LeftUpperArm":(-.75,0,-.24),"LeftForeArm":(.42,0,0),"RightUpperArm":(-1.00,0,.30),"RightForeArm":(.45,0,0)},
    "plant":{"Hips":(.10,0,0),"Pelvis":(-.02,0,0),"Head":(-.08,0,0),
             "LeftUpperLeg":(.40,0,-.04),"LeftLowerLeg":(-.45,0,0),"LeftFoot":(0,0,0),
             "RightUpperLeg":(-.30,0,.04),"RightLowerLeg":(-.50,0,0),"RightFoot":(.30,0,0),
             "LeftUpperArm":(.20,0,-.15),"LeftForeArm":(.30,0,0),"RightUpperArm":(.30,0,.20),"RightForeArm":(.40,0,0)}}
DASH_BACK={
    "onset":{"Hips":(-.10,0,0),"Pelvis":(.05,0,0),"Head":(.08,0,0),
             "LeftUpperLeg":(.30,0,-.04),"LeftLowerLeg":(-.70,0,0),"LeftFoot":(.40,0,0),
             "RightUpperLeg":(.05,0,.04),"RightLowerLeg":(-.65,0,0),"RightFoot":(.45,0,0),
             "LeftUpperArm":(.30,0,-.12),"LeftForeArm":(.35,0,0),"RightUpperArm":(.35,0,.12),"RightForeArm":(.35,0,0)},
    "travel":{"Hips":(.32,0,0),"Pelvis":(-.12,0,0),"Head":(-.28,0,0),
              "LeftUpperLeg":(.55,0,-.05),"LeftLowerLeg":(-1.00,0,0),"LeftFoot":(.30,0,0),
              "RightUpperLeg":(-.70,0,.05),"RightLowerLeg":(-.30,0,0),"RightFoot":(.30,0,0),
              "LeftUpperArm":(.40,0,-.22),"LeftForeArm":(.45,0,0),"RightUpperArm":(.55,0,.25),"RightForeArm":(.55,0,0)},
    "glide":{"Hips":(.28,0,0),"Pelvis":(-.10,0,0),"Head":(-.25,0,0),
             "LeftUpperLeg":(.50,0,-.05),"LeftLowerLeg":(-.95,0,0),"LeftFoot":(.30,0,0),
             "RightUpperLeg":(-.75,0,.05),"RightLowerLeg":(-.25,0,0),"RightFoot":(.35,0,0),
             "LeftUpperArm":(.42,0,-.24),"LeftForeArm":(.45,0,0),"RightUpperArm":(.58,0,.27),"RightForeArm":(.55,0,0)},
    "plant":{"Hips":(-.10,0,0),"Pelvis":(.05,0,0),"Head":(.10,0,0),
             "LeftUpperLeg":(.25,0,-.04),"LeftLowerLeg":(-.40,0,0),"LeftFoot":(.20,0,0),
             "RightUpperLeg":(-.35,0,.04),"RightLowerLeg":(-.40,0,0),"RightFoot":(.55,0,0),
             "LeftUpperArm":(.30,0,-.14),"LeftForeArm":(.30,0,0),"RightUpperArm":(.35,0,.15),"RightForeArm":(.35,0,0)}}
DASH_RIGHT={
    "onset":{"Hips":(-.10,0,.10),"Pelvis":(.05,0,-.06),"Head":(.06,0,-.05),
             "LeftUpperLeg":(.10,0,-.18),"LeftLowerLeg":(-.55,0,0),"LeftFoot":(.35,0,.12),
             "RightUpperLeg":(.15,0,.10),"RightLowerLeg":(-.45,0,0),"RightFoot":(.25,0,0),
             "LeftUpperArm":(.10,0,-.15),"LeftForeArm":(.25,0,0),"RightUpperArm":(.10,0,.30),"RightForeArm":(.25,0,0)},
    "travel":{"Hips":(-.12,-.10,-.42),"Pelvis":(.06,0,.22),"Head":(.10,0,.30),
              "LeftUpperLeg":(-.05,0,-.35),"LeftLowerLeg":(-.30,0,0),"LeftFoot":(.30,0,.45),
              "RightUpperLeg":(.25,0,.85),"RightLowerLeg":(-.55,0,0),"RightFoot":(.20,0,-.55),
              "LeftUpperArm":(.10,0,-.55),"LeftForeArm":(.30,0,0),"RightUpperArm":(.10,0,.75),"RightForeArm":(.35,0,0)},
    "glide":{"Hips":(-.10,-.08,-.38),"Pelvis":(.05,0,.20),"Head":(.09,0,.27),
             "LeftUpperLeg":(-.05,0,-.40),"LeftLowerLeg":(-.25,0,0),"LeftFoot":(.28,0,.48),
             "RightUpperLeg":(.22,0,.80),"RightLowerLeg":(-.50,0,0),"RightFoot":(.20,0,-.52),
             "LeftUpperArm":(.10,0,-.60),"LeftForeArm":(.30,0,0),"RightUpperArm":(.10,0,.70),"RightForeArm":(.35,0,0)},
    "plant":{"Hips":(.02,0,.08),"Pelvis":(0,0,-.04),"Head":(0,0,-.05),
             "LeftUpperLeg":(.05,0,-.10),"LeftLowerLeg":(-.30,0,0),"LeftFoot":(.20,0,.08),
             "RightUpperLeg":(.10,0,.32),"RightLowerLeg":(-.45,0,0),"RightFoot":(.25,0,-.30),
             "LeftUpperArm":(.10,0,-.20),"LeftForeArm":(.25,0,0),"RightUpperArm":(.10,0,.30),"RightForeArm":(.30,0,0)}}

def mirror(keyed):
    """Reflect a pose across the character's centre line (swap sides, negate Y/Z turns)."""
    swap=lambda name:name.replace("Left","#").replace("Right","Left").replace("#","Right")
    return {stage:{swap(name):(x,-y,-z) for name,(x,y,z) in bones.items()} for stage,bones in keyed.items()}

DASH_KEYS={"dash":DASH_FORWARD,"dash_back":DASH_BACK,"dash_right":DASH_RIGHT,"dash_left":mirror(DASH_RIGHT)}

def mix(a,b,s):
    return {n:tuple(x+(y-x)*s for x,y in zip(a.get(n,(0,0,0)),b.get(n,(0,0,0)))) for n in set(a)|set(b)}

# Landing squash: knees take the impact, then the digger rises back to idle.
LAND_CROUCH={"Hips":(-.25,0,0),"Pelvis":(.12,0,0),"Head":(.16,0,0),
             "LeftUpperLeg":(.95,0,-.06),"LeftLowerLeg":(-1.55,0,0),"LeftFoot":(.72,0,0),
             "RightUpperLeg":(.85,0,.06),"RightLowerLeg":(-1.45,0,0),"RightFoot":(.72,0,0),
             "LeftUpperArm":(.25,0,-.30),"LeftForeArm":(.30,0,0),"RightUpperArm":(.25,0,.30),"RightForeArm":(.35,0,0)}

def fold_servbot(q):
    """No pelvis, knees or feet: legs hang from Hips, so fold the pelvis turn into
    the stubby legs; the whole block tilts further so the motion still reads."""
    pelvis=q.get("Pelvis",(0,0,0))
    q["Hips"]=tuple(v*1.25 for v in q["Hips"])
    for side in ("Left","Right"):
        q[side+"UpperLeg"]=tuple((v+p)*.8 for v,p in zip(q.get(side+"UpperLeg",(0,0,0)),pelvis))
    return q

def land_pose(phase, neutral, style):
    # Already half-compressed on contact, deepest at .25, then ease back up.
    if phase<.25: k=.5+.5*(lambda t:t*t*(3-2*t))(phase/.25)
    else: k=1-(lambda t:t*t*(3-2*t))((phase-.25)/.75)
    q=mix(neutral,LAND_CROUCH,k)
    return fold_servbot(q) if style=="servbot" else q

def dash_pose(clip, phase, neutral, style):
    stages=DASH_KEYS[clip]
    keys=[(0,neutral),(.10,stages["onset"]),(.24,stages["travel"]),(.50,stages["glide"]),
          (.66,stages["plant"]),(.82,mix(stages["plant"],neutral,.62)),(1,neutral)]
    for (t0,p0),(t1,p1) in zip(keys,keys[1:]):
        if phase<=t1:
            s=(phase-t0)/(t1-t0)
            q=mix(p0,p1,s*s*(3-2*s))
            break
    return fold_servbot(q) if style=="servbot" else q

def pose(clip, phase, style="volnutt"):
    a = phase * math.tau
    q = {name:(0,0,0) for name in NAMES.values()}
    bob = 0
    q["LeftUpperArm"]=(.10,0,-.05)
    q["RightUpperArm"]=(.10,0,.05)
    if clip == "idle":
        q["Hips"]=(.018*math.sin(a),.012*math.sin(a+.7),.012*math.sin(a))
        q["Pelvis"]=(-.012*math.sin(a),-.006*math.sin(a+.7),-.008*math.sin(a))
        q["Head"]=(.012*math.sin(a+.4),.035*math.sin(a-.3),.012*math.sin(a+.6))
        q["RightUpperArm"]=(.10+.028*math.sin(a-.3),0,.08)
        q["RightForeArm"]=(.16+.025*math.sin(a-.6),0,0)
        q["LeftForeArm"]=(.12+.016*math.sin(a-.6),0,0)
        bob=.008*math.sin(a)
    elif clip in ["run","backpedal","strafe_left","strafe_right"]:
        sideways=clip.startswith("strafe")
        lateral=-1 if clip=="strafe_left" else 1
        lean=.10 if style=="volnutt" else .08
        # Negative Hips X leans the torso into the run; backpedalling sits back slightly.
        q["Hips"]=(-lean if clip=="run" else .04 if clip=="backpedal" else -.055,
                   -.065*math.cos(a),-.020*math.sin(a))
        q["Pelvis"]=(-q["Hips"][0]+.025,.11*math.cos(a),.045*math.sin(a))
        q["Head"]=(-q["Hips"][0]*.65,.035*math.cos(a-.25),.015*math.sin(a-.25))
        for side,offset in [("Left",0),("Right",.5)]:
            p=(phase+offset)%1
            hip=cycle_curve(HIP_KEYS,p)
            knee=cycle_curve(KNEE_KEYS,p)
            sole=cycle_curve(SOLE_KEYS,p)
            hip_x=hip*(.32 if sideways else -.76 if clip=="backpedal" else 1)
            knee*=.62 if sideways else .8 if clip=="backpedal" else 1
            side_bias=-.035 if side=="Left" else .035
            q[side+"UpperLeg"]=(hip_x,0,lateral*hip*.68 if sideways else side_bias)
            q[side+"LowerLeg"]=(knee,0,0)
            q[side+"Foot"]=(sole-hip_x-knee-.025,0,0)
            arm=-hip_x*(.75 if side=="Left" else .95)
            if sideways: arm=-hip*.30
            q[side+"UpperArm"]=(arm,.045*math.sin(a),-.11 if side=="Left" else .11)
            q[side+"ForeArm"]=(.28+max(0,arm)*.36,.020*math.sin(a-.4),0)
            q[side+"Hand"]=(.04*math.sin(a-.5),0,0)
        if style=="servbot":
            # Stubby single-joint legs: a quick side-to-side waddle sells the run.
            q["Hips"]=(q["Hips"][0]*.6,q["Hips"][1],.11*math.sin(a))
            q["Head"]=(-q["Hips"][0]*.5,.05*math.cos(a-.25),-.07*math.sin(a))
        bob=0 # Model-specific sole contact is baked after posing the skeleton.
    elif clip in ["jump","fall"]:
        lift=math.sin(phase*math.pi) if clip=="jump" else .55+.08*math.sin(a)
        q["LeftUpperLeg"]=(.55*lift,0,-.07)
        q["RightUpperLeg"]=(.28*lift,0,.07)
        q["LeftLowerLeg"]=(-1.05*lift,0,0)
        q["RightLowerLeg"]=(-.82*lift,0,0)
        q["LeftFoot"]=(.35*lift,0,0)
        q["RightFoot"]=(.27*lift,0,0)
        q["LeftUpperArm"]=(.15,0,-.38*lift)
        q["RightUpperArm"]=(.15,0,.38*lift)
        q["Hips"]=(.06*lift,0,0)
        q["RightForeArm"]=(.35*lift,0,0)
        q["LeftForeArm"]=(.25*lift,0,0)
    elif clip in DASH_KEYS:
        # One-shot: starts and ends on idle's first frame so it hands back cleanly.
        neutral=pose("idle",0,style)[0]
        q.update(dash_pose(clip,phase,neutral,style))
    elif clip=="land":
        q.update(land_pose(phase,pose("idle",0,style)[0],style))
    elif clip=="hurt":
        hit=math.sin(math.pi*phase)*(1-phase)
        q["Hips"]=(-.30*hit,0,.10*hit)
        q["Pelvis"]=(.16*hit,0,0)
        q["Head"]=(-.15*hit,0,0)
    elif clip=="fire":
        recoil=math.sin(math.pi*phase)*(1-phase)
        q["LeftUpperArm"]=(1.18-.18*recoil,0,-.05)
        q["LeftForeArm"]=(.39,0,0)
        q["Head"]=(0,.03,0)
    elif clip=="victory":
        raise_arm=min(1,phase*4)
        q["RightUpperArm"]=(.3,0,2.5*raise_arm)
        q["RightForeArm"]=(.45,0,0)
        q["LeftUpperArm"]=(.25,0,-.15)
        q["Head"]=(0,-.09,.06*math.sin(a))
        bob=.02*math.sin(a)**2
    elif clip=="defeat":
        down=min(1,phase*1.6)
        q["Hips"]=(.5*down,0,0)
        q["Pelvis"]=(.22*down,0,0)
        q["LeftUpperLeg"]=(.5*down,0,0)
        q["RightUpperLeg"]=(.5*down,0,0)
        q["LeftLowerLeg"]=(-1.25*down,0,0)
        q["RightLowerLeg"]=(-1.25*down,0,0)
        q["Head"]=(.35*down,0,0)
        bob=-.3*down
    return q,bob

class Builder:
    def __init__(self):
        self.bin=bytearray()
        self.doc={"asset":{"version":"2.0","generator":"Relic Diver local COLLADA skin converter"},
                  "buffers":[{"byteLength":0}],"bufferViews":[],"accessors":[],"nodes":[],"meshes":[],"skins":[],"animations":[],"scenes":[{"nodes":[0]}],"scene":0}
    def view(self,raw,target=None):
        while len(self.bin)%4: self.bin.append(0)
        offset=len(self.bin); self.bin.extend(raw)
        v={"buffer":0,"byteOffset":offset,"byteLength":len(raw)}
        if target: v["target"]=target
        self.doc["bufferViews"].append(v)
        return len(self.doc["bufferViews"])-1
    def accessor(self,data,kind="VEC3",component=5126,target=None,bounds=False):
        dtype={5126:"<f4",5123:"<u2",5125:"<u4"}[component]
        data=np.ascontiguousarray(data,dtype=dtype)
        entry={"bufferView":self.view(data.tobytes(),target),"componentType":component,"count":len(data),"type":kind}
        if bounds:
            entry["min"]=np.atleast_1d(data.min(axis=0)).tolist()
            entry["max"]=np.atleast_1d(data.max(axis=0)).tolist()
        self.doc["accessors"].append(entry)
        return len(self.doc["accessors"])-1
    def save(self,path):
        self.doc["buffers"][0]["byteLength"]=len(self.bin)
        text=json.dumps(self.doc,separators=(",",":")).encode()
        text+=b" "*((-len(text))%4)
        self.bin+=b"\0"*((-len(self.bin))%4)
        raw=struct.pack("<III",0x46546c67,2,12+8+len(text)+8+len(self.bin))
        raw+=struct.pack("<II",len(text),0x4e4f534a)+text
        raw+=struct.pack("<II",len(self.bin),0x004e4942)+self.bin
        path.write_bytes(raw)

def convert(stem,dae,png,height,names=NAMES):
    tree=ET.parse(dae).getroot()
    for node in tree.iter(): node.tag=node.tag.split("}")[-1]
    mesh=tree.find(".//library_geometries/geometry/mesh")
    sources={}
    for source in mesh.findall("source"):
        stride=int(source.find(".//accessor").get("stride"))
        sources[source.get("id")]=np.array(list(map(float,source.findtext("float_array").split()))).reshape(-1,stride)
    posid=mesh.find("vertices/input").get("source")[1:]
    positions=sources[posid]
    scale=height/float(np.ptp(positions[:,1]))
    floor=-float(positions[:,1].min())*scale
    axis=np.array([-1,1,-1])
    primitive=mesh.find("polylist")
    inputs={n.get("semantic"):(int(n.get("offset")),n.get("source")[1:]) for n in primitive.findall("input")}
    width=max(offset for offset,_ in inputs.values())+1
    raw=np.array(list(map(int,primitive.findtext("p").split()))).reshape(-1,width)
    polygon_sizes=list(map(int,primitive.findtext("vcount").split()))
    triangles=[]; index=0
    for size in polygon_sizes:
        face=raw[index:index+size];index+=size
        for j in range(1,size-1): triangles.extend([face[0],face[j],face[j+1]])
    triangles=np.array(triangles)
    skin=tree.find(".//skin")
    source_nodes={n.get("id"):n for n in skin.findall("source")}
    jointid=skin.find("joints/input[@semantic='JOINT']").get("source")[1:]
    joint_sids=source_nodes[jointid].findtext("Name_array").split()
    weightid=skin.find("vertex_weights/input[@semantic='WEIGHT']").get("source")[1:]
    weights=list(map(float,source_nodes[weightid].findtext("float_array").split()))
    vertex_weights=skin.find("vertex_weights")
    counts=list(map(int,vertex_weights.findtext("vcount").split()))
    influences=list(map(int,vertex_weights.findtext("v").split()))
    joints_per_vertex=[]; weights_per_vertex=[]; cursor=0
    for count in counts:
        values=[(influences[cursor+i*2],weights[influences[cursor+i*2+1]]) for i in range(count)]
        cursor+=count*2
        values=sorted(values,key=lambda p:-p[1])[:4]
        total=sum(w for _,w in values)
        assert total>0
        joints_per_vertex.append([j for j,_ in values]+[0]*(4-len(values)))
        weights_per_vertex.append([w/total for _,w in values]+[0]*(4-len(values)))
    b=Builder();nodes=b.doc["nodes"]
    nodes.append({"name":stem,"children":[1,2]})
    nodes.append({"name":"Body","mesh":0,"skin":0})
    sid_to_node={};worlds={};bone_names={}; translations={}; parents={}
    jointroot=tree.find(".//library_visual_scenes/visual_scene/node[@name='Armature']/node")
    def walk(element,parent=None,parent_world=np.zeros(3)):
        sid=element.get("sid"); name=names[element.get("name")]
        local=np.array(list(map(float,element.findtext("translate").split())))*axis*scale
        if parent is None: local[1]+=floor
        idx=len(nodes);sid_to_node[sid]=idx;bone_names[name]=idx;translations[name]=local.tolist()
        parents[name]=nodes[parent]["name"] if parent is not None else None
        worlds[sid]=local+parent_world
        nodes.append({"name":name,"translation":local.tolist()})
        children=[]
        for child in element.findall("node"): children.append(walk(child,idx,worlds[sid]))
        if children: nodes[idx]["children"]=children
        return idx
    walk(jointroot)
    vertexids=triangles[:,inputs["VERTEX"][0]]
    # Replace only the left glove with the attached buster; otherwise the
    # original fist protrudes through the cannon's aperture when aiming.
    original_triangle_count=len(triangles)//3
    hand_sid=next((sid for sid,idx in sid_to_node.items() if nodes[idx]["name"]=="LeftHand"),None)
    if hand_sid is not None:
        hand_index=joint_sids.index(hand_sid)
        owners=np.array(joints_per_vertex)[:,0][vertexids].reshape(-1,3)
        keep=np.repeat(~np.all(owners==hand_index,axis=1),3)
        triangles=triangles[keep];vertexids=vertexids[keep]
    p=positions[vertexids]*axis*scale;p[:,1]+=floor
    n=sources[inputs["NORMAL"][1]][triangles[:,inputs["NORMAL"][0]]]*axis
    uv=sources[inputs["TEXCOORD"][1]][triangles[:,inputs["TEXCOORD"][0]]].copy();uv[:,1]=1-uv[:,1]
    # Confirm normals and triangle winding agree before glTF import.
    face_norm=np.cross(p[1::3]-p[::3],p[2::3]-p[::3])
    alignment=np.sum(face_norm*n[::3],axis=1)
    if np.mean(alignment)<0:
        order=np.arange(len(p)).reshape(-1,3)[:,[0,2,1]].flatten()
        p,n,uv,vertexids=p[order],n[order],uv[order],vertexids[order]
    attrs={"POSITION":b.accessor(p,target=34962,bounds=True),"NORMAL":b.accessor(n,target=34962),
           "TEXCOORD_0":b.accessor(uv,"VEC2",target=34962),
           "JOINTS_0":b.accessor(np.array(joints_per_vertex)[vertexids],"VEC4",5123,34962),
           "WEIGHTS_0":b.accessor(np.array(weights_per_vertex)[vertexids],"VEC4",target=34962)}
    inverse=[]
    for sid in joint_sids:
        matrix=np.eye(4);matrix[:3,3]=-worlds[sid]
        inverse.append(matrix.T.flatten())
    b.doc["skins"].append({"name":"OriginalSkin","skeleton":2,"joints":[sid_to_node[s] for s in joint_sids],"inverseBindMatrices":b.accessor(inverse,"MAT4")})
    b.doc["meshes"].append({"name":"OriginalLegendsMesh","primitives":[{"attributes":attrs,"material":0}]})
    b.doc["images"]=[{"bufferView":b.view(png.read_bytes()),"mimeType":"image/png","name":"OriginalTexture"}]
    b.doc["samplers"]=[{"magFilter":9728,"minFilter":9728,"wrapS":33071,"wrapT":33071}]
    b.doc["textures"]=[{"sampler":0,"source":0}]
    b.doc["materials"]=[{"name":"OriginalPaintedTexture","pbrMetallicRoughness":{"baseColorTexture":{"index":0},"metallicFactor":0,"roughnessFactor":1},"doubleSided":True}]
    # Rigid original weights let us locate the actual boot soles, rather than
    # guessing a bob curve that leaves the boots hovering above the ground.
    rest_positions=positions*axis*scale
    rest_positions[:,1]+=floor
    feet={}
    # The lowest joint of each leg carries the sole: a foot, or the whole leg on a Servbot.
    sole_joints=("LeftFoot","RightFoot") if "LeftFoot" in bone_names else ("LeftUpperLeg","RightUpperLeg")
    for sid in joint_sids:
        name=nodes[sid_to_node[sid]]["name"]
        if name in sole_joints:
            owned=np.array(joints_per_vertex)[:,0]==joint_sids.index(sid)
            feet[name]=rest_positions[owned]-worlds[sid]
    def forward_kinematics(rotations,bob=0):
        transforms={}
        for name in bone_names:
            matrix=np.eye(4)
            matrix[:3,:3]=quat_matrix(rotations[name])
            matrix[:3,3]=translations[name]
            if not parents[name]: matrix[1,3]+=bob
            transforms[name]=transforms[parents[name]]@matrix if parents[name] else matrix
        return transforms
    def ground_offset(rotations):
        transforms=forward_kinematics(rotations)
        return -min(float((points@transforms[name][:3,:3].T+transforms[name][:3,3])[:,1].min())
                    for name,points in feet.items())
    planted_legs="LeftLowerLeg" in bone_names and "LeftFoot" in bone_names
    if planted_legs:
        thigh=float(np.linalg.norm(translations["LeftLowerLeg"]))
        shin=float(np.linalg.norm(translations["LeftFoot"]))
        sole=feet["LeftFoot"]
        ankle_height=-float(sole[:,1].min())
        flat=sole[sole[:,1]<sole[:,1].min()+.012]
        heel_point=flat[np.argmax(flat[:,2])]; toe_point=flat[np.argmin(flat[:,2])]
        hip_height=float(forward_kinematics({n:(0,0,0) for n in bone_names})["LeftUpperLeg"][1,3])
    def planted(clip,phase,rotations):
        """Solve both legs onto a planted foot path; returns (rotations, root bob)."""
        spec=PLANTED[clip]; travel=spec["travel"]; cycle=CLIPS[clip]
        stride=spec["stride"]*hip_height
        stance=min(.45,stride/(RUN_SPEED*cycle))
        rotations=dict(rotations)
        for side in ("Left","Right"):
            for part in ("UpperLeg","LowerLeg","Foot"): rotations[side+part]=(0,0,0)
        rest=forward_kinematics(rotations)
        def stance_pose(p,x):
            # The flat ankle slides opposite the travel direction at exactly the ground speed.
            z=travel*stride/2-travel*RUN_SPEED*cycle*p
            u=p/stance; angle=0.0; pivot=None
            if u<.15:
                angle=spec["heel"]*(1-u/.15); pivot=heel_point if angle>0 else toe_point
            elif u>.62:
                angle=-spec["toe"]*(u-.62)/.38; pivot=toe_point
            ankle=np.array([x,ankle_height,z])
            if pivot is not None:
                ground=ankle+pivot
                ankle=ground-pitch(angle)@pivot
            return ankle,angle
        targets={}
        for side,offset in (("Left",0),("Right",.5)):
            p=(phase-offset)%1
            x=rest[side+"UpperLeg"][0,3]*.75
            if p<stance:
                targets[side]=stance_pose(p,x)+(True,)
            else:
                u=(p-stance)/(1-stance); e=u*u*(3-2*u)
                (a0,f0),(a1,f1)=stance_pose(stance,x),stance_pose(0,x)
                ankle=a0+(a1-a0)*e+np.array([0,spec["lift"]*hip_height*math.sin(math.pi*u),0])
                angle=f0+(f1-f0)*e-.25*math.sin(math.pi*u)
                targets[side]=(ankle,angle,False)
        # Body height: lowest in mid-stance, highest mid-flight, never so high that
        # a planted boot can't reach the floor with a slightly bent knee.
        flight=(stance+.5)/2
        bob=hip_height*(-.035+.03*math.cos(4*math.pi*(phase-flight)))
        reach=.985*(thigh+shin)
        for side,(ankle,angle,down) in targets.items():
            if not down: continue
            hip=rest[side+"UpperLeg"][:3,3]
            across=(ankle[0]-hip[0])**2+(ankle[2]-hip[2])**2
            bob=min(bob,float(ankle[1]+math.sqrt(max(reach*reach-across,0))-hip[1]))
        world=forward_kinematics(rotations,bob)
        for side,(ankle,angle,_) in targets.items():
            hip=world[side+"UpperLeg"][:3,3]
            parent=world["Pelvis"][:3,:3]
            reach_vector=ankle-hip
            distance=min(max(float(np.linalg.norm(reach_vector)),abs(thigh-shin)+.01),(thigh+shin)*.999)
            down_dir=unit(reach_vector)
            pole=np.array([0,0,-1.0])
            across_dir=unit(pole-down_dir*np.dot(pole,down_dir))
            hinge=unit(np.cross(down_dir,across_dir))
            bend=math.acos(max(-1,min(1,(thigh*thigh+distance*distance-shin*shin)/(2*thigh*distance))))
            knee=hip+thigh*(math.cos(bend)*down_dir+math.sin(bend)*across_dir)
            foot_at=hip+down_dir*distance
            thigh_world=basis(knee-hip,hinge)@basis(np.array(translations[side+"LowerLeg"]),np.array([1.0,0,0])).T
            shin_world=basis(foot_at-knee,hinge)@basis(np.array(translations[side+"Foot"]),np.array([1.0,0,0])).T
            rotations[side+"UpperLeg"]=tuple(matrix_quat(parent.T@thigh_world))
            rotations[side+"LowerLeg"]=tuple(matrix_quat(thigh_world.T@shin_world))
            rotations[side+"Foot"]=tuple(matrix_quat(shin_world.T@pitch(angle)))
        return rotations,bob
    root_ranges={}
    for clip,duration in CLIPS.items():
        framecount=max(17,round(duration*60)+1)
        phases=np.linspace(0,1,framecount)
        samples=[pose(clip,float(phase),stem) for phase in phases]
        if planted_legs and clip in PLANTED:
            samples=[planted(clip,float(phase),rotations) for phase,(rotations,_) in zip(phases,samples)]
        elif clip in ("idle","run","backpedal","strafe_left","strafe_right","land") or clip.startswith("dash"):
            samples=[(rotations,ground_offset(rotations)) for rotations,_ in samples]
        root_ranges[clip]=[round(min(bob for _,bob in samples),4),round(max(bob for _,bob in samples),4)]
        time=b.accessor(phases*duration,"SCALAR",bounds=True)
        animation={"name":clip,"samplers":[],"channels":[]}
        for name,nodeidx in bone_names.items():
            keys=[]
            for sample in samples:
                key=as_quat(sample[0][name])
                if keys and np.dot(key,keys[-1])<0: key=[-v for v in key]
                keys.append(key)
            output=b.accessor(keys,"VEC4")
            sampler=len(animation["samplers"])
            animation["samplers"].append({"input":time,"output":output,"interpolation":"LINEAR"})
            animation["channels"].append({"sampler":sampler,"target":{"node":nodeidx,"path":"rotation"}})
        positions=[np.array(translations["Hips"])+np.array([0,bob,0]) for _,bob in samples]
        sampler=len(animation["samplers"])
        animation["samplers"].append({"input":time,"output":b.accessor(positions),"interpolation":"LINEAR"})
        animation["channels"].append({"sampler":sampler,"target":{"node":bone_names["Hips"],"path":"translation"}})
        b.doc["animations"].append(animation)
    OUT.mkdir(parents=True,exist_ok=True)
    b.save(OUT/f"{stem}.glb")
    report={"source":str(dae.relative_to(ROOT)),"source_sha256":hashlib.sha256(dae.read_bytes()).hexdigest(),
            "texture_sha256":hashlib.sha256(png.read_bytes()).hexdigest(),"source_vertices":len(counts),
            "triangles":len(p)//3,"original_triangles":original_triangle_count,"left_glove_replaced_by_buster":hand_sid is not None,
            "bones":len(joint_sids),"height_m":height,"scale":scale,"floor_offset":floor,
            "joint_names":list(bone_names),"clips":CLIPS,"root_offset_ranges":root_ranges,"source_weight_sums_valid":True}
    print(stem,json.dumps(report,indent=2))
    return report

if __name__=="__main__":
    reports={}
    reports["volnutt"]=convert("volnutt",SOURCE/"volnutt/Megaman.dae",SOURCE/"volnutt/Megaman.png",1.95)
    reports["roll"]=convert("roll",SOURCE/"roll/Roll_(Cutscene).dae",SOURCE/"roll/Roll_(Cutscene).png",1.88)
    reports["tron"]=convert("tron",SOURCE/"tron/Tron_Bonne_(Cutscene).dae",SOURCE/"tron/Tron_Bonne_(Cutscene).png",1.86,TRON_NAMES)
    reports["servbot"]=convert("servbot",SOURCE/"servbot/ServBot.dae",SOURCE/"servbot/ServBot.png",1.08,SERVBOT_NAMES)
    (SOURCE/"conversion-report.json").write_text(json.dumps(reports,indent=2))
