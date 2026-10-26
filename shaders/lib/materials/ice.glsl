// Ice: see-through with its texture, plus a glossy Fresnel reflection of the scene
// (screen-space, sky fallback). Needs: ssr.glsl, sky.glsl, lighting.glsl, translucent.glsl.

TranslucentSurface ShadeIce(vec4 albedo, vec3 playerPos, vec3 normal, Surface surf, vec3 sunDir, vec3 lightDir) {
    vec3 V = -normalize(playerPos);
    float NdotV = saturate(abs(dot(normal, V)));
    // A bit more reflective than physical ice (F0 0.018) for the stylised glassy look.
    float fresnel = saturate((0.06 + 0.94 * pow(1.0 - NdotV, 5.0)) * ICE_REFLECTIVITY);

    vec3 R = reflect(-V, normal);
    vec3 reflection = GetBlockSkyReflection(normalize(vec3(R.x, abs(R.y), R.z)), sunDir, -1.0) * surf.lm.y * surf.lm.y;
    #if WATER_REFLECTIONS == 1
        if (fresnel > 0.02) {
            vec2 uv = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
            vec3 viewPos = ScreenToView(uv, gl_FragCoord.z);
            vec4 ssr = TraceSSR(viewPos, normalize(mat3(gbufferModelView) * R), normalize(mat3(gbufferModelView) * normal), SSRDither());
            reflection = mix(reflection, ssr.rgb, ssr.a);
        }
    #endif

    vec3 body = SrgbToLinear(albedo.rgb) * GetLighting(surf, sunDir, lightDir);
    float bodyAlpha = albedo.a * ICE_OPACITY;

    float alpha = mix(bodyAlpha, 1.0, fresnel);
    vec3 color = (body * bodyAlpha * (1.0 - fresnel) + reflection * fresnel) / max(alpha, 1e-4);
    return PlainSurface(color, alpha);
}
