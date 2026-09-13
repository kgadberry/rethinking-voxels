// The player and other entityTranslucent geometry draw after deferred1, so this program cannot
// share gbuffers_entities' colortex4 albedo write - that buffer has been repurposed by then.
#define TRANSLUCENT_ENTITY_PASS
#define GBUFFERS_ENTITIES
#include "/program/gbuffers_entities.glsl"
