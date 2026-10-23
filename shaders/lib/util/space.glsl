// Space conversions for fullscreen passes. "Player space" = world space relative to the camera.

vec3 ScreenToView(vec2 uv, float depth) {
    vec4 clip = vec4(vec3(uv, depth) * 2.0 - 1.0, 1.0);
    vec4 view = gbufferProjectionInverse * clip;
    return view.xyz / view.w;
}

vec3 ViewToPlayer(vec3 viewPos) { return mat3(gbufferModelViewInverse) * viewPos + gbufferModelViewInverse[3].xyz; }
vec3 ViewToPlayerDir(vec3 viewDir) { return mat3(gbufferModelViewInverse) * viewDir; }
