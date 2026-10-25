// Specular reflection of opaque materials (plan item X1): Fresnel, the sun/moon highlight,
// and the reflection of the surroundings (added by the reflection passes).
// Needs: common.glsl.

float RoughnessFromSmoothness(float smoothness) {
    float r = 1.0 - smoothness;
    return max(r * r, 0.02);
}

// Base reflectance: 4% for stone, wood, ...; metals reflect in their own colour.
vec3 SpecularF0(vec3 albedo, float metalness) { return mix(vec3(0.04), albedo, metalness); }

// Fresnel with the roughness taken into account (rough surfaces don't turn mirror-like at
// grazing angles).
vec3 FresnelRoughness(float cosTheta, vec3 f0, float roughness) {
    return f0 + (max(vec3(1.0 - roughness), f0) - f0) * pow(1.0 - saturate(cosTheta), 5.0);
}

// GGX highlight of a light from direction L (energy-normalised, includes N.L).
vec3 SpecularHighlight(vec3 N, vec3 V, vec3 L, float roughness, vec3 f0) {
    vec3 H = normalize(L + V);
    float NdotL = saturate(dot(N, L)), NdotV = saturate(dot(N, V)), NdotH = saturate(dot(N, H));
    if (NdotL <= 0.0) return vec3(0.0);
    float a2 = roughness * roughness;
    float d = NdotH * NdotH * (a2 - 1.0) + 1.0;
    float D = a2 / (PI * d * d);
    float k = roughness * 0.5;
    float G = NdotL / (NdotL * (1.0 - k) + k) * NdotV / (NdotV * (1.0 - k) + k);
    vec3 F = f0 + (1.0 - f0) * pow(1.0 - saturate(dot(H, V)), 5.0);
    return min(D * G * F / max(4.0 * NdotV, 1e-3), vec3(30.0));
}
