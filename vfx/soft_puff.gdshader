shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz),0,0,0),
		vec4(0,length(MODEL_MATRIX[1].xyz),0,0), vec4(0,0,length(MODEL_MATRIX[2].xyz),0), vec4(0,0,0,1));
}

void fragment() {
	float radius = length(UV * 2.0 - 1.0);
	float soft = 1.0 - smoothstep(0.15, 1.0, radius);
	ALBEDO = COLOR.rgb;
	ALPHA = soft * soft * COLOR.a * 0.36;
}
