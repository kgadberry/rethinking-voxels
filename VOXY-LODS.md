# Voxy LOD integration notes

How voxy LODs reach this pack's pipeline, what the LOD passes can and cannot do, and the
reasoning behind every LOD-specific rule in the code. Paths are relative to `shaders/`.
Companion client mod: `rkc/mods/voxy-revz` (reversed-Z under Iris 1.11.4, fluid height on every
LOD level). Static findings about the pack itself live in `AUDIT.md`.

## How LODs enter the pipeline

- Voxy appends `program/voxy_opaque.glsl` and `program/voxy_translucent.glsl` to its own
  `lod/gl46/quads.frag` (`#version 460 core`). The `world*/voxy_*.glsl` entry files define
  `VOXY_PATCH` plus `VOXY_OPAQUE`/`DH_TERRAIN` or `VOXY_TRANSLUCENT`/`DH_WATER`.
- The patch sees `blockModelAtlas`, `getBaseUV()` and `VoxyFragmentParameters` (sampled
  colour, tile, uv, face, model id, lightmap, tinting, `customId` = this pack's block.properties
  id). A face tile is 16 texels, `1.0/(vec2(3,2)*256)` of the atlas, so mip 4 at the tile centre
  is the tile mean. There is no voxel or section coordinate and no LOD level.
- Voxy returns helper invocations before the patch runs, so derivatives are undefined there:
  use `textureLod`/`texelFetch`. (`voxy_translucent.glsl` still computes a `dFdx` mip level that
  is dead under the current options and only feeds the sun glitter under `SHADER_STYLE 4`.)
- Only the samplers and uniforms listed in `program/voxy.json` are bound in the patch programs.
  `vxDepthTexTrans` is not bindable in the translucent pass, and the LOD passes draw to
  colortex0 only, so nothing they render has a normal, a material mask or a `translucentMult`.
- Legacy sampler names are not requestable: both patches alias `gaux4` to `colortex7`. Includes
  that read `sqrtAtmColorMult` (aurora, nebula, clouds) must come after `colorMultipliers.glsl`
  in the translucent patch; menu options can turn on such uses, so the compile sweep has to run
  with the live option file.
- Every other program takes `lib/vx/voxyAsDh.glsl`, which defines `DISTANT_HORIZONS` and
  `VOXY_AS_DH` and aliases `dhDepthTex`, `dhDepthTex1`, `dhRenderDistance` and the DH projection
  onto voxy's. The `dhRenderDistance` alias is also the uniform's declaration, so it must stay a
  bare identifier.
- Ordering: voxy draws opaque then translucent LODs inside Sodium's terrain pass. LOD water is
  therefore alpha-blended into colortex0 before deferred1, which fogs LOD pixels through its DH
  branch; loaded water draws after deferred1 and writes `translucentMult` for composite.
  colortex15 is never cleared, so during the terrain pass it holds the previous frame's deferred1
  output, water reflections included.
- Vanilla depth reads 1.0 on every LOD pixel. Any "is this sky" test must also consult the LOD
  depth; composite's underwater path does, which is what keeps LODs visible from under water.

## Distances

- `vxRenderDistance` is voxy's level-0 section reach in blocks (`sectionRenderDistance * 32`).
  Voxy's outermost nodes are level-4 sections of 512 blocks, so the LOD horizon is sixteen times
  that, and `lib/common.glsl` builds `renderDistance` accordingly under `VOXY_AS_DH`. The patch
  programs `#undef DISTANT_HORIZONS` and keep `renderDistance = far`; only the cloud threshold
  still sees that value.
- `HAZE` mixes fogged pixels toward the sky colour by `1 - exp(-3.912 * distance /
  HAZE_VISIBILITY)`, so the slider is the distance where two percent contrast remains.
  `BORDER_FOG_DISTANCE` scales the border fog as a share of `renderDistance`; the nether sites
  tagged for consistency with the view limit move with it. Both combine into `skyFade` instead
  of overwriting it.

## Debug modes

`VOXY_DEBUG`: 0 off, 1 flat magenta LODs, 2 albedo only (LOD water: the lit body alone, opaque,
no reflection), 3 no distance fade (LOD water: the reflection alone), 4 LOD depth coverage,
5 raw gbuffer colour. Mode 5 makes deferred1 return colortex0 unchanged for the whole scene, so
fog, clouds, SSAO and deferred reflections vanish everywhere; no visual judgement is valid with
it on, and it can sit unnoticed in a saved settings file.

## Water

- With `WATER_ALPHA_MULT 300` and `WATER_FOG_MULT 150` the water body is 70 to 98 percent of a
  shallow pixel, so floor changes barely show. The LOD opaque pass uses a `lightmap.y^4` sun
  fallback beyond the shadow map instead of `y^8`, since LOD floors never get a real shadow.
- `glColor.a` must be the vertex alpha, 1.0. The texel alpha (0.706 water, 0.745 ice) read as
  vanilla ambient occlusion darkened every LOD translucent by a quarter.
- `LIGHT_HIGHLIGHT` and `BLOCKLIGHT_HIGHLIGHT` are off for both `GBUFFERS_WATER` and
  `VOXY_TRANSLUCENT`: the reflection already carries the sun lobe weighted by fresnel, and
  adding it again in the lighting pass gave LOD water 2.55 times the highlight, worst with the
  sun near the mirror angle.
- The cloud distance fade must not branch on `DISTANT_HORIZONS` inside the patch (gated on
  `!defined VOXY_PATCH`), or LOD reflections keep more lit cloud than loaded water does.
- LOD reflections (`reflections.glsl`, Method 3) march 28 steps against `vxDepthTexOpaque` with
  four bisection steps, thickness floor `max(1.0, 0.03 * depth)` and bias `max(0.5, 0.002 *
  depth)`; raising the thickness floor produces false hits on open ocean. A hit must rise more
  than `max(0.25, 0.002 * lViewPos)` above the water plane, because voxy bakes seagrass and kelp
  as cubes that top out one eighth of a block above the fluid and a hit on them smears green
  over the surrounding water. Everything else falls to the sky. deferred1 writes alpha 0 into
  colortex15 on LOD-water pixels so last frame's water can never feed itself back.
- The translucent LOD fade uses the same cylinder as the opaque one; a doubled vertical term
  drew LOD water and ice over LOD terrain that had already been discarded.

## Ice and other translucents

- Voxy sends every translucent block through the translucent pass. Only water (32000) and ice
  (32004) have material handling there; ice takes the IPBR constants (reflectMult 0.7). Glass
  would be `smoothnessG = 1.0; highlightMult = 3.5; reflectMult = 0.5;` and tinted glass
  `color.a = pow(color.a, 1.0 - fresnel * 0.65); reflectMult = 0.75;` if wanted; stained glass,
  slime, honey and portals need `translucentMult`, which the patch cannot write.
- `LOD_ICE_EDGE_FIX` discards vertical loaded-ice faces past `far * 0.85` where LOD depth
  exists. Sodium emits the outward face of the last loaded ice block because its neighbour is
  unloaded, and lights it from that neighbour as full sky.
- LOD ice reads clearer than nearby loaded ice because loaded ice multiplies its background by
  `translucentMult`, which the pack fades to 1.0 at the far plane; at the handoff the two agree.
  Matching LOD ice to near ice would create a seam at the boundary, so it is left alone.
- Seams between LOD sections are voxy geometry: `RenderDataFactory.acquireNeighborData` culls
  same-model translucent faces only against same-level neighbours (`world.acquire(section.lvl,
  ...)`), so every LOD-level ring keeps its internal faces, and the patch cannot tell those from
  real faces. A voxy-revz mixin that falls back to the level-above neighbour when the same-level
  one is empty (each coarse voxel duplicated 2x2 into the 32x32 face slice) closes the common
  case; the general ring mismatch needs draw-time knowledge. The same seams and the underwater
  LOD look reproduce with shaders off, so they are not the pack's.
- Voxy does emit the water face under ice: ice is in the translucent layer, so it occludes
  nothing.

## Lava, light sources, foliage

- LOD lava follows the loaded path per resource-pack mode. Under IPBR it ports `lava.glsl`
  with the atlas tile mean standing in for the texel average; under labPBR/SEUS modes it uses
  `0.03 * CUSTOM_EMISSION_INTENSITY`, since the patch has no specular map and labPBR packs mark
  lava fully emissive; in vanilla mode it has no emission. Outside IPBR the patch also clamps
  full-bright lightmaps to 0.95 the way `gbuffers_terrain` does, where the blocklight curve is
  sane. LOD light sources keep a deliberate flat emission of 2.5 so they read at LOD range.
- Ground foliage ids 10005, 10017 and 10021 get `subsurfaceMode 1`, `noSmoothLighting` and
  `noDirectionalShading` like loaded plants, and the subsurface gates in `mainLighting.glsl`
  accept `VOXY_OPAQUE`. Voxy bakes leaves solid, which needs nothing.
- Vanilla face shade (0.6/0.8/1.0) is not baked into voxy's atlas, so LOD side faces are
  brighter than loaded ones. Open.

## Colored light and the nether

- Per pixel (at `BLOCKLIGHT_RESOLUTION`) the pack cone-traces toward up to `MAX_TRACE_COUNT`
  lights, each up to `RT_STEPS` SDF steps. GI already runs per voxel per frame into the
  irradiance cache, so bounce rays are cached, not per pixel. `shadowcomp1`'s per-voxel direct
  light is capped at `MAX_TRACE_COUNT` too.
- `LIGHT_CLUMPING` merges still block lights into world-aligned 4x2x4 cells (grid from
  `cameraPositionInt`, with the sentinel fallback to `floor(cameraPosition)`). Only lights with
  the same occupancy bits 17-26 (level and material class) merge, entity lights (bit 27) are
  left to their own pass, and cells whose centre is within `LIGHT_CLUMP_MIN_DIST` of the camera
  stay exact. The representative is the cell-min corner, promoted with bit 16 and the key when
  no light sits there; the merged entry lives at that corner's hash with corner-relative sums,
  word 3's upper bits carry `0x8000 | N` and readers scale the mean colour by N. Members lose
  bit 16 and readers redirect through `lightClumpCellMin`. A cell whose mean position falls in a
  solid voxel does not merge. Emissive blocks are not in the SDF (`shadow.glsl` voxelizes
  emissive faces instead of solid ones), so a mean inside a glowstone cluster traces fine.
- `LIGHT_CUTOFF` skips a trace when the light's unoccluded bound (colour, falloff, brightness,
  N.L) is below that percent of the light already accumulated, plus a 1e-4 floor. Skipped traces
  do not count against the budget. A light skipped by every pixel of a tile drops out of the
  previous-frame list but is re-found by the per-pixel discovery ray and the neighbour scan.
- Occupancy bits: 0-7 solid per SDF level, 8-15 translucent per level, 16 light, 17-21 level,
  22-26 material class, 27 entity light, 28-29 skylight. There are no free bits.
- What to watch: nether frame time over lava and fire; a glowstone cluster 20+ blocks away
  staying one bright source; torch rows near the player unchanged; hot spots every four blocks
  on lava shores; two same-kind lights either side of a one-block wall merging; caves at the
  edge of torch range with the cutoff at 1.

## Compile sweep

`tools/sweep/sweep.sh` assembles every program the way Iris does (world defines,
`IRIS_VERSION`, the `IRIS_FEATURE_*` flags, `IRIS_TAG_SUPPORT`) and the six patch variants the
way voxy's pipeline does, applies an Iris settings file, and runs glslangValidator. It needs
`glslangValidator` on the path (`nix-shell -p glslang`).

By default it runs a matrix: pack programs for LOD mode `voxy` (`VOXY 2`), `none` (no LOD mod:
the `#ifndef DISTANT_HORIZONS` fog and cloud paths) and `dh` (Iris with real Distant Horizons
defines `DISTANT_HORIZONS`, which is what the pack keys on) times `IRIS_VERSION` 11104 and
11103 (the `#else` branches of `voxyProj.glsl`, `voxyAsDh.glsl`, `voxy_opaque/translucent`),
and the voxy patches for both Iris versions. Each config writes `r_<tag>_<config>.txt`
(`voxy-11104`, `none-11103`, `patch-11104`, ...) and its own log directory under `SWEEP_OUT`.

Inputs: `SWEEP_OPTS` (the profile's `<pack>.zip.txt`), `VOXY_JAR` (voxy's shader sources are
extracted from it; without it the patch variants are skipped), `SWEEP_OUT`, `SWEEP_TAG`,
`SWEEP_LODS` and `SWEEP_IRIS` (space separated overrides of the matrix), `SWEEP_ONLY` (extended
regex on result names such as `world0_gbuffers_water_fsh` or `voxy_world0_translucent`) and
`SWEEP_BASELINE` (directory of result files from an earlier run with the same tag).

About 26 programs per config fail only because the harness does not emulate what Iris injects
(`DH_BLOCK_LEAVES`, `MC_RENDER_STAGE_*`, `projectionMatrix`, `gl_Fog`, `shadow2D`,
`dhMaterialId`, `dhProjection` in the dh programs), so the raw FAIL count is no regression
signal. Take a baseline from the known-good tree and rerun with `SWEEP_BASELINE`: it prints
`NEW FAIL <config> <name>` for every program that fails now but passed (or was absent) there,
and exits non-zero if there is any. Because the sweep reads the live settings, the baseline
moves when options change in-game, and branches the live options never select (IPBR lava,
unbound clouds) need a second run with an edited option file.

## Open items

- Seams between LOD sections and the underwater LOD look: voxy-side, see above.
- LOD translucents have no refraction (composite's `DoRefraction` gates on a material mask the
  patch never writes) and no `translucentMult`.
- The GI ambient normal for LOD translucents still uses `+normalM` at full weight where loaded
  water uses the downward half-weight hemisphere (`mainLighting.glsl`, the `#ifndef
  GBUFFERS_WATER` branch). Untested because the irradiance cache cannot be measured offline.
- LOD wave normals are continuous where loaded ones snap to a 1/16 block grid; sub-pixel at LOD
  range.
- LOD light sources at emission 2.5 versus about 0.93 loaded under labPBR.
- Glass and tinted glass constants for the LOD translucent pass, above.
- `RenderDataFactory.generateMesh` never clears `neighboringFaces` between sections; unproven.
