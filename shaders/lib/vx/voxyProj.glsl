#ifndef VOXY_PROJ
#define VOXY_PROJ

// Iris 1.11.4+ no longer hides GL_ARB_clip_control and hands packs 1 - depth and conventional
// matrices, so the forward branch below rewrites voxy's zero-to-one reversed projection the same
// way Iris's own iris_undoRevZ does: row 2 of the projection becomes row 3 - 2 * row 2.
// That branch requires voxy to be on reversed-Z whenever it draws under Iris 1.11.4+, which on
// voxy 0.2.19 only the voxyrevz mod provides; without it voxy draws no LOD fragment at all, so the
// branch is never reached. Older Iris switches GL to forward depth for pack rendering and voxy
// follows, which the #else side (vxProj as is, raw depth) matches.
// The convention cannot be detected here at compile time: Iris preprocesses the patch before voxy
// adds its own defines. At run time the sign of vxProj[3][2] tells the two apart (positive when
// reversed).
#if IRIS_VERSION >= 11104
    #define VOXY_FORWARD_PROJ

    // The LOD patches get both from voxy's uniform block instead
    #ifndef VOXY_PATCH
        uniform mat4 vxProj;
        uniform mat4 vxProjInv;
    #endif

    mat4 voxyProjForward() {
        mat4 p = vxProj;
        p[0][2] = p[0][3] - 2.0 * p[0][2];
        p[1][2] = p[1][3] - 2.0 * p[1][2];
        p[2][2] = p[2][3] - 2.0 * p[2][2];
        p[3][2] = p[3][3] - 2.0 * p[3][2];
        return p;
    }

    // Exact inverse of the rewrite above: column 2 halves and flips, column 3 absorbs half of it
    mat4 voxyProjInvForward() {
        return mat4(vxProjInv[0], vxProjInv[1], -0.5 * vxProjInv[2], vxProjInv[3] + 0.5 * vxProjInv[2]);
    }
#endif

// The LOD patches read vxDepthTexOpaque untransformed, so every read goes through this to land in
// the same convention as the projection above: flipped only where that projection is the forward copy.
#ifdef VOXY_PATCH
    #ifdef VOXY_FORWARD_PROJ
        #define VoxyOpaqueDepth(rawDepth) (1.0 - (rawDepth))
    #else
        #define VoxyOpaqueDepth(rawDepth) (rawDepth)
    #endif
#endif

#endif
