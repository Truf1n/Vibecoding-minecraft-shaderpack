// Per-block material evaluation for deferred geometry. Runs in the gbuffers fragment
// stage, where the texture is available; the G-buffer only carries the result.
// M0: shading model + emission only. The full material library arrives in M6.

struct Material {
    int shadingModel;
    float emission; // 0..1, scaled to HDR in the lighting pass
};

Material GetTerrainMaterial(int blockId, vec3 albedoSrgb) {
    Material m;
    m.shadingModel = SM_DEFAULT;
    m.emission = 0.0;

    if (IsPlant(blockId)) {
        m.shadingModel = blockId == BLOCK_LEAVES ? SM_LEAVES : SM_FOLIAGE;
    } else if (IsLightSource(blockId)) {
        // Only the bright texels of a light block glow (the flame, not the stick).
        float lum = Luminance(albedoSrgb);
        m.emission = blockId == BLOCK_LIGHT_LAVA ? 1.0 : smoothstep(0.55, 0.95, lum);
    }
    return m;
}
