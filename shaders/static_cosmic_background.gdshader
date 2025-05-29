shader_type canvas_item;

uniform vec4 background_color : source_color;
uniform vec4 foreground_color : source_color;
uniform float pulse_intensity : hint_range(0.0, 0.5) = 0.1; // How much brighter it gets
uniform float pulse_speed : hint_range(0.1, 5.0) = 0.5;   // How fast it pulses

// 8x8 Bayer matrix for larger pattern
const mat4 bayer8x8_1 = mat4(
	vec4(0.0, 32.0, 8.0, 40.0),
	vec4(48.0, 16.0, 56.0, 24.0),
	vec4(12.0, 44.0, 4.0, 36.0),
	vec4(60.0, 28.0, 52.0, 20.0)
) / 64.0;

const mat4 bayer8x8_2 = mat4(
	vec4(3.0, 35.0, 11.0, 43.0),
	vec4(51.0, 19.0, 59.0, 27.0),
	vec4(15.0, 47.0, 7.0, 39.0),
	vec4(63.0, 31.0, 55.0, 23.0)
) / 64.0;

// Returns 0-1 based on position in dither pattern
float get_dither_value(vec2 pos, mat4 pattern, float scale) {
	vec2 scaled_pos = pos / (4.0 * scale); // Scale up the pattern size
	int x = int(mod(scaled_pos.x, 4.0));
	int y = int(mod(scaled_pos.y, 4.0));
	return pattern[x][y];
}

// Cloud noise function
float cloud_noise(vec2 uv, float time_offset) {
	float noise = 0.0;
	noise += sin(uv.x * 2.0 + time_offset) * sin(uv.y * 2.0 + time_offset) * 0.5;
	noise += sin(uv.x * 4.0 - time_offset * 0.7) * sin(uv.y * 4.0 + time_offset * 0.3) * 0.25;
	noise = noise * 0.5 + 0.5; // Normalize to 0-1
	return noise;
}

void fragment() {
	// Base scaling for our 640x640 context
	float pixel_scale = 4.0; // Minimum design pixel
	vec2 scaled_pos = FRAGCOORD.xy / pixel_scale;
	
	// Multiple overlapping dither patterns with different scales and offsets
	float pattern1 = get_dither_value(
		scaled_pos + vec2(TIME * 0.2, TIME * 0.1), 
		bayer8x8_1, 
		2.0 // 8x8 effective pattern
	);
	
	float pattern2 = get_dither_value(
		scaled_pos + vec2(-TIME * 0.15, TIME * 0.25), 
		bayer8x8_2, 
		3.0 // 12x12 effective pattern
	);
	
	// Animated cloud-like noise patterns
	float cloud1 = cloud_noise(UV * 4.0, TIME * 0.1);
	float cloud2 = cloud_noise(UV * 2.0 + vec2(TIME * 0.05), TIME * -0.15);
	
	// Combine patterns with clouds
	float combined_pattern = mix(pattern1, pattern2, 0.5);
	combined_pattern = mix(combined_pattern, cloud1, 0.3);
	combined_pattern = mix(combined_pattern, cloud2, 0.2);
	
	// Very subtle pulse
	float pulse = (sin(TIME * pulse_speed) * 0.5 + 0.5) * pulse_intensity * 0.3;
	
	// Use the combined pattern for intensity
	float final_intensity = combined_pattern * (0.15 + pulse);
	
	// Mix between background and foreground colors based on pattern
	vec4 output_color = mix(
		background_color,
		foreground_color,
		final_intensity * 0.15 // Reduced mix factor for subtlety
	);
	
	COLOR = output_color;
	COLOR.a = background_color.a;
} 