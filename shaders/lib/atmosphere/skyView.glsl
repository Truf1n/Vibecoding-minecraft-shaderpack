#ifndef SKY_VIEW_GLSL
#define SKY_VIEW_GLSL

// Cloud panorama layout (program/skyView.glsl): u = azimuth (0..1 around), v = elevation,
// v^2 * 90 degrees (more texels near the horizon).
const ivec2 SKY_VIEW_SIZE = ivec2(1024, 256);

vec3 SkyViewDirection(vec2 uv) {
    float azimuth = uv.x * TAU;
    float elevation = uv.y * uv.y * PI * 0.5;
    return vec3(cos(elevation) * cos(azimuth), sin(elevation), cos(elevation) * sin(azimuth));
}

vec2 SkyViewCoord(vec3 dir) {
    float azimuth = atan(dir.z, dir.x);
    float elevation = asin(clamp(dir.y, 0.0, 1.0));
    return vec2(fract(azimuth / TAU), sqrt(elevation / (PI * 0.5)));
}

#endif
