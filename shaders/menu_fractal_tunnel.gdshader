shader_type canvas_item;

uniform vec4 background_color : source_color;
uniform vec4 foreground_color : source_color;
uniform float speed : hint_range(0.1, 2.0) = 0.5;
uniform float rotation_speed : hint_range(-1.0, 1.0) = 0.2;
uniform float square_count : hint_range(4.0, 12.0) = 8.0;
uniform float sparsity : hint_range(0.1, 0.9) = 0.4;

const float DESIGN_RES = 640.0;
const float MIN_PIXEL_SIZE = 4.0; // Minimum design pixel size

// Quantize a value to the nearest pixel grid
vec2 quantize_to_grid(vec2 value) {
    return floor(value * (DESIGN_RES / MIN_PIXEL_SIZE)) / (DESIGN_RES / MIN_PIXEL_SIZE);
}

// Rotation matrix
mat2 rotate2d(float angle) {
    float s = sin(angle);
    float c = cos(angle);
    return mat2(vec2(c, -s), vec2(s, c));
}

// Square SDF (Signed Distance Field)
float square_sdf(vec2 p, float size) {
    vec2 d = abs(p) - size;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Repeated square pattern with rotation
float square_pattern(vec2 uv, float size, float angle) {
    // Center and rotate UV
    vec2 center_uv = uv - 0.5;
    center_uv = rotate2d(angle) * center_uv;
    
    // Scale for aspect ratio and quantize
    center_uv = quantize_to_grid(center_uv);
    
    // Get base square
    float square = square_sdf(center_uv, size);
    
    // Add some variation based on position and time
    float time_quantized = floor(TIME * speed * 8.0) / 8.0; // Quantize time for chunkier animation
    float variation = sin(length(center_uv) * 4.0 - time_quantized * speed) * 0.1;
    
    // Hard step instead of smooth for pixelated look
    return step(0.015, abs(square + variation));
}

// Dither pattern using 4x4 Bayer matrix
float get_dither_value(vec2 pixel_pos) {
    const mat4 bayer = mat4(
        vec4(0.0, 8.0, 2.0, 10.0),
        vec4(12.0, 4.0, 14.0, 6.0),
        vec4(3.0, 11.0, 1.0, 9.0),
        vec4(15.0, 7.0, 13.0, 5.0)
    ) / 16.0;
    
    int x = int(mod(pixel_pos.x, 4.0));
    int y = int(mod(pixel_pos.y, 4.0));
    return bayer[x][y];
}

void fragment() {
    // Quantize UV to pixel grid
    vec2 pixel_pos = floor(UV * DESIGN_RES);
    vec2 uv = pixel_pos / DESIGN_RES;
    
    vec4 final_color = background_color;
    float dither = get_dither_value(pixel_pos);
    
    // Create multiple rotating squares of different sizes
    for(float i = 0.0; i < square_count; i++) {
        float size = 0.1 + 0.3 * (i / square_count);
        // Quantize time for chunkier animation
        float t = floor(TIME * speed * 4.0) / 4.0 * (1.0 + i * 0.1);
        float angle = t * rotation_speed + i * 0.2;
        
        // Calculate square pattern
        float square = square_pattern(uv, size, angle);
        
        // Add depth effect
        float depth = 1.0 - (i / square_count);
        depth = pow(depth, 2.0); // More contrast in depth
        
        // Modulate by distance from center for tunnel effect
        float dist_from_center = length(uv - 0.5);
        float edge_fade = 1.0 - step(0.45, dist_from_center); // Sharp cutoff
        
        // Only draw some squares based on sparsity and dither
        if (mod(i, 1.0 / sparsity) < 1.0 && dither > 0.5) {
            vec4 square_color = mix(background_color, foreground_color, depth * edge_fade);
            final_color = mix(final_color, square_color, (1.0 - square) * depth * 0.4);
        }
    }
    
    // Add pixelated center glow
    float center_glow = 1.0 - length(quantize_to_grid(uv - 0.5)) * 2.0;
    center_glow = step(0.7, center_glow) * 0.2; // Sharp glow
    center_glow *= floor(sin(TIME * 0.5) * 2.0) / 2.0; // Quantized pulse
    
    final_color = mix(final_color, foreground_color, center_glow);
    
    COLOR = final_color;
} 