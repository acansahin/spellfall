shader_type spatial;
render_mode cull_disabled;

void fragment() {
	float inlay = step(0.9, COLOR.g) * (1.0 - step(0.2, COLOR.b));
	ALBEDO = COLOR.rgb;
	METALLIC = 0.55 * (1.0 - inlay);
	ROUGHNESS = mix(0.32, 0.48, inlay);
	EMISSION = vec3(0.38, 1.0, 0.025) * inlay * 1.35;
}
