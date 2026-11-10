# Flatten one pack program the way Iris does, with its standard macros, for glslang.
import os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
R = os.environ.get("PACK_ROOT", os.path.normpath(os.path.join(HERE, "..", "..", "shaders")))
entry=sys.argv[1]          # e.g. world0/deferred1.fsh
out=sys.argv[2]
# argv[3] = LOD mode: voxy (VOXY 2), dh (DISTANT_HORIZONS, as Iris defines it with the real DH mod)
# or none (neither); argv[4] = IRIS_VERSION (default 11104)
lod = sys.argv[3] if len(sys.argv)>3 else "voxy"
iris = sys.argv[4] if len(sys.argv)>4 else "11104"
if lod not in ("voxy","dh","none"): sys.exit("LOD mode must be voxy, dh or none")

inc_re=re.compile(r'^(\s*)#include\s+"([^"]+)"\s*$')
def pk(path,acc,depth=0):
    path=os.path.normpath(path)
    if not os.path.isfile(path): acc.append(f'#error MISSING INCLUDE {path}'); return
    if depth>64: acc.append("#error include too deep"); return
    for line in open(path,errors="replace").read().split("\n"):
        m=inc_re.match(line)
        if m:
            i=m.group(2)
            nxt = R+i if i.startswith("/") else os.path.join(os.path.dirname(path),i)
            acc.append(f'// >>> {i}'); pk(nxt,acc,depth+1); acc.append(f'// <<< {i}')
        else: acc.append(line)

body=[]
pk(os.path.join(R,entry),body)
# Iris standard macros injected after #version
macros=["#define MC_VERSION 12602","#define IS_IRIS","#define MC_GL_VENDOR_NVIDIA",
        "#define MC_GL_RENDERER_GEFORCE","#define MC_RENDER_QUALITY 1.0",
        "#define MC_SHADOW_QUALITY 1.0","#define MC_NORMAL_MAP","#define MC_SPECULAR_MAP",
        "#define MC_OS_LINUX","#define MC_GL_VERSION 460","#define MC_GLSL_VERSION 460",
        f"#define IRIS_VERSION {iris}","#define IRIS_HAS_TRANSLUCENCY_SORTING",
        "#define IRIS_FEATURE_SEPARATE_HARDWARE_SAMPLERS","#define IRIS_FEATURE_HIGHER_SHADOWCOLOR","#define IRIS_FEATURE_CUSTOM_IMAGES","#define IRIS_FEATURE_PER_BUFFER_BLENDING","#define IRIS_FEATURE_COMPUTE_SHADERS","#define IRIS_FEATURE_TESSELLATION_SHADERS","#define IRIS_FEATURE_ENTITY_TRANSLUCENT","#define IRIS_FEATURE_REVERSED_CULLING","#define IRIS_FEATURE_BLOCK_EMISSION_ATTRIBUTE","#define IRIS_FEATURE_CAN_DISABLE_WEATHER","#define IRIS_FEATURE_SSBO","#define IRIS_FEATURE_FADE_VARIABLE","#define IRIS_FEATURE_TEXTURE_FILTERING","#define IRIS_TAG_SUPPORT 2"]
if lod=="voxy": macros.append("#define VOXY 2")
if lod=="dh": macros.append("#define DISTANT_HORIZONS")
L=[]
for line in body:
    L.append(line)
    if line.startswith("#version"): L.extend(macros)
# The pack's ASCII-art banners end lines with "\\" inside comments; glslang treats that as an
# unsupported line continuation where NVIDIA/Iris do not. Strip it only inside comments.
def _decomment(lines):
    out=[]; inblk=False
    for l in lines:
        incmt = inblk or l.lstrip().startswith("//")
        # update block state for the NEXT line
        i=0
        while i < len(l)-1:
            if not inblk and l[i:i+2]=="/*": inblk=True; i+=2; continue
            if inblk and l[i:i+2]=="*/": inblk=False; i+=2; continue
            if not inblk and l[i:i+2]=="//": break
            i+=1
        out.append(l[:-1] if (incmt and l.endswith("\\")) else l)
    return out
L=_decomment(L)
open(out,"w").write("\n".join(L))
