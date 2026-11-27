// Particles from a sphere emitter, stirred by turbulence (game/fx/particles/process.gdshaderinc).
shader_type particles;
render_mode disable_velocity;

#define TURBULENCE
#include "res://game/fx/particles/process.gdshaderinc"
