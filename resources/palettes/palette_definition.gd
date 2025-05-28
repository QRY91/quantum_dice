# res://resources/palettes/palette_definition.gd
extends Resource
class_name PaletteDefinition # This makes "PaletteDefinition" appear in the "New Resource..." dialog

## Unique identifier (e.g., "default_downwell", "classic_bw")
@export var id: StringName = &"" # Using StringName for optimized comparisons

## Name displayed to the player (e.g., "Classic Retro", "Black & White")
@export var display_name: String = "Unnamed Palette"

## The color that will replace the source_placeholder_bg in the shader
@export var palette_background_color: Color = Color.BLACK # Defaulting to black as per your game's BG

## The color that will replace the source_placeholder_main in the shader
@export var palette_main_color: Color = Color.WHITE # Defaulting to white as per your game's FG

## The color that will replace the source_placeholder_accent in the shader
@export var palette_accent_color: Color = Color.RED # Default accent, can be changed per palette

## If true, this palette is available to the user from the start.
@export var is_unlocked_by_default: bool = true

# Optional: for complex unlock logic later
# @export var unlock_condition_id: String = "" 

# Constructor for programmatic creation (less used for .tres files but good practice)
func _init(p_id: StringName = &"", 
			p_display_name: String = "", 
			p_bg_color: Color = Color.BLACK, 
			p_main_color: Color = Color.WHITE, 
			p_accent_color: Color = Color.RED,
			p_unlocked_default: bool = true):
	if p_id != &"": id = p_id # Check against empty StringName
	if p_display_name != "": display_name = p_display_name
	palette_background_color = p_bg_color
	palette_main_color = p_main_color
	palette_accent_color = p_accent_color
	is_unlocked_by_default = p_unlocked_default
