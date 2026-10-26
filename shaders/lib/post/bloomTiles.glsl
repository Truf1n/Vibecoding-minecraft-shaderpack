// Bloom tiles (plan item K1): the scene blurred at six sizes, from 1/4 to 1/128 of the
// screen (mip levels 2-7), packed side by side into one half-size buffer (colortex13):
// written by program/bloom.glsl, summed by program/post.glsl.

const int BLOOM_TILES = 6;

// Where tile k sits in the bloom buffer (uv): its corner and its size (half the size of
// the one before, with a gap so blurring and upsampling never reach a neighbour).
vec2 BloomTileOffset(int k) {
    const vec2 offsets[BLOOM_TILES] = vec2[BLOOM_TILES](vec2(0.0, 0.0), vec2(0.52, 0.0), vec2(0.52, 0.27),
                                                        vec2(0.66, 0.27), vec2(0.52, 0.41), vec2(0.57, 0.41));
    return offsets[k];
}
float BloomTileScale(int k) { return exp2(-float(k + 1)); }
