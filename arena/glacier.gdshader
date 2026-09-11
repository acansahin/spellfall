shader_type spatial;

varying vec3 ice_position;
varying float top_face;

void vertex() {
	// The circular mesh matches the playable boundary. All ice detail is surface shading.
	ice_position = VERTEX;
	top_face = NORMAL.y;
}

void fragment() {
	vec2 p = ice_position.xz;
	vec2 cell_position = p * 0.31;
	vec2 cell = floor(cell_position);
	vec2 local = fract(cell_position);
	float nearest = 8.0;
	float second = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 offset = vec2(float(x), float(y));
			vec2 id = cell + offset;
			vec2 jitter = fract(sin(vec2(dot(id, vec2(127.1, 311.7)), dot(id, vec2(269.5, 183.3)))) * 43758.5453);
			float distance_to_cell = length(offset + 0.2 + jitter * 0.6 - local);
			second = max(nearest, min(second, distance_to_cell));
			nearest = min(nearest, distance_to_cell);
		}
	}
	float cracks = 1.0 - smoothstep(0.005, 0.027, second - nearest);
	float cloud = sin(p.x * 0.41 + sin(p.y * 0.55)) * sin(p.y * 0.37 - p.x * 0.19) * 0.5 + 0.5;
	float grain = sin(p.x * 2.9 + sin(p.y * 1.7)) * 0.5 + 0.5;
	float top = smoothstep(0.4, 0.9, top_face);
	vec3 deep_ice = mix(vec3(0.035, 0.17, 0.24), vec3(0.08, 0.34, 0.45), cloud);
	vec3 surface_ice = mix(vec3(0.18, 0.45, 0.56), vec3(0.54, 0.70, 0.72), cloud);
	float snow = smoothstep(0.64, 0.88, cloud + grain * 0.16);
	surface_ice = mix(surface_ice, vec3(0.76, 0.82, 0.80), snow * 0.38);
	vec3 ice = mix(deep_ice, surface_ice, top);
	ALBEDO = mix(ice, vec3(0.045, 0.15, 0.19), cracks * top * 0.82);
	ROUGHNESS = mix(0.38, 0.68, snow);
	SPECULAR = 0.58;
}
