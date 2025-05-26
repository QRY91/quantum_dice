shader_type canvas_item;

// Define the palette colors your shader will use.
// These are exposed in the Inspector when you apply the material.
uniform vec4 palette_background_color : source_color = vec4(0.93, 0.87, 0.80, 1.0); // Creamy white (Downwell-ish)
uniform vec4 palette_main_color : source_color = vec4(0.10, 0.08, 0.12, 1.0);     // Dark indigo/black (Downwell-ish)
uniform vec4 palette_accent_color : source_color = vec4(0.90, 0.25, 0.20, 1.0);   // Red (Downwell-ish)

// Define the placeholder colors your original sprite art uses.
// These should match what you used to draw your sprites.
uniform vec4 source_placeholder_bg : source_color = vec4(1.0, 1.0, 1.0, 1.0);    // Pure White
uniform vec4 source_placeholder_main : source_color = vec4(0.0, 0.0, 0.0, 1.0);  // Pure Black
uniform vec4 source_placeholder_accent : source_color = vec4(1.0, 0.0, 0.0, 1.0); // Pure Red


// A small tolerance for color matching.
// hint_range makes it a slider in the inspector.
uniform float color_match_tolerance : hint_range(0.0, 0.5, 0.001) = 0.05;


void fragment() {
    vec4 original_color = texture(TEXTURE, UV);
    vec4 final_color = original_color;

    if (original_color.a > 0.1) {
        if (distance(original_color.rgb, source_placeholder_main.rgb) < color_match_tolerance) {
            final_color = palette_main_color;
        }
        else if (distance(original_color.rgb, source_placeholder_accent.rgb) < color_match_tolerance) {
            final_color = palette_accent_color;
        }
        else if (distance(original_color.rgb, source_placeholder_bg.rgb) < color_match_tolerance) {
            final_color = palette_background_color;
        }
        else {
            // Fallback for opaque colors that don't match any placeholder.
            // You might want them to become background, main, or remain original.
            // For a strict palette swap, making them one of the palette colors is typical.
            final_color = palette_background_color; 
        }
        final_color.a = original_color.a; // Preserve original alpha
    } else {
        final_color = vec4(0.0, 0.0, 0.0, 0.0); // Keep transparent
    }

    COLOR = final_color;
}