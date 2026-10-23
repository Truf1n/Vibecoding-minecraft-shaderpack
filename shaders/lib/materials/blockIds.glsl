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

#define BLOCK_WATER             3001
#define BLOCK_STAINED_GLASS     3002
#define BLOCK_GLASS             3003
#define BLOCK_ICE               3004
#define BLOCK_SLIME_HONEY       3005
#define BLOCK_NETHER_PORTAL     3006

#define BLOCK_END_PORTAL        9001

bool IsPlant(int id)       { return id >= 1001 && id <= 1008; }
bool IsLightSource(int id) { return id >= 2001 && id <= 2010; }

// Shading models stored in the G-buffer (8 bits). 0 means "not deferred-lit":
// the deferred pass keeps whatever colortex0 holds (sky, forward-rendered geometry).
#define SM_KEEP     0
#define SM_DEFAULT  1
#define SM_FOLIAGE  2
#define SM_LEAVES   3
#define SM_ENTITY   4
#define SM_HAND     5
