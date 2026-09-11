shader_type spatial;

varying vec3 rock_position;

float hash3(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1,0,0)), f.x),
		mix(hash3(i + vec3(0,1,0)), hash3(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0,0,1)), hash3(i + vec3(1,0,1)), f.x),
		mix(hash3(i + vec3(0,1,1)), hash3(i + vec3(1,1,1)), f.x), f.y), f.z);
}

void vertex() {
	rock_position = VERTEX;
}

void fragment() {
	float grain = noise3(rock_position * 22.0);
	float stone = noise3(rock_position * 4.7 + vec3(2.0));
	float seam = 1.0 - smoothstep(0.006, 0.026, abs(stone - 0.50));
	float pulse = 0.90 + 0.10 * sin(TIME * 5.0 + rock_position.y * 8.0);
	ALBEDO = mix(vec3(0.035, 0.028, 0.026), vec3(0.18, 0.13, 0.10), grain);
	ALBEDO = mix(ALBEDO, vec3(0.32, 0.07, 0.012), seam);
	ROUGHNESS = 0.9;
	EMISSION = mix(vec3(1.0, 0.08, 0.004), vec3(1.0, 0.48, 0.025), seam) * seam * pulse * 1.65;
}
