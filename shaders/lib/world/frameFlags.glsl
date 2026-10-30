#ifndef FRAME_FLAGS_GLSL
#define FRAME_FLAGS_GLSL

// Small flags passes leave for each other (bufferObject.4), so work nobody needs can be
// skipped:
//   rippleWaves[f]  - the ripple step of frame f (mod 4) left some cell moving (A3)
//   rippleSource[f] - in frame f something crossed the water surface (A3)
//   panoramaUsed[f] - in frame f (mod 8) something drew clouds from the panorama (A4)

layout(std430, binding = 4) buffer FrameFlags {
    uint rippleWaves[4];
    uint rippleSource[4];
    uint panoramaUsed[8];
};

#endif
