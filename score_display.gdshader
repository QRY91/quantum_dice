shader_type canvas_item;

// Uniforms to be set by the PaletteManager
uniform vec4 tier_base_color : source_color; // Color for text before any tier is met
uniform vec4 tier_bronze_color : source_color;
uniform vec4 tier_silver_color : source_color;
uniform vec4 tier_gold_color : source_color;
uniform vec4 tier_platinum_color : source_color; // This might be the accent or a special platinum color from palette

uniform float score_ratio = 0.0; // 0.0 to 1.0

// Thresholds for success tiers
const float BRONZE_THRESHOLD = 0.25;
const float SILVER_THRESHOLD = 0.5;
const float GOLD_THRESHOLD = 0.75;
const float PLATINUM_THRESHOLD = 0.95; // Requires near perfect

// Variables for shimmer effect (platinum)
uniform float time;
uniform float shimmer_speed = 1.0;
uniform float shimmer_intensity = 0.1;
uniform float shimmer_scale = 10.0;


// Basic noise function
float noise(vec2 uv) {
    return fract(sin(dot(uv, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
    vec4 current_color = tier_base_color;

    if (score_ratio >= PLATINUM_THRESHOLD) {
        current_color = tier_platinum_color;
        // Add a subtle, fast-moving shimmer for platinum
        float shimmer = (noise(UV * shimmer_scale + vec2(time * shimmer_speed, 0.0)) - 0.5) * shimmer_intensity;
        current_color.rgb += shimmer;
    } else if (score_ratio >= GOLD_THRESHOLD) {
        current_color = tier_gold_color;
    } else if (score_ratio >= SILVER_THRESHOLD) {
        current_color = tier_silver_color;
    } else if (score_ratio >= BRONZE_THRESHOLD) {
        current_color = tier_bronze_color;
    }

    COLOR = current_color * texture(TEXTURE, UV);
} 