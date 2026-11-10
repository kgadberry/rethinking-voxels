#ifndef SSBO
    #define SSBO
    #ifndef WRITE_TO_SSBOS
        #define READONLY
        #define WRITE_TO_SSBOS readonly
    #endif

    // Binding 7, not 0: other mods bind and unbind low SSBO binding points without
    // restoring them, and Iris binds a pack's SSBO only once per pipeline.
    // Must match bufferObject.7 in shaders.properties.
    layout(std430, binding=7) WRITE_TO_SSBOS buffer stuff {
        mat4 gbufferPreviousModelViewInverse;
        mat4 gbufferPreviousProjectionInverse;
        mat4 reprojectionMatrix;
        uint globalLightHashMap[];
    };
    #ifdef READONLY
        #undef WRITE_TO_SSBOS
    #endif
#endif
