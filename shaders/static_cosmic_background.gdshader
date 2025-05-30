shader_type canvas_item;

uniform vec4 background_color : source_color;
uniform vec4 foreground_color : source_color;
uniform float pulse_intensity : hint_range(0.0, 1.0) = 0.8;
uniform float pulse_speed : hint_range(0.1, 5.0) = 0.8;

// Simplified 4x4 Bayer matrix
const mat2 bayer4x4 = mat2(
	vec2(0.0, 8.0),
	vec2(12.0, 4.0)
) / 16.0;

// Simplified dither lookup
float get_dither_value(vec2 pos) {
	vec2 scaled_pos = pos / 2.0;
	int x = int(mod(scaled_pos.x, 2.0));
	int y = int(mod(scaled_pos.y, 2.0));
	return bayer4x4[x][y];
}

// Simplified noise
float simple_noise(vec2 uv, float time_offset) {
	return sin(uv.x * 2.0 + time_offset) * sin(uv.y * 2.0 + time_offset) * 0.5 + 0.5;
}

void fragment() {
	// Simplified scaling
	float pixel_scale = 4.0;
	vec2 scaled_pos = FRAGCOORD.xy / pixel_scale;
	
	// Single dither pattern
	float pattern = get_dither_value(scaled_pos + vec2(TIME * 0.1));
	float pulse = (sin(TIME * pulse_speed) * 0.5 + 0.5) * pulse_intensity;
	pattern *= (0.15 + pulse * 0.2);
	
	// Single noise pattern
	float noise = simple_noise(UV * 3.0, TIME * 0.1) * 0.1;
	
	// Combine patterns
	float combined = pattern * 0.7 + noise * 0.3;
	
	// Final color
	COLOR = mix(background_color, foreground_color, combined * 0.15);
	COLOR.a = background_color.a;
} 