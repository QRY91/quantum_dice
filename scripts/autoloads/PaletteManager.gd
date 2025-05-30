# res://scripts/autoloads/PaletteManager.gd
extends Node

## Emitted when the effective palette (user-selected or temporary override) changes.
## Provides a dictionary with the target colors for the shader.
signal active_palette_updated(palette_colors: Dictionary)

const PALETTES_DIR_PATH: String = "res://resources/palettes/"
const SAVE_FILE_PATH: String = "user://palette_settings.save"

# Stores all loaded PaletteDefinition resources, keyed by their StringName id
var available_palettes: Dictionary = {}

# Stores the StringName id of the user's chosen palette
var current_user_palette_id: StringName = &"" 
# Stores StringName ids of palettes the user has unlocked
var unlocked_palette_ids: Array[StringName] = []

# For temporary palette overrides (e.g., for gameplay events)
var temporary_palette_active: bool = false
var temporary_palette_colors: Dictionary = {} # Stores {"background": Color, "main": Color, "accent": Color}
var temporary_palette_duration_timer: Timer

# The ID of the palette that should be considered the game's default if no save file exists
const FALLBACK_DEFAULT_PALETTE_ID: StringName = &"quantum_void" # Changed to our new default

func _ready():
	_load_palette_definitions()
	_load_settings() # Load user's choice and unlocks

	temporary_palette_duration_timer = Timer.new()
	temporary_palette_duration_timer.one_shot = true
	temporary_palette_duration_timer.timeout.connect(_on_temporary_palette_timer_timeout)
	add_child(temporary_palette_duration_timer)

	# Ensure current_user_palette_id is valid, otherwise use fallback
	if not available_palettes.has(current_user_palette_id):
		printerr("PaletteManager: Saved user palette ID '%s' not found in available palettes. Reverting to fallback '%s'." % [str(current_user_palette_id), str(FALLBACK_DEFAULT_PALETTE_ID)])
		current_user_palette_id = FALLBACK_DEFAULT_PALETTE_ID
		if not available_palettes.has(current_user_palette_id): # Fallback itself is missing
			printerr("PaletteManager: CRITICAL - Fallback default palette ID '%s' also not found! Palette system may not work." % str(FALLBACK_DEFAULT_PALETTE_ID))
			# Attempt to use the first available unlocked palette, or the very first palette loaded
			if not unlocked_palette_ids.is_empty() and available_palettes.has(unlocked_palette_ids[0]):
				current_user_palette_id = unlocked_palette_ids[0]
			elif not available_palettes.is_empty():
				current_user_palette_id = available_palettes.keys()[0]

	_broadcast_active_palette() # Broadcast the initial palette
	print("PaletteManager: Ready. Loaded %d palettes. Current user palette: '%s'." % [available_palettes.size(), str(current_user_palette_id)])

# ... rest of the file remains unchanged ... 