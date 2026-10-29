shader_type spatial;
render_mode cull_front, unshaded, depth_draw_opaque;
uniform float thickness = 0.011;
uniform vec4 ink : source_color = vec4(0.06, 0.035, 0.045, 1.0);
void vertex() { VERTEX += NORMAL * thickness; }
void fragment() { ALBEDO = ink.rgb; }
