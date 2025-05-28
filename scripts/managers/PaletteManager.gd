# res://scripts/managers/PaletteManager.gd (or your preferred path)
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
# or if the saved palette ID is invalid.
# Make sure this ID matches one of your .tres files (e.g., your "default_bw").
const FALLBACK_DEFAULT_PALETTE_ID: StringName = &"default_bw"


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


func _load_palette_definitions():
	available_palettes.clear()
	var dir = DirAccess.open(PALETTES_DIR_PATH)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".tres"):
				var palette_resource_path = PALETTES_DIR_PATH + file_name
				var palette_def: PaletteDefinition = load(palette_resource_path)
				if palette_def is PaletteDefinition:
					if palette_def.id == &"":
						printerr("PaletteManager: Palette resource at '%s' has an empty ID. Skipping." % palette_resource_path)
					elif available_palettes.has(palette_def.id):
						printerr("PaletteManager: Duplicate palette ID '%s' found at '%s'. Previous one will be overwritten." % [str(palette_def.id), palette_resource_path])
					
					available_palettes[palette_def.id] = palette_def
					if palette_def.is_unlocked_by_default and not unlocked_palette_ids.has(palette_def.id):
						unlocked_palette_ids.append(palette_def.id)
				else:
					printerr("PaletteManager: Failed to load PaletteDefinition resource at: ", palette_resource_path)
			file_name = dir.get_next()
	else:
		printerr("PaletteManager: Could not open palettes directory: ", PALETTES_DIR_PATH)

	if available_palettes.is_empty():
		printerr("PaletteManager: No palette definition files (.tres) found in %s" % PALETTES_DIR_PATH)


func _load_settings():
	var config = ConfigFile.new()
	var err = config.load(SAVE_FILE_PATH)
	if err == OK:
		current_user_palette_id = StringName(config.get_value("user_settings", "current_palette_id", str(FALLBACK_DEFAULT_PALETTE_ID)))
		var loaded_unlocked_ids_str: Array = config.get_value("user_settings", "unlocked_palette_ids", [])
		
		unlocked_palette_ids.clear() # Clear existing (from default unlocks) before loading saved
		for id_str in loaded_unlocked_ids_str:
			unlocked_palette_ids.append(StringName(id_str))
		
		# Re-add default unlocks if they weren't in the save file (e.g. new defaults added)
		for pal_id in available_palettes:
			var pal_def: PaletteDefinition = available_palettes[pal_id]
			if pal_def.is_unlocked_by_default and not unlocked_palette_ids.has(pal_id):
				unlocked_palette_ids.append(pal_id)
		
		print("PaletteManager: Settings loaded. User palette: '%s', Unlocked count: %d" % [str(current_user_palette_id), unlocked_palette_ids.size()])
	else:
		print("PaletteManager: No save file found or error loading (%s). Using defaults." % err)
		# current_user_palette_id will be set to FALLBACK_DEFAULT_PALETTE_ID in _ready if needed
		# unlocked_palette_ids will already contain defaults from _load_palette_definitions


func _save_settings():
	var config = ConfigFile.new()
	config.set_value("user_settings", "current_palette_id", str(current_user_palette_id))
	
	var unlocked_ids_str_array: Array[String] = []
	for id_sname in unlocked_palette_ids:
		unlocked_ids_str_array.append(str(id_sname))
	config.set_value("user_settings", "unlocked_palette_ids", unlocked_ids_str_array)
	
	var err = config.save(SAVE_FILE_PATH)
	if err != OK:
		printerr("PaletteManager: Error saving palette settings to '%s'. Error code: %s" % [SAVE_FILE_PATH, err])
	else:
		print("PaletteManager: Settings saved.")


func _broadcast_active_palette():
	var colors_to_broadcast = get_current_palette_colors()
	emit_signal("active_palette_updated", colors_to_broadcast)
	# print("PaletteManager: Broadcasting active palette: BG:%s, Main:%s, Accent:%s" % [colors_to_broadcast.background, colors_to_broadcast.main, colors_to_broadcast.accent])


## Returns the colors of the currently active palette (user or temporary).
func get_current_palette_colors() -> Dictionary:
	if temporary_palette_active and not temporary_palette_colors.is_empty():
		return temporary_palette_colors

	if available_palettes.has(current_user_palette_id):
		var palette_def: PaletteDefinition = available_palettes[current_user_palette_id]
		return {
			"background": palette_def.palette_background_color,
			"main": palette_def.palette_main_color,
			"accent": palette_def.palette_accent_color
		}
	elif not available_palettes.is_empty(): # Fallback if current_user_palette_id is somehow invalid but palettes exist
		printerr("PaletteManager: current_user_palette_id '%s' is invalid, using first available palette as fallback for colors." % str(current_user_palette_id))
		var first_palette_def: PaletteDefinition = available_palettes.values()[0]
		return {
			"background": first_palette_def.palette_background_color,
			"main": first_palette_def.palette_main_color,
			"accent": first_palette_def.palette_accent_color
		}
	
	# Absolute fallback - should ideally not be reached if FALLBACK_DEFAULT_PALETTE_ID is valid
	printerr("PaletteManager: CRITICAL - No valid current or fallback palette found. Returning default black/white/red.")
	return {
		"background": Color.BLACK,
		"main": Color.WHITE,
		"accent": Color.RED
	}


## Sets the user's preferred palette. This choice persists across sessions.
func set_user_palette(palette_id: StringName):
	if not available_palettes.has(palette_id):
		printerr("PaletteManager: Cannot set user palette. ID '%s' not found." % str(palette_id))
		return
	if not unlocked_palette_ids.has(palette_id):
		printerr("PaletteManager: Cannot set user palette. ID '%s' is not unlocked." % str(palette_id))
		# Optionally, allow setting if it's a default one, even if somehow missing from unlocked_palette_ids
		# var pal_def: PaletteDefinition = available_palettes[palette_id]
		# if not pal_def.is_unlocked_by_default: return
		return

	current_user_palette_id = palette_id
	print("PaletteManager: User palette set to '%s'." % str(current_user_palette_id))
	_save_settings()
	
	# If a temporary palette is not active, broadcast the change immediately.
	# If a temporary one IS active, it will revert to this new user choice when it expires.
	if not temporary_palette_active:
		_broadcast_active_palette()


## Unlocks a palette for user selection.
func unlock_palette(palette_id: StringName):
	if not available_palettes.has(palette_id):
		printerr("PaletteManager: Cannot unlock palette. ID '%s' not found." % str(palette_id))
		return
	if not unlocked_palette_ids.has(palette_id):
		unlocked_palette_ids.append(palette_id)
		print("PaletteManager: Palette '%s' unlocked!" % str(palette_id))
		_save_settings()
		# Optionally, emit a signal like "palette_unlocked" for UI updates
	else:
		print("PaletteManager: Palette '%s' was already unlocked." % str(palette_id))


## Applies a temporary palette override, e.g., for a gameplay effect.
func apply_temporary_palette(palette_id: StringName, duration_seconds: float):
	if not available_palettes.has(palette_id):
		printerr("PaletteManager: Cannot apply temporary palette. ID '%s' not found." % str(palette_id))
		return
	if duration_seconds <= 0:
		printerr("PaletteManager: Temporary palette duration must be greater than 0.")
		return

	var palette_def: PaletteDefinition = available_palettes[palette_id]
	temporary_palette_colors = {
		"background": palette_def.palette_background_color,
		"main": palette_def.palette_main_color,
		"accent": palette_def.palette_accent_color
	}
	temporary_palette_active = true
	
	temporary_palette_duration_timer.stop() # Stop any previous timer
	temporary_palette_duration_timer.wait_time = duration_seconds
	temporary_palette_duration_timer.start()
	
	print("PaletteManager: Temporary palette '%s' applied for %s seconds." % [str(palette_id), duration_seconds])
	_broadcast_active_palette()


func _on_temporary_palette_timer_timeout():
	print("PaletteManager: Temporary palette duration ended.")
	revert_to_user_palette()


## Clears any temporary palette and reverts to the user's selected palette.
func revert_to_user_palette():
	if temporary_palette_active:
		temporary_palette_active = false
		temporary_palette_colors.clear()
		temporary_palette_duration_timer.stop() # Ensure timer is stopped
		print("PaletteManager: Reverted to user palette '%s'." % str(current_user_palette_id))
		_broadcast_active_palette()


## Returns an array of dictionaries for UI display, containing id, display_name, and colors.
## Only includes unlocked palettes.
func get_all_displayable_palettes() -> Array[Dictionary]:
	var display_list: Array[Dictionary] = []
	for pal_id in unlocked_palette_ids:
		if available_palettes.has(pal_id):
			var pal_def: PaletteDefinition = available_palettes[pal_id]
			display_list.append({
				"id": pal_def.id,
				"display_name": pal_def.display_name,
				"background_color": pal_def.palette_background_color,
				"main_color": pal_def.palette_main_color,
				"accent_color": pal_def.palette_accent_color
			})
		else:
			printerr("PaletteManager: Unlocked palette ID '%s' not found in available_palettes during get_all_displayable_palettes." % str(pal_id))
			
	# Optionally sort them, e.g., by display_name
	# display_list.sort_custom(func(a, b): return a.display_name < b.display_name)
	return display_list
