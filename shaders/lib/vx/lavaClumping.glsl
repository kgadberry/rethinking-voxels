#ifndef LAVA_CLUMPING
#define LAVA_CLUMPING

// world-aligned cell that the lava/magma clumping pass merges lights over
const ivec3 lavaClumpCellSize = ivec3(4, 2, 4);
// set in the upper 16 bits of hash word 3 to mark a merged voxel count
#define LAVA_CLUMP_MERGED_FLAG 0x8000u

// occupancy material hash 21 covers both lava (10068) and magma (10452). Entity
// lights (bit 27) have their own clumping pass and must be left to it.
bool isLakeLightMat(int occupancy) {
    return (occupancy >> 27 & 1) == 0 && (occupancy >> 22 & 31) == 21;
}

// voxel coords are camera relative, so the compute pass and every reader have to
// derive the cell grid from the same camera block or their cells drift apart
ivec3 lavaClumpCamOffset() {
    ivec3 camPosInt = cameraPositionInt.y == -98257195 ? ivec3(floor(cameraPosition)) : cameraPositionInt;
    return (camPosInt % lavaClumpCellSize + lavaClumpCellSize) % lavaClumpCellSize;
}

// shift that lines a workgroup's cells up with the world grid
ivec3 lavaClumpAlign() {
    return (lavaClumpCellSize - lavaClumpCamOffset()) % lavaClumpCellSize;
}

// min corner of the cell holding lightCoord, in that same volume-centred space
ivec3 lavaClumpCellMin(ivec3 lightCoord) {
    ivec3 inCell = (lightCoord + lavaClumpCamOffset()) % lavaClumpCellSize;
    return lightCoord - (inCell + lavaClumpCellSize) % lavaClumpCellSize;
}

// a merged entry holds the mean colour of N voxels, so it has to be scaled back up
float lavaClumpMergeScale(uint packedUpper) {
    return ((packedUpper & LAVA_CLUMP_MERGED_FLAG) != 0u && packedUpper != 0xffffu) ?
        float(packedUpper & 0x7fffu) : 1.0;
}
#endif
