shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;

void fragment() {
	float height = 1.0 - UV.y;
	float flicker = sin(height * 18.0 - TIME * 21.0) * 0.035
		+ sin(height * 33.0 - TIME * 27.0) * 0.023;
	float centre = 0.5 + sin(height * 7.0 - TIME * 8.0) * height * 0.07;
	float width = pow(max(1.0 - height, 0.0), 0.72) * 0.49 + flicker;
	float edge = 1.0 - smoothstep(max(width * 0.30, 0.0), max(width, 0.001), abs(UV.x - centre));
	float fade = smoothstep(0.0, 0.14, height) * (1.0 - smoothstep(0.80, 1.0, height));
	vec3 colour = mix(vec3(1.0, 0.72, 0.19), vec3(1.0, 0.11, 0.008), height);
	ALBEDO = colour * 1.5;
	ALPHA = edge * fade * 0.90;
}
