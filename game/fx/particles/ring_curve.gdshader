// Particles from a ring emitter, scaled over life by a curve (game/fx/particles/process.gdshaderinc).
shader_type particles;
render_mode disable_velocity;

#define RING
#define SCALE_CURVE
#include "res://game/fx/particles/process.gdshaderinc"
