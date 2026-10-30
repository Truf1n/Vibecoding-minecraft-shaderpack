// Screen-space reflections (plan item W11, pulled forward): march the reflected ray in
// view space against the opaque depth buffer and fetch the lit opaque scene that the
// deferred pass copies into colortex7. Misses fall back to the sky.
// Needs: common.glsl, space.glsl.

uniform sampler2D colortex7; // lit opaque scene (copied in deferred, before translucents)
uniform sampler2D depthtex1; // opaque depth (without translucents)
#include "/lib/materials/depthTiles.glsl"

#define SSR_STEPS 24
#define SSR_REFINE_STEPS 5

vec3 ViewToScreen(vec3 viewPos) {
    vec4 clip = gbufferProjection * vec4(viewPos, 1.0);
    return clip.xyz / clip.w * 0.5 + 0.5;
}

float LinearizeDepth(float depth) {
    float ndc = depth * 2.0 - 1.0;
    return 2.0 * near * far / (far + near - ndc * (far - near));
}

// rgb = reflected scene colour, a = confidence (0 = use the sky instead).
// planeNormal: view-space normal of the reflecting surface (not the wave normal); hits
// behind that plane (e.g. terrain under the water) cannot appear in the reflection.
vec4 TraceSSR(vec3 viewPos, vec3 viewDir, vec3 planeNormal, float dither) {
    float dist = length(viewPos);
    float stepLen = 0.15 + dist * 0.02;
    vec3 pos = viewPos + viewDir * stepLen * dither;
    vec3 prev = pos;
    // Distant surfaces (P12): fewer, faster-growing steps that reach about as far (their
    // reflections are small on screen and mostly sky).
    int steps = dist > 64.0 ? SSR_STEPS / 2 : (dist > 24.0 ? SSR_STEPS * 3 / 4 : SSR_STEPS);
    float growth = dist > 64.0 ? 1.45 : (dist > 24.0 ? 1.3 : 1.22);

    for (int i = 0; i < steps; i++) {
        prev = pos;
        pos += viewDir * stepLen;
        stepLen *= growth;

        vec3 screen = ViewToScreen(pos);
        if (any(lessThan(screen.xy, vec2(0.0))) || any(greaterThan(screen.xy, vec2(1.0))) || pos.z > -near) break;

        float rayLin = -pos.z;
        if (rayLin > far) break; // beyond everything drawn: only the sky is left
        // In front of everything in this 8x8 tile (P18): nothing here to hit, no need to
        // read the depth itself, and the steps may grow a little faster while it lasts.
        if (rayLin < LinearizeDepth(DepthTileAt(screen.xy)) - 0.05) {
            stepLen *= 1.12;
            continue;
        }
        float sceneLin = LinearizeDepth(texture(depthtex1, screen.xy).r);
        float behind = rayLin - sceneLin;
        if (behind > 0.0) {
            // Too far behind the surface: the ray passed behind an object, keep going.
            if (behind > stepLen * 2.0 + 0.5) continue;

            // Binary search between the last two samples for the crossing point.
            vec3 a = prev, b = pos;
            for (int j = 0; j < SSR_REFINE_STEPS; j++) {
                vec3 mid = (a + b) * 0.5;
                vec3 s = ViewToScreen(mid);
                if (-mid.z > LinearizeDepth(texture(depthtex1, s.xy).r)) b = mid; else a = mid;
            }
            vec3 hit = ViewToScreen(b);
            float hitDepth = texture(depthtex1, hit.xy).r;
            if (hitDepth >= 1.0) break; // sky: let the caller draw it
            vec3 hitView = ScreenToView(hit.xy, hitDepth);
            if (dot(hitView - viewPos, planeNormal) < -0.05) continue; // below the surface

            // Fade out near the screen edges, where the information runs out.
            vec2 edge = smoothstep(vec2(0.0), vec2(0.08), hit.xy) * smoothstep(vec2(0.0), vec2(0.08), 1.0 - hit.xy);
            return vec4(texture(colortex7, hit.xy).rgb, edge.x * edge.y);
        }
    }
    return vec4(0.0);
}

// Per-pixel jitter for the first ray step (interleaved gradient noise).
// Varies every frame (golden-ratio offset) so TAA averages the steps away.
float SSRDither() {
    float ign = fract(52.9829189 * fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715))));
    #ifdef TAA
        ign = fract(ign + float(frameCounter % 64) * 0.618034);
    #endif
    return ign;
}
