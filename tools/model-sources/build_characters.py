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
CLIPS = {"idle":2.8,"run":.48,"backpedal":.56,"strafe_left":.56,"strafe_right":.56,
         "jump":.6,"fall":.7,"dash":.32,"hurt":.32,"fire":.18,"victory":2.0,"defeat":.8}

def quat(x=0,y=0,z=0):
    # Intrinsic XYZ rotations, encoded as glTF xyzw quaternions.
    sx,cx = math.sin(x/2),math.cos(x/2)
    sy,cy = math.sin(y/2),math.cos(y/2)
    sz,cz = math.sin(z/2),math.cos(z/2)
    return [sx*cy*cz-cx*sy*sz,cx*sy*cz+sx*cy*sz,cx*cy*sz-sx*sy*cz,cx*cy*cz+sx*sy*sz]

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

def pose(clip, phase, roll=False):
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
        lean=.08 if roll else .10
        q["Hips"]=(lean if clip=="run" else -.04 if clip=="backpedal" else .055,
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
    elif clip=="dash":
        q["Hips"]=(.45,0,0)
        q["Pelvis"]=(-.15,0,0)
        q["LeftUpperLeg"]=(.7,0,0)
        q["RightUpperLeg"]=(-.5,0,0)
        q["LeftLowerLeg"]=(-.95,0,0)
        q["RightLowerLeg"]=(-.35,0,0)
        q["RightUpperArm"]=(-.65,0,.08)
        q["Head"]=(-.22,0,0)
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

def convert(stem,dae,png,height):
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
        sid=element.get("sid"); name=NAMES[element.get("name")]
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
    hand_sid=next(sid for sid,idx in sid_to_node.items() if nodes[idx]["name"]=="LeftHand")
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
    for sid in joint_sids:
        name=nodes[sid_to_node[sid]]["name"]
        if name in ("LeftFoot","RightFoot"):
            owned=np.array(joints_per_vertex)[:,0]==joint_sids.index(sid)
            feet[name]=rest_positions[owned]-worlds[sid]
    def ground_offset(rotations):
        transforms={}
        for name in bone_names:
            x,y,z,w=quat(*rotations[name])
            matrix=np.eye(4)
            matrix[:3,:3]=[[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],
                           [2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],
                           [2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]]
            matrix[:3,3]=translations[name]
            transforms[name]=transforms[parents[name]]@matrix if parents[name] else matrix
        return -min(float((points@transforms[name][:3,:3].T+transforms[name][:3,3])[:,1].min())
                    for name,points in feet.items())
    root_ranges={}
    for clip,duration in CLIPS.items():
        framecount=max(17,round(duration*60)+1)
        phases=np.linspace(0,1,framecount)
        samples=[pose(clip,float(phase),stem=="roll") for phase in phases]
        if clip in ("idle","run","backpedal","strafe_left","strafe_right","dash"):
            samples=[(rotations,ground_offset(rotations)) for rotations,_ in samples]
        root_ranges[clip]=[round(min(bob for _,bob in samples),4),round(max(bob for _,bob in samples),4)]
        time=b.accessor(phases*duration,"SCALAR",bounds=True)
        animation={"name":clip,"samplers":[],"channels":[]}
        for name,nodeidx in bone_names.items():
            output=b.accessor([quat(*sample[0][name]) for sample in samples],"VEC4")
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
            "triangles":len(p)//3,"original_triangles":original_triangle_count,"left_glove_replaced_by_buster":True,
            "bones":len(joint_sids),"height_m":height,"scale":scale,"floor_offset":floor,
            "joint_names":list(bone_names),"clips":CLIPS,"root_offset_ranges":root_ranges,"source_weight_sums_valid":True}
    print(stem,json.dumps(report,indent=2))
    return report

if __name__=="__main__":
    reports={}
    reports["volnutt"]=convert("volnutt",SOURCE/"volnutt/Megaman.dae",SOURCE/"volnutt/Megaman.png",1.95)
    reports["roll"]=convert("roll",SOURCE/"roll/Roll_(Cutscene).dae",SOURCE/"roll/Roll_(Cutscene).png",1.88)
    (SOURCE/"conversion-report.json").write_text(json.dumps(reports,indent=2))
