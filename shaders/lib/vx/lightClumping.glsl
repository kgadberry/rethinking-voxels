#ifndef INCLUDE_LIGHT_CLUMPING
#define INCLUDE_LIGHT_CLUMPING

// world-aligned cell that the light clumping pass merges lights over
const ivec3 lightClumpCellSize = ivec3(4, 2, 4);
// set in the upper 16 bits of hash word 3 to mark a merged voxel count
#define LIGHT_CLUMP_MERGED_FLAG 0x8000u

// light level and material class: only lights agreeing on both merge, so a torch
// and a sea lantern sharing a cell stay separate
int lightClumpKey(int occupancy) {
    return occupancy >> 17 & 1023;
}

// a voxel the pass merged away: it lost its light bit but kept level and class.
// Entity lights (bit 27) have their own clumping pass and must be left to it.
bool lightClumpIsMember(int occupancy) {
    return (occupancy >> 16 & 1) == 0 && (occupancy >> 27 & 1) == 0 && lightClumpKey(occupancy) != 0;
}

// voxel coords are camera relative, so the compute pass and every reader have to
// derive the cell grid from the same camera block or their cells drift apart
ivec3 lightClumpCamOffset() {
    ivec3 camPosInt = cameraPositionInt.y == -98257195 ? ivec3(floor(cameraPosition)) : cameraPositionInt;
    return (camPosInt % lightClumpCellSize + lightClumpCellSize) % lightClumpCellSize;
}

// shift that lines a workgroup's cells up with the world grid
ivec3 lightClumpAlign() {
    return (lightClumpCellSize - lightClumpCamOffset()) % lightClumpCellSize;
}

// min corner of the cell holding lightCoord, in that same volume-centred space
ivec3 lightClumpCellMin(ivec3 lightCoord) {
    ivec3 inCell = (lightCoord + lightClumpCamOffset()) % lightClumpCellSize;
    return lightCoord - (inCell + lightClumpCellSize) % lightClumpCellSize;
}

// nearby lights stay exact, since a torch row merging a few blocks away would show.
// The test is on the cell, so the pass and every reader reach the same answer.
bool lightClumpNearCamera(ivec3 cellMin) {
    vec3 toCell = vec3(cellMin) + 0.5 * vec3(lightClumpCellSize);
    return dot(toCell, toCell) < float(LIGHT_CLUMP_MIN_DIST * LIGHT_CLUMP_MIN_DIST);
}

// a merged entry holds the mean colour of N voxels, so it has to be scaled back up
float lightClumpMergeScale(uint packedUpper) {
    return ((packedUpper & LIGHT_CLUMP_MERGED_FLAG) != 0u && packedUpper != 0xffffu) ?
        float(packedUpper & 0x7fffu) : 1.0;
}
#endif
