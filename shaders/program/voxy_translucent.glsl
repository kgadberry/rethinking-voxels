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

// Voxy never jitters its projection, so the un-jitter water.glsl applies under TAA must be a no-op
#define TAAJitter(coord, w) (coord)

//Common//
#include "/lib/common.glsl"

//Common Variables//
// Voxy exposes no vertex stage to patch, so what dh_water.glsl receives as a varying is either
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
vec3 playerPos = vec3(0.0);
vec3 viewVector = vec3(0.0);
mat3 tbnMatrix = mat3(1.0);

// Declared rather than requested: nothing in Iris supplies these, so they read zero here exactly
// as they do in every other program in the pack.
uniform float maxBlindnessDarkness;
uniform float playerSize = 1.8;

// Voxy draws past the vanilla far plane with its own projection. Aliasing it onto the gbuffer
// names is what dh_water.glsl does with dhProjection, and leaves spaceConversion untouched.
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

//Includes//
#include "/lib/util/dither.glsl"
#include "/lib/util/spaceConversion.glsl"
#include "/lib/lighting/mainLighting.glsl"

#ifdef OVERWORLD
    #include "/lib/atmospherics/sky.glsl"
#endif

// The sky effects below scale by the atmosphere multiplier, so it has to be declared first
#ifdef ATM_COLOR_MULTS
    #include "/lib/colors/colorMultipliers.glsl"
#endif

#if WATER_REFLECT_QUALITY >= 0
    #if defined SKY_EFFECT_REFLECTION && defined OVERWORLD
        #if AURORA_STYLE > 0
            #include "/lib/atmospherics/auroraBorealis.glsl"
        #endif

        #ifdef NIGHT_NEBULA
            #include "/lib/atmospherics/nightNebula.glsl"
        #else
            #include "/lib/atmospherics/stars.glsl"
        #endif

        #ifdef VL_CLOUDS_ACTIVE
            #include "/lib/atmospherics/clouds/mainClouds.glsl"
        #endif
    #endif

    #include "/lib/materials/materialMethods/reflections.glsl"
#endif

#ifdef MOON_PHASE_INF_ATMOSPHERE
    #include "/lib/colors/moonPhaseInfluence.glsl"
#endif

layout(location = 0) out vec4 fragColor;

//Program//
void voxy_emitFragment(VoxyFragmentParameters parameters) {
    #if VOXY_DEBUG == 1
        fragColor = vec4(0.0, 1.0, 1.0, 1.0);
        return;
    #endif

    // Texel alpha times tint alpha is what gbuffers_water starts from; the tint is the biome water colour
    float alpha = parameters.sampledColour.a * parameters.tinting.a;
    // glColor is the vertex colour, whose alpha DoLighting reads as vanilla AO - and vanilla leaves
    // that 1.0 on fluids, so handing it the texel's 0.706 dimmed every LOD water pixel by a quarter.
    glColor = vec4(parameters.tinting.rgb, 1.0);
    // Raw texel like gbuffers_water's tex sample; voxy bakes fluids through the vanilla FluidRenderer
    vec4 colorP = vec4(parameters.sampledColour.rgb, alpha);
    vec4 color = vec4(parameters.sampledColour.rgb * parameters.tinting.rgb, alpha);

    // miplevel.glsl measures sprite fractions per pixel times 16; a voxy atlas tile spans (1/768, 1/512) of uv
    vec2 mipx = dFdx(parameters.uv) * vec2(768.0, 512.0) * 16.0;
    vec2 mipy = dFdy(parameters.uv) * vec2(768.0, 512.0) * 16.0;
    float miplevel = max(0.5 * log2(max(dot(mipx, mipx), dot(mipy, mipy))), 0.0);

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
    tbnMatrix = mat3(
        eastVec.x, northVec.x, normal.x,
        eastVec.y, northVec.y, normal.y,
        eastVec.z, northVec.z, normal.z
    );

    vec3 screenPos = vec3(gl_FragCoord.xy / vec2(viewWidth, viewHeight), gl_FragCoord.z);
    vec3 viewPos = ScreenToView(screenPos);
    playerPos = ViewToPlayer(viewPos);
    float lViewPos = length(playerPos);
    viewVector = tbnMatrix * viewPos;
    vec3 nViewPos = normalize(viewPos);
    float VdotU = dot(nViewPos, upVec);
    float VdotS = dot(nViewPos, sunVec);

    float dither = Bayer64(gl_FragCoord.xy);
    #ifdef TAA
        dither = fract(dither + goldenRatio * mod(float(frameCounter), 3600.0));
    #endif

    #ifdef ATM_COLOR_MULTS
        atmColorMult = GetAtmColorMult();
        sqrtAtmColorMult = sqrt(atmColorMult);
    #endif

    bool noSmoothLighting = false, noDirectionalShading = false, noVanillaAO = false, centerShadowBias = false;
    int subsurfaceMode = 0;
    float smoothnessG = 0.0, highlightMult = 0.0, emission = 0.0, materialMask = 0.0, reflectMult = 0.0;
    vec3 normalM = normal, geoNormal = normal, shadowMult = vec3(1.0);
    vec3 worldGeoNormal = faceNormal; // already axis-aligned in player space, no round-trip needed
    float fresnel = clamp(1.0 + dot(normalM, nViewPos), 0.0, 1.0);

    // customId is this pack's own block.properties id, the same value gbuffers_water reads out of mc_Entity.x
    mat = int(parameters.customId);
    if (mat == 32000) { // Water
        #include "/lib/materials/specificMaterials/translucents/water.glsl"
    } else if (mat == 32004) { // Ice
        // translucentMaterials.glsl's own constants. Without them reflectMult stays zero, so the
        // shared reflection block below gave LOD ice neither a sky reflection nor a highlight.
        smoothnessG = pow2(color.g) * color.g;
        highlightMult = pow2(min1(pow2(color.g) * 1.5)) * 3.5;
        reflectMult = 0.7;
    }

    // Fade in over the same band the opaque patch dithers in over, so LODs never show inside loaded
    // terrain. Its y term carries no factor, and doubling ours drew LOD ice over discarded LOD land.
    float lengthCylinder = max(length(playerPos.xz), abs(playerPos.y));
    color.a *= smoothstep(far * 0.5, far * 0.7, lengthCylinder);

    DoLighting(color, shadowMult, playerPos, viewPos, lViewPos, geoNormal, normalM, 0.5,
               worldGeoNormal, lmCoordM, noSmoothLighting, noDirectionalShading, noVanillaAO,
               centerShadowBias, subsurfaceMode, smoothnessG, materialMask, highlightMult, emission);

    #if VOXY_DEBUG == 2 // the lit water body alone, opaque, so the reflection cannot mask it
        fragColor = vec4(color.rgb, 1.0);
        return;
    #endif

    // Reflections
    #if WATER_REFLECT_QUALITY >= 0
        #ifdef LIGHT_COLOR_MULTS
            highlightColor *= lightColorMult;
        #endif
        #ifdef MOON_PHASE_INF_REFLECTION
            highlightColor *= pow2(moonPhaseInfluence);
        #endif

        float fresnelM = (pow3(fresnel) * 0.85 + 0.15) * reflectMult;

        float skyLightFactor = pow2(max(lmCoordM.y - 0.7, 0.0) * 3.33333);
        #if SHADOW_QUALITY > -1 && WATER_REFLECT_QUALITY >= 2 && WATER_MAT_QUALITY >= 2
            skyLightFactor = max(skyLightFactor, min1(dot(shadowMult, shadowMult)));
        #endif

        vec4 reflection = GetReflection(normalM, viewPos.xyz, nViewPos, playerPos, lViewPos, -1.0,
                                        vxDepthTexOpaque, dither, skyLightFactor, fresnel,
                                        smoothnessG, geoNormal, color.rgb, shadowMult, highlightMult);

        #if VOXY_DEBUG == 3 // the reflection alone, opaque, before fresnel weights it in
            fragColor = vec4(reflection.rgb, 1.0);
            return;
        #endif

        color.rgb = mix(color.rgb, reflection.rgb, fresnelM);
    #endif
    ////

    // No DoFog here: this blends into colortex0 before deferred, which fogs every LOD pixel itself
    // from dhDepthTex, and voxyAsDh.glsl points that at the depth this program writes.
    fragColor = color;
}
