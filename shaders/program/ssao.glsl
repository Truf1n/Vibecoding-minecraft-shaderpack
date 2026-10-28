// Screen-space ambient occlusion (deferred1, plan item L8): soft contact shadows in
// corners, where blocks meet and around mobs. Half size (size.buffer.colortex15): a ring of
// samples in the hemisphere above each pixel, checked against the depth buffer; the set
// turns a little every frame (TAA blends it) and the lighting pass upsamples it with a
// depth-aware blur. Only the ambient and block light are darkened, never the sunlight.
// Positions go through the projection matrices both ways, which carry Minecraft's view
// bobbing, so the occlusion stays put on the blocks while walking.

#include "/lib/common.glsl"

#ifdef VERTEX_SHADER

void main() {
    gl_Position = ftransform();
}

#endif

#ifdef FRAGMENT_SHADER

#include "/lib/gbuffer/layout.glsl"
#include "/lib/util/encoding.glsl"
#include "/lib/util/space.glsl"

uniform sampler2D colortex2;
uniform sampler2D depthtex0;

/* RENDERTARGETS: 15 */
layout(location = 0) out float outAO;

#if SSAO == 2
    const int AO_SAMPLES = 12;
#else
    const int AO_SAMPLES = 6;
#endif
const float AO_RADIUS = 1.1; // blocks

vec3 ViewToScreenAO(vec3 viewPos) {
    vec4 clip = gbufferProjection * vec4(viewPos, 1.0);
    return clip.xyz / clip.w * 0.5 + 0.5;
}

void main() {
    vec2 size = floor(vec2(viewWidth, viewHeight) * 0.5);
    vec2 uv = gl_FragCoord.xy / size;
    ivec2 pixel = ivec2(uv * vec2(viewWidth, viewHeight));
    float depth = texelFetch(depthtex0, pixel, 0).r;
    outAO = 1.0;
    if (depth >= 1.0 || depth < 0.56) return; // sky, held item

    vec3 viewPos = ScreenToView(uv, depth);
    vec3 normal = mat3(gbufferModelView) * DecodeNormal(texelFetch(colortex2, pixel, 0).xy);

    // A frame of reference around the normal, turned by a per-pixel, per-frame angle.
    float noise = fract(52.9829189 * fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715))) + float(frameCounter % 16) * 0.618034);
    float angle = noise * TAU;
    vec3 helper = abs(normal.z) < 0.9 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
    vec3 tangent = normalize(cross(helper, normal));
    vec3 bitangent = cross(normal, tangent);

    float occlusion = 0.0, weight = 0.0;
    for (int i = 0; i < AO_SAMPLES; i++) {
        // Spiral through the hemisphere: angles spread evenly, radii growing outwards,
        // pointing more and more along the surface.
        float fi = (float(i) + 0.5) / float(AO_SAMPLES);
        float a = angle + float(i) * 2.39996; // golden angle
        float r = AO_RADIUS * (0.15 + 0.85 * fi * fi);
        float elevation = mix(0.85, 0.2, fi);
        vec3 dir = normalize((tangent * cos(a) + bitangent * sin(a)) * sqrt(1.0 - elevation * elevation) + normal * elevation);
        vec3 samplePos = viewPos + dir * r;

        vec3 screen = ViewToScreenAO(samplePos);
        if (any(lessThan(screen.xy, vec2(0.0))) || any(greaterThan(screen.xy, vec2(1.0)))) continue;
        float sceneDepth = texelFetch(depthtex0, ivec2(screen.xy * vec2(viewWidth, viewHeight)), 0).r;
        if (sceneDepth < 0.56) continue; // the held item hides nothing
        float sceneZ = ScreenToView(screen.xy, sceneDepth).z;
        // Occluded when the scene there is in front of the sample; things far in front
        // (a separate object) count less.
        float inFront = sceneZ - samplePos.z;
        float range = smoothstep(0.0, 1.0, AO_RADIUS / max(abs(viewPos.z - sceneZ), 1e-3));
        occlusion += (inFront > 0.03 ? 1.0 : 0.0) * range;
        weight += 1.0;
    }
    float ao = 1.0 - occlusion / max(weight, 1.0);
    // Fade out towards the screen edges, where much of the surroundings is off screen.
    vec2 edge = smoothstep(vec2(0.0), vec2(0.06), uv) * smoothstep(vec2(0.0), vec2(0.06), 1.0 - uv);
    outAO = mix(1.0, ao, edge.x * edge.y);
}

#endif
