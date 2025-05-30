shader_type canvas_item;

uniform vec4 background_color : source_color;
uniform vec4 foreground_color : source_color;
uniform float speed : hint_range(0.1, 2.0) = 0.5;
uniform float rotation_speed : hint_range(-1.0, 1.0) = 0.2;
uniform float square_count : hint_range(4.0, 12.0) = 8.0;
uniform float sparsity : hint_range(0.1, 0.9) = 0.4;

const float DESIGN_RES = 640.0;
const float MIN_PIXEL_SIZE = 4.0;

// Simplified rotation matrix
mat2 rotate2d(float angle) {
    float s = sin(angle);
    float c = cos(angle);
    return mat2(vec2(c, -s), vec2(s, c));
}

// Simplified square pattern
float square_pattern(vec2 uv, float size, float angle) {
    vec2 center_uv = uv - 0.5;
    center_uv = rotate2d(angle) * center_uv;
    
    vec2 d = abs(center_uv) - size;
    float square = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
    
    return step(0.015, abs(square));
}

void fragment() {
    // Basic setup
    vec2 uv = UV;
    vec4 final_color = background_color;
    
    // Reduced number of squares for better performance
    float actual_squares = min(square_count, 6.0);
    
    // Create tunnel effect with fewer iterations
    for(float i = 0.0; i < actual_squares; i++) {
        float size = 0.1 + 0.3 * (i / actual_squares);
        float t = TIME * speed * (1.0 + i * 0.1);
        float angle = t * rotation_speed + i * 0.2;
        
        float square = square_pattern(uv, size, angle);
        float depth = 1.0 - (i / actual_squares);
        depth = depth * depth; // Simplified depth effect
        
        // Basic distance fade
        float dist_from_center = length(uv - 0.5);
        float edge_fade = 1.0 - smoothstep(0.4, 0.5, dist_from_center);
        
        // Simplified color mixing
        if (mod(i, 2.0) < 1.0) { // Simpler sparsity check
            vec4 square_color = mix(background_color, foreground_color, depth * edge_fade);
            final_color = mix(final_color, square_color, (1.0 - square) * depth * 0.4);
        }
    }
    
    // Simplified center glow
    float center_glow = (1.0 - length(uv - 0.5) * 2.0) * 0.2;
    center_glow *= sin(TIME * 0.5) * 0.5 + 0.5;
    
    final_color = mix(final_color, foreground_color, center_glow);
    
    COLOR = final_color;
} 