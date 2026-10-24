// Where a screen pixel was on the previous frame, from its depth and the camera motion.
// Used by TAA now and by the reduced-resolution effects (clouds, light shafts) later.
// Needs: common.glsl, space.glsl.

uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;
uniform vec3 previousCameraPosition;

// Depths below this belong to the held item, which moves with the camera.
const float HAND_DEPTH_LIMIT = 0.56;

vec2 ReprojectToPreviousFrame(vec2 uv, float depth) {
    if (depth < HAND_DEPTH_LIMIT) return uv;

    vec3 playerPos = ViewToPlayer(ScreenToView(uv, depth));
    // The sky is infinitely far away: only the camera rotation matters there.
    vec3 cameraMove = depth >= 1.0 ? vec3(0.0) : cameraPosition - previousCameraPosition;
    vec4 prevClip = gbufferPreviousProjection * (gbufferPreviousModelView * vec4(playerPos + cameraMove, 1.0));
    return prevClip.xy / prevClip.w * 0.5 + 0.5;
}
