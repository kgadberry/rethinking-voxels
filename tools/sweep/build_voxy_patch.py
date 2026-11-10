# Assemble one voxy patch variant the way voxy's Iris pipeline does, for glslang.
import os, re, sys, json
HERE = os.path.dirname(os.path.abspath(__file__))
R = os.environ.get("PACK_ROOT", os.path.normpath(os.path.join(HERE, "..", "..", "shaders")))
# extracted voxy jar: the directory holding assets/voxy/shaders
VX = os.path.join(os.environ["VOXY_SHADERS"], "assets")
OUT=sys.argv[1]
MODE=sys.argv[3] if len(sys.argv)>3 else "opaque"
IRIS=sys.argv[4] if len(sys.argv)>4 else "11104"

# ---- voxy side: #import <ns:path> -> assets/<ns>/shaders/<path>, once each (guard-free) ----
imp_re=re.compile(r'^\s*#import\s*<([^:>]+):([^>]+)>\s*$')
seen=set()
def vx(path,out):
    for line in open(path,errors="replace").read().split("\n"):
        m=imp_re.match(line)
        if m:
            ns,rel=m.group(1),m.group(2)
            f=f"{VX}/{ns}/shaders/{rel}"
            if rel in seen: out.append(f"// (dup import {rel})"); continue
            seen.add(rel)
            if not os.path.isfile(f): out.append(f"#error missing voxy import {rel}"); continue
            out.append(f"// >>> voxy {rel}")
            vx(f,out)
            out.append(f"// <<< voxy {rel}")
        elif line.startswith("#version"):
            out.append("// "+line)
        else:
            out.append(line)

# ---- pack side: Iris #include flattening ----
inc_re=re.compile(r'^(\s*)#include\s+"([^"]+)"\s*$')
def pk(path,out,depth=0):
    path=os.path.normpath(path)
    if not os.path.isfile(path): out.append(f'#error MISSING INCLUDE {path}'); return
    if depth>64: out.append("#error include too deep"); return
    for line in open(path,errors="replace").read().split("\n"):
        m=inc_re.match(line)
        if m:
            inc=m.group(2)
            nxt = R+inc if inc.startswith("/") else os.path.join(os.path.dirname(path),inc)
            out.append(f'// >>> {inc}'); pk(nxt,out,depth+1); out.append(f'// <<< {inc}')
        else: out.append(line)

raw=open(R+"/program/voxy.json").read()
raw=re.sub(r'//[^\n]*','',raw); raw=re.sub(r'(\{|,)\s*(-?\d+)\s*:', r'\1 "\2":', raw)
cfg=json.loads(raw)
TYPES={"mat4":["gbufferModelView","gbufferModelViewInverse","gbufferPreviousModelView",
               "gbufferPreviousProjection","shadowModelView","shadowModelViewInverse",
               "shadowProjection","shadowProjectionInverse","vxProj","vxProjInv"],
       "int":["vxRenderDistance","frameCounter","worldTime","worldDay","moonPhase","isEyeInWater",
              "entityId","blockEntityId","currentRenderedItemId","heldItemId","heldItemId2",
              "heldBlockLightValue","heldBlockLightValue2","renderStage"],
       "ivec2":["eyeBrightness","atlasSize"],
       "ivec3":["cameraPositionInt","previousCameraPositionInt"],
       "vec3":["cameraPosition","cameraPositionFract","previousCameraPosition",
               "previousCameraPositionFract","fogColor","skyColor","relativeEyePosition"],
       "vec4":["entityColor","lightningBoltPosition"],
       "bool":["firstPersonCamera"]}
def ty(n):
    for t,names in TYPES.items():
        if n in names: return t
    return "float"

L=[]
L.append("#version 460 core")
L.append("#define PATCHED_SHADER 1")
L.append("#define VOXY 2")
if MODE=="translucent": L.append("#define TRANSLUCENT")
L.append("#define MC_VERSION 12602")
L.append(f"#define IRIS_VERSION {IRIS}")
L += ["#define IS_IRIS","#define MC_GL_VENDOR_NVIDIA","#define MC_GL_RENDERER_GEFORCE","#define MC_RENDER_QUALITY 1.0",
      "#define MC_SHADOW_QUALITY 1.0","#define MC_NORMAL_MAP","#define MC_SPECULAR_MAP","#define MC_OS_LINUX",
      "#define MC_GL_VERSION 460","#define MC_GLSL_VERSION 460","#define IRIS_HAS_TRANSLUCENCY_SORTING",
      "#define IRIS_FEATURE_SEPARATE_HARDWARE_SAMPLERS","#define IRIS_FEATURE_HIGHER_SHADOWCOLOR","#define IRIS_FEATURE_CUSTOM_IMAGES","#define IRIS_FEATURE_PER_BUFFER_BLENDING","#define IRIS_FEATURE_COMPUTE_SHADERS","#define IRIS_FEATURE_TESSELLATION_SHADERS","#define IRIS_FEATURE_ENTITY_TRANSLUCENT","#define IRIS_FEATURE_REVERSED_CULLING","#define IRIS_FEATURE_BLOCK_EMISSION_ATTRIBUTE","#define IRIS_FEATURE_CAN_DISABLE_WEATHER","#define IRIS_FEATURE_SSBO","#define IRIS_FEATURE_FADE_VARIABLE","#define IRIS_FEATURE_TEXTURE_FILTERING","#define IRIS_TAG_SUPPORT 2"]
L.append("")
L.append("// ================= voxy: lod/gl46/quads.frag (imports resolved) =================")
vx(f"{VX}/voxy/shaders/lod/gl46/quads.frag",L)
L.append("")
L.append("// ================= voxy: buildGenericShaderHeader() =================")
L.append("")
L.append("")
L.append("layout(binding = 7, std140) uniform ShaderUniformBindings {")
bools=[]
for u in cfg["uniforms"]:
    t=ty(u)
    if t=="bool": bools.append(u); continue
    L.append(f"\t{t} {u};")
L.append("};")
L.append("")
for b in bools: L.append(f"uniform bool {b};")
L.append("#define BASE_SAMPLER_BINDING_INDEX 6")
for i,(name,stype) in enumerate(cfg["samplers"].items()):
    L.append(f"layout(binding=(BASE_SAMPLER_BINDING_INDEX+{i})) uniform {stype} {name};")
L.append("")
L.append("")
L.append(f"// ================= pack: voxy_{MODE}.glsl (includes flattened) =================")
pk(R+"/"+(sys.argv[2] if len(sys.argv)>2 else "world0")+f"/voxy_{MODE}.glsl",L)
open(OUT,"w").write("\n".join(L)+"\n")
print("wrote",OUT,len(L),"lines")
