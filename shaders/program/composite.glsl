// Resolves order-independent translucency: background * transmittance + added light.
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
    vec3 color = texelFetch(colortex0, pixel, 0).rgb;
    color = color * texelFetch(colortex5, pixel, 0).rgb + texelFetch(colortex6, pixel, 0).rgb;
    outColor = vec4(color, 1.0);
}

#endif
