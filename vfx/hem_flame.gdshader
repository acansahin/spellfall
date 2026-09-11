shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;

void vertex() {
	// Every flame faces the arena camera while its particle still rises independently.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1],
		INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	float height = 1.0 - UV.y;
	float sway = sin(TIME * 18.0 + height * 13.0) * height * 0.08;
	float width = mix(0.43, 0.035, pow(height, 0.78));
	float flame = 1.0 - smoothstep(width * 0.55, width, abs(UV.x - 0.5 - sway));
	float ends = smoothstep(0.0, 0.10, height) * (1.0 - smoothstep(0.80, 1.0, height));
	vec3 hot = vec3(1.0, 0.86, 0.28);
	vec3 ember = vec3(1.0, 0.10, 0.008);
	ALBEDO = mix(hot, ember, smoothstep(0.12, 0.9, height)) * 1.45;
	ALPHA = flame * ends * COLOR.a * 0.72;
}
