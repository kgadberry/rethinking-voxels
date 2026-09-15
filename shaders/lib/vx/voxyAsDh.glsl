#ifndef INCLUDE_VOXY_AS_DH
#define INCLUDE_VOXY_AS_DH

// Voxy keeps LOD depth in its own textures and draws with its own projection, which is exactly the
// shape of Distant Horizons support, so its names are aliased onto DH's and every pass that already
// handles DH geometry handles LODs too. The LOD patches supply that geometry and are excluded.
//
// Voxy draws opaque and translucent LODs back to back inside Sodium's terrain pass, so both depth
// textures are complete before deferred; as with Iris's DH pair, dhDepthTex1 is the opaque-only one.
#if defined VOXY && !defined DISTANT_HORIZONS && !defined VOXY_PATCH
    #define DISTANT_HORIZONS
    #define VOXY_AS_DH // for the few places where voxy's LOD handoff differs from DH's

    #define dhRenderDistance vxRenderDistance
    #define dhDepthTex vxDepthTexTrans
    #define dhDepthTex1 vxDepthTexOpaque

    #include "/lib/vx/voxyProj.glsl"
    #ifdef VOXY_FORWARD_PROJ
        #define dhProjection voxyProjForward()
        #define dhProjectionInverse voxyProjInvForward()
    #else
        #define dhProjection vxProj
        #define dhProjectionInverse vxProjInv
    #endif
#endif
#endif
