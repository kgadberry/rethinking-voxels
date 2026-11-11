# Voxy LOD integration notes

How voxy LODs reach this pack's pipeline, what the LOD passes can and cannot do, and the
reasoning behind every LOD-specific rule in the code. Paths are relative to `shaders/`.
Required client mod on Minecraft 26.2: `rkc/mods/voxy-revz` (reversed-Z under Iris 1.11.4, fluid
height on every LOD level; see "voxy-revz"). Static findings about the pack itself live in
`AUDIT.md`.

## How LODs enter the pipeline

- Voxy appends `program/voxy_opaque.glsl` and `program/voxy_translucent.glsl` to its own
  `lod/gl46/quads.frag` (`#version 460 core`). The `world*/voxy_*.glsl` entry files define
  `VOXY_PATCH` plus `VOXY_OPAQUE`/`DH_TERRAIN` or `VOXY_TRANSLUCENT`/`DH_WATER`.
- The patch sees `blockModelAtlas`, `getBaseUV()` and `VoxyFragmentParameters` (sampled
  colour, tile, uv, face, model id, lightmap, tinting, `customId` = this pack's block.properties
  id). A face tile is 16 texels, `1.0/(vec2(3,2)*256)` of the atlas, so mip 4 at the tile centre
  is the tile mean. There is no voxel or section coordinate and no LOD level.
- Derivatives are undefined in the patches. Voxy's `quads.frag` returns from every helper
  invocation (`gl_HelperInvocation`) unless `PATCHED_SHADER_ALLOW_DERIVATIVES` is defined, which
  voxy never does and a patch appended after `main()` cannot, and it discards per pixel before
  calling the patch. The patch therefore runs in non-uniform control flow, where `dFdx`, `dFdy`
  and `fwidth` are undefined; `parameters.uv` is also wrapped per tile. Use `textureLod`/
  `texelFetch`. `voxy_translucent.glsl` estimates the water-highlight mip level from distance,
  `P[1][1]`, `viewHeight` and N.V (world blocks, 16 texels each, not LOD voxels), and
  `mainLighting.glsl` skips the fake variable penumbra under `VOXY_PATCH`.
- Only the samplers and uniforms listed in `program/voxy.json` are bound in the patch programs.
  Every uniform that `lib/uniforms.glsl` hides under `VOXY_PATCH` and that the patch include tree
  can read under some option set must be listed there, custom uniforms included (`rainFactor`,
  `inDry`, `inRainy`, `inSnowy`, `eyeBrightnessM`, `maxBlindnessDarkness` and the five nether
  biome factors). A custom uniform reaches voxy even when only the LOD patches use it, because
  voxy builds its uniform set before Iris's `CustomUniforms.optimise()` runs. Both patches used
  to declare `maxBlindnessDarkness` locally; that declaration is gone, the uniform now comes
  from `voxy.json`. `playerSize` has no Iris source and stays a local `= 1.8` declaration.
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
- The patches read `vxDepthTexOpaque` untransformed, and only through `VoxyOpaqueDepth`
  (`lib/vx/voxyProj.glsl`). There are two conventions. On Iris 1.11.4+ (`IRIS_VERSION >= 11104`)
  voxy must be on reversed-Z, which on voxy 0.2.19 only voxy-revz provides (0.2.19 draws forward
  whenever any Iris pack is active, `RenderProperties.useReverseZ`); there the patches use the
  forward projection copies (`voxyProjForward()`, `voxyProjInvForward()`) in place of voxy's
  reversed matrices and `VoxyOpaqueDepth` is `1 - depth`. On older Iris voxy draws forward, the
  matrices are used as they are and `VoxyOpaqueDepth` is the raw value. In both a texel without
  LOD geometry reads 1.0 (voxy's far: its clear and its depth fix-up over vanilla terrain).
- Ordering: voxy draws opaque then translucent LODs inside Sodium's terrain pass. LOD water is
  therefore alpha-blended into colortex0 before deferred1, which fogs LOD pixels through its DH
  branch; loaded water draws after deferred1 and writes `translucentMult` for composite.
  colortex15 is never cleared, so during the terrain pass it holds the previous frame's deferred1
  output, water reflections included.
- Vanilla depth reads 1.0 on every LOD pixel, so any "is this sky" test must also consult the
  LOD depth. Composite's underwater path does (`trueSky0`/`trueSky1`), and so does the
  light-shaft march: `GetVolumetricLight` takes its length from `GetDepth(z1)`, which is `far`,
  the sky's march, on an LOD texel. Under water, where the distance scaling at the end of that
  function does not run, it now marches LOD and DH texels as far as a loaded block at the same
  position would. Before that, LOD terrain under water gathered the sky's shaft light, including
  unshadowed samples past the shadow map, and could not be told from open water, while loaded
  chunks popped in darker. The shadow pass also draws only loaded sections, so under water a
  shaft sample past the loaded edge found no water above it, read as lit and dry and was
  zeroed, and each chunk that loaded added its shafts to every texel behind it. Such a sample
  now takes the mean of the ray's earlier water samples, up to the first LOD translucent face
  (the LOD surface seen from below).
- Voxy does not draw LODs inside loaded sections. `quads.frag` discards any LOD fragment in
  front of its depth-bounding buffer, which `BoundRenderer` fills with the far faces of every
  built section Sodium visits, and `initDepthStencil` masks every pixel that holds vanilla
  opaque depth (the translucent pass runs with the same stencil test). The patches' fade over
  0.5 to 0.7 of `far` therefore only matters in holes, where chunks are still loading.

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
  of overwriting it, except in the forward translucent passes (gbuffers_water, translucent
  entities, beacon beams, dh_water). There `skyFade` becomes an alpha cut, so `DoHaze` leaves it
  alone: those layers get the haze only as a colour mix, and their alpha is cut by border fog
  alone. The dark outline fogs its own zero-initialised `skyFade` and, when that is above zero,
  replaces the pixel's with it. Under voxy that border-fog cut is measured against the LOD
  horizon (`renderDistance`), so it is about zero at the vanilla edge and loaded translucents
  are not dissolved where the LODs begin.
- Bloom fog measures LOD texels at their own distance in every dimension (the pass that
  multiplies it in and `composite5`, which divides it back out, read the same distance). Vanilla
  depth is the far plane on every LOD texel, which used to give LODs full bloom fog right past
  the vanilla render distance: a brightness step at the handoff at night and in rain.

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
  Loaded terrain between the end of the shadow map (11/12 of `min(shadowDistance, far)`) and
  the loaded edge gets no real shadow either, and used to take `y^8` there: a floor under two,
  four or six blocks of water came out 2.4, 5 or 12 times darker than the LOD floor beside it,
  so blocks visible under LOD ice sank into the dark as their chunk loaded. Under voxy,
  `gbuffers_terrain` and `gbuffers_block` now ramp the fallback from `y^8` to `y^4` over the
  last 16 blocks before `far` (the cylinder distance Sodium and voxy cull by), so loaded terrain
  meets the LODs' value at the edge, above water and below. Shaded loaded terrain in that last
  stretch is lighter for it, as the LOD terrain behind it already was. Real DH and setups
  without LODs keep `y^8` throughout.
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
  over the surrounding water. Everything else falls to the sky. colortex15 holds last frame's
  image, so a verified hit is reprojected into the previous frame (player space plus the
  `cameraPositionInt`/`cameraPositionFract` offset, then `gbufferPreviousModelView` and
  `gbufferPreviousProjection`) and colortex15 is sampled there. Iris's previous projection is
  valid for this because `vxProj` shares the vanilla projection's x, y and w rows. A hit behind
  the previous camera, or outside the `rEdge` box the march used, falls to the sky like a miss;
  a hit just past the screen edge but inside that box samples colortex15's clamped edge texel.
  deferred1 writes alpha 0 into colortex15 on LOD-water pixels so last frame's water can never
  feed itself back.
- The translucent LOD fade uses the same cylinder as the opaque one; a doubled vertical term
  drew LOD water and ice over LOD terrain that had already been discarded.

## Ice and other translucents

- Voxy sends every translucent block through the translucent pass. Only water (32000) and ice
  (32004) have material handling there. Ice takes the IPBR constants (reflectMult 0.7) only
  under `IPBR`, as `gbuffers_water` does. In the other pack modes loaded ice reads its material
  from the resource pack's specular map (`reflectMult = smoothnessD`), which voxy's atlas does
  not carry; Iris binds an all-zero map where a pack has none, so LOD ice keeps zeros there and
  both are matte. A pack that does give ice a specular map reflects up close and not as LOD.
  Glass would be `smoothnessG = 1.0; highlightMult = 3.5; reflectMult = 0.5;` and tinted glass
  `color.a = pow(color.a, 1.0 - fresnel * 0.65); reflectMult = 0.75;` if wanted; stained glass,
  slime, honey and portals need `translucentMult`, which the patch cannot write.
- Voxy draws translucent quads with face culling off (`MDICSectionRenderer.renderTranslucent`)
  and turns `parameters.face` toward the camera, so the far side of a translucent block showed
  as a second layer: under an ice sheet, its underside lit from the water voxel below, which
  made an unbroken LOD ice sheet denser than loaded ice. The translucent patch now discards a
  quad seen from behind (`parameters.face != getFace()`), as loaded translucent terrain is
  back-face culled. Water keeps both sides, because vanilla's fluid renderer adds a reversed
  copy of its faces and underwater views need it.
- LODs are never voxelized: they lie outside every section the shadow pass draws. Inside the
  voxel volume the irradiance cache at an LOD's position holds only light diffused out of the
  loaded area, which came out darker than an open surface gets, so LOD ice, water and terrain
  within the volume read darker than their loaded neighbours. `mainLighting.glsl` now gives the
  LOD programs (`DH_TERRAIN`, `DH_WATER`) this texel's vanilla ambient as the cache value, which
  is what `shadowcomp1` settles on for an open surface; the compression, the `GI_AMBIENT_MIN`
  floor and the `voxelFactor` fade then run unchanged. Side faces and partly covered LOD
  surfaces get the same stand-in rather than their own hemisphere value. With the eye under
  water every LOD program reads the cache as loaded geometry does instead, because the stand-in
  is a sky-lit surface and falls with sky light where the cache's sky term is capped, which
  left submerged LODs at about half the ambient of their loaded neighbours. From above, a
  submerged LOD floor inside the volume therefore stays darker in ambient than the loaded floor
  beside it (about 0.95, 0.75 to 0.9 and 0.5 to 0.7 of it under two, four and six blocks of
  water). The opaque patch cannot tell a submerged floor from a cave: its parameters carry no
  fluid flag and LOD translucents draw after it. The volume is a box, so at `VX_VOL_SIZE 0` it
  reaches about 68 blocks toward its corners.
- Loaded and LOD ice cover the same share of a pixel, 0.745. Every texel of `ice.png` has alpha
  190, voxy's software bake rasterises one winding per view so each face texture is a single
  unblended layer, mips of a uniform alpha are unchanged, both samplers are nearest within a
  level, and no alpha term touches ice in either path. A difference in how solid the two look
  is therefore a lighting difference.
- Loaded water at the loaded edge: a view ray that leaves the loaded area under water has an LOD
  floor behind it, but `depthtex1` is empty there, so the water measured as bottomless and came
  out opaque in a band just inside the edge, visible from above in shallow water. Under voxy,
  `water.glsl` now measures to `dhDepthTex1` when vanilla depth is empty.
- `LOD_ICE_EDGE_FIX` is gone. It discarded vertical loaded-ice faces in the outer 15 percent of
  the render distance on the theory that a stray face of the last loaded ice block drew a line.
  No such face exists (translucent terrain is back-face culled and Sodium meshes a chunk only
  once all 8 neighbours are loaded), so it only cut genuine ice sides, and it made no visible
  difference in game. A lesson from it: Iris registers a boolean define as an option only when
  some source names it on a plain `#ifdef` or `#ifndef` line, so an option used only inside a
  compound `#if defined ... &&` needs a line in the Activate Settings block of `lib/common.glsl`.
- `translucentMult` is not a visible difference between loaded and LOD ice. It never multiplies
  the background colour: composite only uses it to tint light-shaft, coloured-light-fog, nether
  storm and rainbow samples behind the surface, and `gbuffers_water` fades it to 1.0 at `far`.
  The mismatch at the handoff came from the material mode, the second layer and the cache value,
  all above.
- Seams between LOD sections are voxy geometry: `RenderDataFactory.acquireNeighborData` culls
  same-model translucent faces only against same-level neighbours (`world.acquire(section.lvl,
  ...)`), so every LOD-level ring keeps its internal faces, and the patch cannot tell those from
  real faces. A voxy-revz mixin that falls back to the level-above neighbour when the same-level
  one is empty (each coarse voxel duplicated 2x2 into the 32x32 face slice) closes the common
  case; the general ring mismatch needs draw-time knowledge. The same seams reproduce with
  shaders off, so they are not the pack's. LODs also fade under water with shaders off, but for
  a voxy-only reason: `NormalRenderPipeline` fogs them with the vanilla water fog and skips the
  LOD blit while that fog ends inside the vanilla render distance. Under Iris, voxy has no fog
  or eye-in-fluid logic.
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
- `INFESTED_DEEPSLATE_GLOW` (VX_SETTINGS, default on, "Glowing Infested Deepslate") gates the
  light emitter for the void-infused deepslate of the player-portals mod, which reaches the
  client as sideways infested deepslate: block 10110, the held/dropped item remap 10111 to 10110
  in `shadow.glsl`, and voxelizer id 29. Turn it off in vanilla worlds, where it would light
  real infested deepslate.

## Colored light and the nether

- Per pixel (at `BLOCKLIGHT_RESOLUTION`) the pack cone-traces toward up to `MAX_TRACE_COUNT`
  lights, each up to `RT_STEPS` SDF steps. GI already runs per voxel per frame into the
  irradiance cache, so bounce rays are cached, not per pixel. `shadowcomp1`'s per-voxel direct
  light is capped at `MAX_TRACE_COUNT` too.
- Where the detail comes from. The shadow pass voxelizes each face into as many levels as its
  distance allows (`getVoxelResolution`): with `VX_VOL_SIZE 0` that is 16 per block within about
  3 blocks, 8 within 6, 4 within 12, 2 within 24 and 1 per block beyond, so block-light shadows
  past about 24 blocks out are one voxel per block by design. A gbuffers pixel searches
  colortex8 for its own normal and depth and reads the per-pixel trace on a match; otherwise it
  reads the irradiance cache, which holds one value per block and is re-traced and overwritten
  each frame near the camera, so a failed match looks blocky and flickers. LOD texels never
  match, so they always read the cache. At `BLOCKLIGHT_RESOLUTION 1` `prepare4_csh_a` applies
  no temporal filter at all, so 1 flickers more than 2.
- Translucents never take the per-pixel path: the colortex8 search is compiled out for
  `GBUFFERS_WATER`, so water, ice and glass always read the cache, half a block out along the
  face normal (the wave-bumped normal made the read swim across the block grid). They are not
  in the distance field either, so the cache voxel in front of one takes its N.L from the
  nearest opaque surface. One value per block is all the cache holds, so their block-light
  shadows are block-sized; only a trace in the translucent pass itself would change that.
- The cache's block-light half is blended over time at the write in `shadowcomp1` (a fresh
  trace enters at 0.2, more where a voxel is retraced less often), so its readers no longer
  show the per-frame dither of the cone traces as flicker; lights settle over about five
  frames on those surfaces. Alpha there now means "holds a value": a voxel shifted in from
  outside the volume has none, and its next trace is taken whole.
- `BLOCKLIGHT_DEBUG` shows, per pixel, whether a surface took the per-pixel trace or the cache,
  each source alone, and the distance-field level its trace sees. Translucents show blue on
  the map, solid with their own cache light in the cache view, and red in the resolution view.
- `shadow.culling=reversed` is Iris's SAFE_ZONE. With `voxelDistance` 32, chunks past 32 blocks
  are only voxelized if they cast shadow into view, though the volume reaches 48 blocks at
  `VX_VOL_SIZE 0`.
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
  N.L) is below that percent of the light already accumulated, plus a 1e-4 floor. In
  `prepare4_csh` a light is skipped only when its diffuse bound is under the cutoff of
  `accumLight` (the diffuse total) and, under `BLOCKLIGHT_HIGHLIGHT`, its GGX highlight bound is
  under the cutoff of `accumSpecular` (the highlight total); GGX is evaluated before the cutoff.
  `shadowcomp1` has no highlight term and keeps the diffuse-only bound. Skipped traces
  do not count against the budget. A light skipped by every pixel of a tile drops out of the
  previous-frame list but is re-found by the per-pixel discovery ray and the neighbour scan.
- Occupancy bits: 0-7 solid per SDF level, 8-15 translucent per level, 16 light, 17-21 level,
  22-26 material class, 27 entity light, 28-29 skylight. There are no free bits.
- What to watch: nether frame time over lava and fire; a glowstone cluster 20+ blocks away
  staying one bright source; torch rows near the player unchanged; hot spots every four blocks
  on lava shores; two same-kind lights either side of a one-block wall merging; caves at the
  edge of torch range with the cutoff at 1.

## voxy-revz

Minecraft 26.2 (voxy 0.2.19-beta, Iris 1.11.4): `rkc/mods/voxy-revz` is required, not an optional
companion.

- Without its reversed-Z mixin (`RenderProperties.useReverseZ`) voxy draws forward under any
  shader pack, and under Iris 1.11.4 that draws no LOD fragment at all. The `IRIS_VERSION >=
  11104` branch of `lib/vx/voxyProj.glsl` is written for voxy on reversed-Z and is never reached
  without the mod.
- Without its fluid mixin (`ShaderLoader.parse`, splicing `lod_fluid_height.glsl` into the end of
  `setupQuad`) LOD fluid surfaces sit too high at each LOD level: voxy scales the face inset by
  LOD size, so a sea at y=63 climbs to 63.78 on level 1 and steps at every level edge.

### Minecraft 26.3 / voxy 0.2.20

Read from the decompiled 0.2.20 jar; not tested in game.

- Voxy stays on reversed-Z itself under Iris (`useReverseZ` no longer returns false under a pack).
  It hands the patches an already forward `vxProj` (`VoxyUniforms.conditionallyReverseRevZ`
  rewrites row 2 of `vxProj`, `vxProjInv` and `vxViewProj`) and flips `gl_FragDepth`,
  `gl_FragCoord.z` and depth-sampler reads in every patch (`IrisShaderPatch`, through Iris's
  `DepthTransformer`). The reversed-Z mixin is therefore redundant there, and its 26.2 build
  would likely fail on 26.3 class names (voxy 0.2.20 imports `CompareOp` and `DepthStencilState`
  from `com.mojang.renderpearl.api`; unchecked against the 26.3 client jar).
- The fluid mixin is still needed: its hook (`ShaderLoader.parse`) and anchor
  (`quad.uvCorner = faceSize.xz;`) are intact and `quad_util.glsl` is unchanged from 0.2.19.
- This pack's own forward rewrite in `lib/vx/voxyProj.glsl` would be applied twice, undoing
  voxy's conversion and breaking view-position reconstruction and depth in the LOD shading. It
  must be gated before the pack is used with voxy 0.2.20. Voxy defines `VOXY` as 3 there (2 on
  0.2.19), which can tell the two apart; `VoxyOpaqueDepth` needs the same gate, and whether
  voxy's depth-read rewrite catches reads through the pack's own helpers is unverified.
- Patch schema `version` is still 1, and `voxy.json` fields are all still accepted; the new
  `vxNearPlane`/`vxFarPlane` uniforms are unused by the pack.

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
`SWEEP_BASELINE` (directory of result files from an earlier run with the same tag and the same
`SWEEP_OPTS`; a config absent there counts every FAIL as new).

About 26 programs per config fail only because the harness does not emulate what Iris injects
(`MC_RENDER_STAGE_*`, `projectionMatrix`, `gl_Fog`, `shadow2D`, `dhMaterialId` and
`dhProjection` in the dh programs), so the raw FAIL count is no regression
signal. The patch variants all pass. `voxy_world0_translucent` used to fail in both `patch-*`
configs because `voxy.json` did not request `eyeBrightnessM`, which `CAVE_FOG`'s `GetCaveFactor`
reads via `sky.glsl`; a baseline taken before that fix still lists it as FAIL, which is harmless.
Take a baseline from the known-good tree and rerun with `SWEEP_BASELINE`: it prints
`NEW FAIL <config> <name>` for every program that fails now but passed (or was absent) there,
and exits non-zero if there is any. Because the sweep reads the live settings, the baseline
moves when options change in-game, and branches the live options never select (IPBR lava,
unbound clouds) need a second run with an edited option file.

## Open items

- Minecraft 26.3 / voxy 0.2.20: gate the forward branch of `lib/vx/voxyProj.glsl` and
  `VoxyOpaqueDepth` on `VOXY < 3` before using the pack there, see "voxy-revz".
- Seams between LOD sections: voxy-side, see above.
- Under water the pack fogs by the whole view distance, so LOD terrain above the surface seen
  from below is a fog-coloured silhouette past about 50 blocks at `WATER_FOG_MULT 150`, as
  loaded terrain would be. Above water, LOD texels still take the sky's light-shaft march when
  `dhVlStillIntense` is high (upstream DH behaviour).
- The block-light highlight on a held item is traced from last frame's picture and read at the
  fragment's own pixel, so it trails the item by one frame of its on-screen motion (about 10
  pixels at 60 fps with view bobbing). Iris exposes no previous-frame hand transform to
  compensate with; the real fix would be a pass that traces the hand from the current frame.
- Ice reads whiter from where the shadow map ends. Inside the map, the water and floor under
  loaded ice are lit through the ice's coloured shadow; past 11/12 of `min(shadowDistance,
  far)` they take the fallback, which knows nothing of the ice above, so the water body comes
  out about a fifth brighter and less blue. That was the lighter strip at the loaded edge. LODs
  share the fallback and can never receive the coloured shadow, so with the `y^4` ramp the band
  and the LODs agree and the change sits at the shadow fade, spread over 16 blocks, not at the
  handoff.
- Block-light shadows on translucents are block-sized, see "Colored light". The fix would be a
  per-pixel trace in `gbuffers_water` against the distance field for the few strongest lights
  of the fragment's workgroup, roughly 50 fetches per light per fragment at `RT_STEPS 50`.
- Looking up from under water, the surface brightens toward the horizon. This is the pack's own
  shaft weighting (`VdotUM`, about twice from overhead to the horizon) and fresnel, unchanged
  from before the LOD work.
- `WORLD_BLUR 2` focuses on `depthtex1`, so depth of field treats LOD pixels, and loaded ice
  over LOD water, as infinitely far and blurs them more than loaded geometry at that distance.
- LOD water has no refraction (composite's `DoRefraction` gates on the water material mask,
  which the patch never writes; ice and glass get none in either path), and LOD translucents
  write no `translucentMult`.
- LOD wave normals are continuous where loaded ones snap to a 1/16 block grid; sub-pixel at LOD
  range.
- LOD light sources at emission 2.5 versus about 0.93 loaded under labPBR.
- Glass and tinted glass constants for the LOD translucent pass, above.
- `RenderDataFactory.generateMesh` never clears `neighboringFaces` between sections; unproven.
