// Applies translucent tints and order-independent layers: scene * colortex5 + colortex6.
// Later milestones add fog, light shafts and reflections around this pass.

#include "/lib/common.glsl"

#ifdef VERTEX_SHADER

void main() {
    gl_Position = ftransform();
}

#endif

#ifdef FRAGMENT_SHADER

#include "/lib/gbuffer/layout.glsl"

uniform sampler2D colortex0;
uniform sampler2D colortex5;
uniform sampler2D colortex6;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 outColor;

void main() {
    ivec2 pixel = ivec2(gl_FragCoord.xy);
    vec2 uv = gl_FragCoord.xy / vec2(viewWidth, viewHeight);

    #ifdef UNDERWATER_DISTORTION
        if (isEyeInWater == 1) {
            // Gentle wobble while the camera is under water.
            float t = frameTimeCounter;
            uv += vec2(sin(uv.y * 18.0 + t * 1.7), cos(uv.x * 14.0 + t * 1.3)) * 0.0018;
            uv = clamp(uv, vec2(0.0), vec2(1.0));
            pixel = ivec2(uv * vec2(viewWidth, viewHeight));
        }
    #endif

    vec3 color = texture(colortex0, uv).rgb;
    color = color * texelFetch(colortex5, pixel, 0).rgb + texelFetch(colortex6, pixel, 0).rgb;
    outColor = vec4(color, 1.0);
}

#endif
