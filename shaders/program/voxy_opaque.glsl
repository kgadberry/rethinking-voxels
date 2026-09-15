/////////////////////////////////////
// Complementary Shaders by EminGT //
/////////////////////////////////////

// Voxy appends this to its own "#version 460 core" quads.frag, so the compatibility-profile
// texture builtins the lighting chain still uses have to be mapped onto their core equivalents.
#define texture2D texture
#define shadow2D(shadowSampler, shadowCoord) vec4(texture(shadowSampler, shadowCoord))

// Voxy supplies the LOD geometry in this program and none of DH's uniforms are bound here, so the
// pack must not take its Distant Horizons paths even when that mod is installed alongside.
#undef DISTANT_HORIZONS

// voxy.json can only request Iris's canonical sampler names
#define gaux4 colortex7

//Common//
#include "/lib/common.glsl"

//Common Variables//
// Voxy exposes no vertex stage to patch, so what dh_terrain.glsl receives as a varying is either
// derived from a uniform out here or assigned from VoxyFragmentParameters before lighting runs.
vec3 upVec = normalize(gbufferModelView[1].xyz);
vec3 eastVec = normalize(gbufferModelView[0].xyz);
vec3 northVec = normalize(gbufferModelView[2].xyz);
vec3 sunVec = GetSunVector();

float SdotU = dot(sunVec, upVec);
float sunFactor = SdotU < 0.0 ? clamp(SdotU + 0.375, 0.0, 0.75) / 0.75 : clamp(SdotU + 0.03125, 0.0, 0.0625) / 0.0625;
float sunVisibility = clamp(SdotU + 0.0625, 0.0, 0.125) / 0.125;
float sunVisibility2 = sunVisibility * sunVisibility;
float shadowTimeVar1 = abs(sunVisibility - 0.5) * 2.0;
float shadowTimeVar2 = shadowTimeVar1 * shadowTimeVar1;
float shadowTime = shadowTimeVar2 * shadowTimeVar2;

#ifdef OVERWORLD
    vec3 lightVec = sunVec * ((timeAngle < 0.5325 || timeAngle > 0.9675) ? 1.0 : -1.0);
#else
    vec3 lightVec = sunVec;
#endif

// Filled in at the top of voxy_emitFragment(), before anything in the lighting chain reads them
vec3 normal = upVec;
vec4 glColor = vec4(1.0);
int mat = 0;
vec2 lmCoord = vec2(0.0);
vec2 lmCoordM = vec2(0.0);
float NdotU = 1.0;
float NdotUmax0 = 1.0;

// Declared rather than requested: nothing in Iris supplies these, so they read zero here exactly
// as they do in every other program in the pack.
uniform float maxBlindnessDarkness;
uniform float playerSize = 1.8;

// Voxy draws past the vanilla far plane with its own projection. Aliasing it onto the gbuffer
// names is what dh_terrain.glsl does with dhProjection, and leaves spaceConversion untouched.
// Iris never runs its depth transformer over this program, so under Iris 1.11.4+ the forward
// copies and the 1 - z view of gl_FragCoord that every other program receives are recreated here.
#include "/lib/vx/voxyProj.glsl"
#ifdef VOXY_FORWARD_PROJ
    mat4 gbufferProjection = voxyProjForward();
    mat4 gbufferProjectionInverse = voxyProjInvForward();
    #define gl_FragCoord vec4(gl_FragCoord.xy, 1.0 - gl_FragCoord.z, gl_FragCoord.w)
#else
    mat4 gbufferProjection = vxProj;
    mat4 gbufferProjectionInverse = vxProjInv;
#endif

//Common Functions//
float Noise3D(vec3 p) {
    p.z = fract(p.z) * 128.0;
    float iz = floor(p.z);
    float fz = fract(p.z);
    vec2 a_off = vec2(23.0, 29.0) * (iz) / 128.0;
    vec2 b_off = vec2(23.0, 29.0) * (iz + 1.0) / 128.0;
    float a = texture2D(noisetex, p.xy + a_off).r;
    float b = texture2D(noisetex, p.xy + b_off).r;
    return mix(a, b, fz);
}

//Includes//
#include "/lib/util/spaceConversion.glsl"
#include "/lib/util/dither.glsl"

#ifdef ATM_COLOR_MULTS
    #include "/lib/colors/colorMultipliers.glsl"
#endif

#define GBUFFERS_TERRAIN
    #include "/lib/lighting/mainLighting.glsl"
#undef GBUFFERS_TERRAIN

#ifdef SNOWY_WORLD
    #include "/lib/materials/materialMethods/snowyWorld.glsl"
#endif

layout(location = 0) out vec4 fragColor;

//Program//
void voxy_emitFragment(VoxyFragmentParameters parameters) {
    #if VOXY_DEBUG == 1
        fragColor = vec4(1.0, 0.0, 1.0, 1.0);
        return;
    #endif

    // Voxy hands over the raw atlas texel and the biome tint as separate values
    vec4 color = vec4(parameters.sampledColour.rgb * parameters.tinting.rgb, 1.0);

    #if VOXY_DEBUG == 2
        fragColor = color;
        return;
    #endif
    glColor = parameters.tinting;

    // parameters.lightMap arrives on the same [0.03125, 0.96875] range as the vanilla lightmap
    // texcoord, so it takes the same remap GetLightMapCoordinates() applies
    lmCoord = clamp((parameters.lightMap - 0.03125) * 1.06667, 0.0, 1.0);
    lmCoordM = lmCoord;

    // face is 0-5 as -Y +Y -Z +Z -X +X, already flipped for gl_FrontFacing by voxy
    uint faceAxis = parameters.face >> 1u;
    vec3 faceNormal = vec3(faceAxis == 2u, faceAxis == 0u, faceAxis == 1u)
                    * (float(parameters.face & 1u) * 2.0 - 1.0);
    normal = normalize(mat3(gbufferModelView) * faceNormal);
    NdotU = dot(normal, upVec);
    NdotUmax0 = max(NdotU, 0.0);

    vec3 screenPos = vec3(gl_FragCoord.xy / vec2(viewWidth, viewHeight), gl_FragCoord.z);
    vec3 viewPos = ScreenToView(screenPos);
    vec3 playerPos = ViewToPlayer(viewPos);
    float lViewPos = length(playerPos);

    float dither = Bayer64(gl_FragCoord.xy);
    #ifdef TAA
        dither = fract(dither + goldenRatio * mod(float(frameCounter), 3600.0));
    #endif

    #ifdef ATM_COLOR_MULTS
        atmColorMult = GetAtmColorMult();
    #endif

    bool noSmoothLighting = false, noDirectionalShading = false, noVanillaAO = false, centerShadowBias = false;
    int subsurfaceMode = 0;
    float smoothnessG = 0.0, smoothnessD = 0.0, highlightMult = 1.0, emission = 0.0, snowFactor = 1.0, snowMinNdotU = 0.0;
    vec3 normalM = normal, geoNormal = normal, shadowMult = vec3(1.0);
    vec3 worldGeoNormal = faceNormal; // already axis-aligned in player space, no round-trip needed

    // customId is this pack's own block.properties id, the same value gbuffers_terrain reads out
    // of mc_Entity.x, so LODs classify against the real terrain ids and not a DH-style subset
    mat = int(parameters.customId);
    if (mat == 10009) { // Leaves
        #include "/lib/materials/specificMaterials/terrain/leaves.glsl"
    } else if (mat == 10005 || mat == 10124 || mat == 10132) { // Foliage, Grass Blocks
        smoothnessG = pow2(color.g) * 0.85;
    } else if (mat == 10068) { // Lava
        emission = 1.5;
    } else if (mat == 10396 || mat == 10412 || mat == 10448 || mat == 10452 || mat == 10560 ||
               mat == 10564 || mat == 10648 || mat == 10652 || mat == 10656) {
        emission = 2.5; // Light sources bright enough to still read at LOD range
    }

    #ifdef SNOWY_WORLD
        DoSnowyWorld(color, smoothnessG, highlightMult, smoothnessD, emission,
                     playerPos, lmCoord, snowFactor, snowMinNdotU, NdotU, subsurfaceMode);
    #endif

    float lengthCylinder = max(length(playerPos.xz), abs(playerPos.y));
    highlightMult *= 0.5 + 0.5 * pow2(1.0 - smoothstep(far, far * 1.5, lengthCylinder));
    #if VOXY_DEBUG != 3
        color.a *= smoothstep(far * 0.5, far * 0.7, lengthCylinder);
        if (color.a < min(dither, 1.0)) discard;
    #endif

    vec3 noisePos = floor((playerPos + cameraPosition) * 4.0 + 0.001) / 32.0;
    float noiseTexture = Noise3D(noisePos) + 0.5;
    float noiseFactor = max0(1.0 - 0.3 * dot(color.rgb, color.rgb));
    color.rgb *= pow(noiseTexture, 0.6 * noiseFactor);

    DoLighting(color, shadowMult, playerPos, viewPos, lViewPos, geoNormal, normalM, 0.5,
               worldGeoNormal, lmCoordM, noSmoothLighting, noDirectionalShading, noVanillaAO,
               centerShadowBias, subsurfaceMode, smoothnessG, 0.0, highlightMult, emission);

    fragColor = color;
}
