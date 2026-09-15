#ifndef VOXY_PROJ
#define VOXY_PROJ

// Iris 1.11.4+ no longer hides GL_ARB_clip_control, so voxy (held on reversed-Z by the voxyrevz
// mod) projects zero-to-one reversed while Iris hands packs 1 - depth and conventional matrices.
// Same rewrite as Iris's own iris_undoRevZ: row 2 of the projection becomes row 3 - 2 * row 2.
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

#endif
