// Mirrors shaders/block.properties. Keep both files in sync.

#define BLOCK_PLANT_GROUND      1001
#define BLOCK_PLANT_TALL_LOWER  1002
#define BLOCK_PLANT_TALL_UPPER  1003
#define BLOCK_LEAVES            1004
#define BLOCK_PLANT_HANGING     1005
#define BLOCK_LILY_PAD          1006
#define BLOCK_GROUND_COVER      1007
#define BLOCK_BUSH              1008

#define BLOCK_LIGHT_FIRE        2001
#define BLOCK_LIGHT_SOUL        2002
#define BLOCK_LIGHT_GLOWSTONE   2003
#define BLOCK_LIGHT_SEA_LANTERN 2004
#define BLOCK_LIGHT_LAVA        2005
#define BLOCK_LIGHT_REDSTONE    2006
#define BLOCK_LIGHT_COPPER      2007
#define BLOCK_LIGHT_AMETHYST    2008
#define BLOCK_LIGHT_LICHEN      2009
#define BLOCK_LIGHT_CRYING      2010
#define BLOCK_LIGHT_FROG_OCHRE  2011
#define BLOCK_LIGHT_FROG_VERDANT 2012
#define BLOCK_LIGHT_FROG_PEARL  2013
#define BLOCK_LIGHT_SEA_PICKLE  2014
#define BLOCK_LIGHT_SCULK       2015
#define BLOCK_LIGHT_ENCHANT     2016
#define BLOCK_LIGHT_TRIAL       2017
#define BLOCK_LIGHT_OMINOUS     2018
#define BLOCK_LIGHT_COPPER_BULB 2019
#define BLOCK_LIGHT_CANDLE      2100 // + 1 + colour index 0..15 for coloured candles

#define BLOCK_WATER             3001 // source block (full-height surface)
#define BLOCK_WATER_FLOWING     3002
#define BLOCK_GLASS             3003
#define BLOCK_ICE               3004
#define BLOCK_SLIME_HONEY       3005
#define BLOCK_NETHER_PORTAL     3006
#define BLOCK_GLASS_PANE        3007
#define BLOCK_TINTED_GLASS      3008
#define BLOCK_STAINED_GLASS     3100 // + colour index 0..15
#define BLOCK_STAINED_PANE      3200 // + colour index 0..15

#define BLOCK_DRY_WATERLOGGABLE 4001 // stairs, slabs, ... with waterlogged=false
#define BLOCK_THIN_SOLID        4002 // carpets, snow layers 1-7: solid but let light past

// Materials (smoothness / metalness / emission in terrainMaterial.glsl)
#define MAT_IRON            5001
#define MAT_GOLD            5002
#define MAT_COPPER          5003
#define MAT_COPPER_OXIDIZED 5004
#define MAT_NETHERITE       5005
#define MAT_RAW_METAL       5006
#define MAT_GEM             5010
#define MAT_LAPIS_BLOCK     5011
#define MAT_REDSTONE_BLOCK  5012
#define MAT_AMETHYST_BLOCK  5013
#define MAT_POLISHED_STONE  5020
#define MAT_QUARTZ          5021
#define MAT_CONCRETE        5022
#define MAT_GLAZED          5023
#define MAT_PRISMARINE      5024
#define MAT_TERRACOTTA      5025
#define MAT_OBSIDIAN        5026
#define MAT_PACKED_ICE      5027
#define MAT_SNOW            5028
#define MAT_PURPUR          5029
#define MAT_PLANKS          5030
#define MAT_LOGS            5031
#define ORE_COAL            5100
#define ORE_IRON            5101
#define ORE_GOLD            5102
#define ORE_COPPER          5103
#define ORE_REDSTONE        5104
#define ORE_LAPIS           5105
#define ORE_EMERALD         5106
#define ORE_DIAMOND         5107
#define ORE_NETHER_QUARTZ   5108
#define ORE_NETHER_GOLD     5109
#define ORE_GILDED          5110
#define ORE_ANCIENT_DEBRIS  5111

#define BLOCK_END_PORTAL        9001

// Entity IDs (entity.properties)
#define ENTITY_PLAYER           10001

bool IsPlant(int id)       { return id >= 1001 && id <= 1008; }
bool IsLightSource(int id) { return (id >= 2001 && id <= 2019) || (id >= 2100 && id <= 2116); }
bool IsWater(int id)       { return id == BLOCK_WATER || id == BLOCK_WATER_FLOWING; }
bool IsOre(int id)         { return id >= 5100 && id <= 5111; }
bool IsStainedGlass(int id) { return id >= 3100 && id <= 3115; }
bool IsStainedPane(int id)  { return id >= 3200 && id <= 3215; }
bool IsGlass(int id) {
    return id == BLOCK_GLASS || id == BLOCK_GLASS_PANE || id == BLOCK_TINTED_GLASS || IsStainedGlass(id) || IsStainedPane(id);
}
bool IsPane(int id) { return id == BLOCK_GLASS_PANE || IsStainedPane(id); }

// Shading models stored in the G-buffer (8 bits). 0 means "not deferred-lit":
// the deferred pass keeps whatever colortex0 holds (sky, forward-rendered geometry).
#define SM_KEEP     0
#define SM_DEFAULT  1
#define SM_FOLIAGE  2
#define SM_LEAVES   3
#define SM_ENTITY   4
#define SM_HAND     5
