shader_type spatial;
// Hand-painted look: sculpt-baked vertex colour (AO, edge light, warm/cool paint) x triplanar brush grain.
// COLOR.rgb = painted albedo (authored in sRGB), COLOR.a = emissive "energy" mask.
uniform sampler2D grain : source_color, filter_linear_mipmap, repeat_enable;
uniform float grain_scale = 0.28;
uniform float grain_amt = 0.30;
uniform vec3 glow_color : source_color = vec3(0.24, 1.0, 0.9);
uniform float glow_energy = 2.4;
uniform float sun_gain = 0.5;
varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = pow(abs(wnrm), vec3(4.0));
	n /= (n.x + n.y + n.z + 0.0001);
	vec3 g = texture(grain, wpos.zy * grain_scale).rgb * n.x
		+ texture(grain, wpos.xz * grain_scale).rgb * n.y
		+ texture(grain, wpos.xy * grain_scale).rgb * n.z;
	vec3 c = pow(clamp(COLOR.rgb, 0.0, 1.0), vec3(2.2));
	c *= mix(vec3(1.0), g * 1.75, grain_amt);
	ALBEDO = c;
	ROUGHNESS = 0.92;
	SPECULAR = 0.12;
	float gm = smoothstep(0.35, 0.8, COLOR.a);
	EMISSION = glow_color * glow_energy * gm * (0.7 + 0.3 * c.g);
	ALBEDO = mix(ALBEDO, vec3(0.05), gm * 0.4);
}

void light() {
	float w = clamp(dot(NORMAL, LIGHT) * 0.5 + 0.5, 0.0, 1.0);
	w = smoothstep(0.2, 0.9, w);
	DIFFUSE_LIGHT += ATTENUATION * LIGHT_COLOR * w * sun_gain;
}
