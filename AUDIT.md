# Shaderpack audit (2026-09-14)

Findings only; nothing here has been changed. Paths are relative to `shaders/`.
Method: static scan of every option, uniform, buffer, program and include, plus an offline
glslang compile sweep of all three dimensions with the Kalic0 profile's option values applied.

## Latent load failure

- `program/shadowcomp2.glsl:9` and `:11` read `const const ivec3 workGroups`. That branch is
  compiled when `INTERACTIVE_WATER` is on and `SHADOW_QUALITY` is `0` or `-1` (both selectable),
  and the doubled keyword is a syntax error, so the whole pack fails to load in that configuration.

## Options that do nothing

Defined but never tested anywhere:

- `CONWAY`, `CONWAY_HEIGHT` (`lib/common.glsl:67`)
- `info6`, `info7` (`lib/common.glsl:416-417`, empty lang entries)
- `BRIGHTNESS_BEACONBEAM`
- `PER_BLOCK_LIGHT` (`lib/common.glsl:36`)
- `SHADOW_FRUSTUM_FIT` (`lib/common.glsl:406`)
- `ACL_CORNER_LEAK_FIX` (`lib/common.glsl:571`)

On a menu screen but never defined:

- `BLOCKLIGHT_COLOR_MODE`, `GLOWING_ORES` (`screen.BLOCKLIGHT_SETTINGS`, `shaders.properties:66`)
- `COLORED_CANDLE_LIGHT`, `COLORED_LIGHT_SATURATION` (`screen.ACL_FEATURES_SETTINGS`, `:60`)
- `screen.TNT_COL` (`:124`, linked from `:67`) lists `TNT_COL_R/G/B`; the code reads
  `EXPLODING_COL_R/G/B` (`lib/materials/lightColorSettings.glsl:346`). Stale rename.

Tested but never defined, so the branch is permanently off:

- `COLORED_CANDLE_LIGHT` at `lib/common.glsl:697` and `lib/misc/voxelization.glsl:202`
- `VBL_STRENGTH` at `lib/atmospherics/volumetricBlocklight.glsl:16`

## Orphan files

Never `#include`d by anything:

- `lib/atmospherics/volumetricBlocklight.glsl` (also depends on the undefined `VBL_STRENGTH`)
- `lib/materials/specificMaterials/entities/glowItemFrame.glsl` (entity id 50010 is handled
  inline in `program/gbuffers_entities.glsl:339` and `lib/materials/shadowChecks.glsl`)
- `program/template.glsl`

## Stale menu wiring (`shaders.properties` / `lang/en_US.lang`)

Sliders naming options that no longer exist: `ACCUM_FALLOFF_SPEED`, `BLOCKLIGHT_CHECK_INTERVAL`,
`BLOCKLIGHT_SHAFT_STRENGTH`, `BLOCKLIGHT_SOURCE_SIZE`, `BLOCKLIGHT_STRENGTH`,
`COLORED_LIGHT_SATURATION`, `DENOISE_CONVERGED_MULT`, `DENOISE_MAX_BLUR`, `DENOISE_MIN_BLUR`,
`OCCLUSION_CASCADE_COUNT`, `TNT_COL_R/G/B`, `TRANSLUCENT_LIGHT_CONDUCTION`, `VBL_STRENGTH`,
`WIRE0_BRIGHTNESS_REDSTONE` .. `WIRE3_BRIGHTNESS_REDSTONE`.

Lang keys for the same set plus `VOLUMETRIC_BLOCKLIGHT`. `WIRE_BRIGHTNESS_REDSTONE` exists but
has no lang label.

Enable directives for `world-1/shadowcomp2` and `world1/shadowcomp2` (`:177-178`) name programs
that do not exist in those folders.

## Dead uniforms

Declared in `lib/uniforms.glsl` but never read: `depthtex2`, `eyeAltitude`, `frameTime`,
`gaux2`, `isEyeInCave`, `lightningBoltPosition`, `playerMood`, `starter`, `velocity`
(`velocity` is also defined nowhere in `shaders.properties`; in taa/prepare1/deferred1/composite2
a local shadows it).

Custom-uniform chain `difX`, `difY`, `difZ`, `difSum`, `moving`, `moved` -> `starter`
(`shaders.properties:252-280`) and `isEyeInCave` are evaluated every frame and feed nothing.
Duplicate `smooth()` ids 54 (`inSoulValley`/`inPaleGarden`) and 4 (`eyeBrightnessM`/`M2`) are
harmless on Iris, which creates one smoother per call site.

## Buffers and programs

- No dead colour buffers. `colortex9`-`14` are written only by compute image stores
  (`colorimgN`), so a sampler-only scan misreports them; `colortex11` (RGBA16I) is light-sample
  storage for `prepare4_csh`.
- 27 `program.*.enabled` directives; `world1`/`world-1` lack `shadowcomp2.csh`.
- Compute sizes: `shadowcomp`/`shadowcomp1` 8x8x8 groups over a voxel volume that scales with
  the colored-light range; `deferred1_csh` half resolution; `prepare4_csh` 32x32 with render
  scale steps down to 1/8.
- `#version`: 153 programs at 130, 30 at 430, 52 at 430 compatibility. No `#extension` lines.

## Optimisation candidates

- `lib/atmospherics/fractals.glsl:44` calls `inverse(sunRotMat0)` on a rotation matrix;
  `transpose` is exact and free.
- Loop bounds worth a look: 2000-step voxel DDA (`voxelTrace`, bounded by volume exit),
  30-step reflection march, 18-tap depth of field (`composite3`), 64-sample 4x4x4 shadow gather
  (`shadowcomp`), 27-cell SDF loop (`shadowcomp_sdf_loop`).
- Sample-fetch leaders per program: `deferred1` 22, `fxaa` 19, `water` 19, `deferred1_csh` 14.

## Scaffolding to remove once voxy works

- `VOXY_DEBUG` option: `lib/common.glsl:32`, `program/voxy_opaque.glsl` (three sites),
  `program/deferred1.glsl:496-498`.
- `FIXME` at `lib/vx/voxelReading.glsl:48`.

## Compile-sweep notes

- 29 offline failures are harness gaps, not pack errors: `shadow` needs the
  `MC_RENDER_STAGE_*` macros; `gbuffers_terrain`, `gbuffers_line`, `dh_terrain`, `dh_water`,
  `gbuffers_skytextured` trip glslang on a `\` at the end of a comment line; `deferred1_csh`
  uses `gl_Fog` and `shadowcomp1_b_csh` uses `shadow2D`, both rewritten by Iris.
- The harness did not define `IRIS_VERSION` until 2026-09-14, so the three branches gated on it
  (`lib/common.glsl:750`, `connectedGlass.glsl:46`, `gbuffers_skybasic.glsl:72`) were untested
  before then.
- Likewise the `IRIS_FEATURE_*` flags (all thirteen are usable on this GPU) and
  `IRIS_TAG_SUPPORT`, added the same day after the in-game driver rejected the translucent voxy
  patch: `INTERACTIVE_WATER` is gated on `IRIS_FEATURE_HIGHER_SHADOWCOLOR`, so its samplers
  never showed up offline.
