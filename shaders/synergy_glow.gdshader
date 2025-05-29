shader_type canvas_item;

uniform vec4 glow_color : source_color = vec4(1.0, 0.8, 0.0, 0.5); // Gold/Yellowish glow
uniform float glow_strength : hint_range(0.0, 1.0) = 0.5;
uniform float pulse_speed : hint_range(0.1, 5.0) = 1.0;

void fragment() {
	vec4 current_color = texture(TEXTURE, UV);
	
	// Simple glow: add color if pixel is not transparent
	// A more advanced glow would use a blur or a distance field.
	float alpha_check = step(0.01, current_color.a); // Only apply to non-transparent parts
	
	float pulse = (sin(TIME * pulse_speed) + 1.0) / 2.0; // 0.0 to 1.0 pulse
	vec4 effect_color = glow_color * pulse * glow_strength * alpha_check;
	
	COLOR = current_color + effect_color;
	COLOR.rgb = clamp(COLOR.rgb, vec3(0.0), vec3(1.0)); // Prevent color overflow
	COLOR.a = current_color.a; // Preserve original alpha
} 