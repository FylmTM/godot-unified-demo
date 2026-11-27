// Particles from a sphere emitter, scaled over life by a curve and stirred by turbulence (game/fx/particles/process.gdshaderinc).
shader_type particles;
render_mode disable_velocity;

#define SCALE_CURVE
#define TURBULENCE
#include "res://game/fx/particles/process.gdshaderinc"
