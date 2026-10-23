// Octahedral unit-vector encoding (Cigolle et al. 2014): 2 channels, uniform precision.

vec2 OctWrap(vec2 v) { return (1.0 - abs(v.yx)) * vec2(v.x >= 0.0 ? 1.0 : -1.0, v.y >= 0.0 ? 1.0 : -1.0); }

// Unit vector -> [0,1]^2
vec2 EncodeNormal(vec3 n) {
    n /= abs(n.x) + abs(n.y) + abs(n.z);
    vec2 e = n.z >= 0.0 ? n.xy : OctWrap(n.xy);
    return e * 0.5 + 0.5;
}

// [0,1]^2 -> unit vector
vec3 DecodeNormal(vec2 e) {
    e = e * 2.0 - 1.0;
    vec3 n = vec3(e, 1.0 - abs(e.x) - abs(e.y));
    float t = saturate(-n.z);
    n.xy += vec2(n.x >= 0.0 ? -t : t, n.y >= 0.0 ? -t : t);
    return normalize(n);
}

// 8-bit shading model id stored in a UNORM8 channel.
float EncodeId(int id) { return float(id) / 255.0; }
int DecodeId(float v) { return int(v * 255.0 + 0.5); }

// Vanilla lightmap coordinates (texel centres of a 16x16 map) -> [0,1] block/sky light.
vec2 RemapLightmap(vec2 lm) { return saturate((lm - 0.5 / 16.0) * (16.0 / 15.0)); }
