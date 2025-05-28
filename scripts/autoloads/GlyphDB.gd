# res://scripts/autoloads/GlyphDB.gd
extends Node

## Dictionary to hold all loaded glyph data, keyed by glyph ID.
var all_glyphs: Dictionary = {}

## Array defining the glyphs on the player's starting dice.
var starting_dice_configuration: Array[GlyphData] = []

## List of glyphs that can be offered as loot.
var potential_loot_glyphs: Array[GlyphData] = []

const GLYPHS_BASE_PATH: String = "res://resources/glyphs/"

func _ready():
	_load_all_glyph_resources_recursively(GLYPHS_BASE_PATH)
	_setup_starting_configurations() # This can stay the same as it uses all_glyphs
	print("GlyphDB initialized. Loaded %d glyphs. Starting dice: %d faces. Potential loot: %d types." % [all_glyphs.size(), starting_dice_configuration.size(), potential_loot_glyphs.size()])

# Recursive function to load glyph resources
func _load_all_glyph_resources_recursively(path: String):
	var dir = DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name == "." or file_name == "..": # Skip current and parent directory entries
				file_name = dir.get_next()
				continue

			var full_path = path.path_join(file_name) # Use path_join for robust path construction

			if dir.current_is_dir():
				_load_all_glyph_resources_recursively(full_path) # Recurse into subdirectory
			elif file_name.ends_with(".tres"): # Ensure it's a .tres file
				var glyph_data: GlyphData = load(full_path)
				if glyph_data is GlyphData: # Check if loaded and correct type
					if glyph_data.id == "" or glyph_data.id == "unknown_glyph": # Check for uninitialized/default ID
						printerr("GlyphDB Warning: GlyphData resource at path '", full_path, "' has a default or empty ID ('", glyph_data.id,"'). Skipping.")
					elif not all_glyphs.has(glyph_data.id):
						all_glyphs[glyph_data.id] = glyph_data
						# print("GlyphDB: Loaded glyph '", glyph_data.id, "' from path: ", full_path) # Optional: for verbose logging
					else:
						printerr("GlyphDB Error: Duplicate glyph ID found: '", glyph_data.id, "'. Path: '", full_path, "'. Previous was: '", all_glyphs[glyph_data.id].resource_path, "'. Overwriting.")
						all_glyphs[glyph_data.id] = glyph_data # Decide on overwrite or skip behavior
				else:
					# This might also catch non-GlyphData .tres files if they exist in the folders
					# print("GlyphDB Info: File at path '", full_path, "' is a .tres file but not of type GlyphData. Skipping.")
					pass # Silently skip non-GlyphData .tres files
			
			file_name = dir.get_next()
		# dir.list_dir_end() # Not strictly necessary in Godot 4 for DirAccess after loop
	else:
		printerr("GlyphDB Error: Could not open directory '", path, "' for recursive loading.")


var add_test_runes_to_start: bool = true
func _setup_starting_configurations():
	starting_dice_configuration.clear()
	potential_loot_glyphs.clear()

	var starting_ids = ["dice_1", "dice_2", "dice_3", "dice_4", "dice_5", "dice_6"]
	if add_test_runes_to_start:
		starting_ids.append("rune_sowilo")
		starting_ids.append("rune_fehu")
		# Also add your new Photon Twins if you want them in the starting dice for testing
		# starting_ids.append("photon_alpha")
		# starting_ids.append("photon_beta")


	for glyph_id in starting_ids:
		if all_glyphs.has(glyph_id):
			starting_dice_configuration.append(all_glyphs[glyph_id])
		else:
			printerr("GlyphDB Warning: Starting glyph ID '", glyph_id, "' not found in all_glyphs.")

	for glyph_id in all_glyphs:
		var glyph: GlyphData = all_glyphs[glyph_id]
		# Adjust loot pool criteria as needed
		# Example: Exclude dice, superposition, and photon twins from general loot initially
		# if glyph.type != "dice" and glyph.type != "superposition" and not glyph.id.begins_with("photon_"):
		if glyph.type != "dice": # Simpler: all non-dice are lootable
			if not potential_loot_glyphs.has(glyph): # Ensure no duplicates if IDs could be non-unique (though they shouldn't)
				potential_loot_glyphs.append(glyph)
	
	if starting_dice_configuration.is_empty() and not all_glyphs.is_empty():
		print("GlyphDB Warning: Starting dice configuration is empty despite loaded glyphs. Check starting_ids.")
	if potential_loot_glyphs.is_empty() and all_glyphs.size() > starting_dice_configuration.size():
		print("GlyphDB Warning: No potential loot glyphs identified based on current criteria.")


func get_glyph_by_id(id: String) -> GlyphData: # Parameter type should be String or StringName consistently
	var s_name_id = StringName(id) # Convert to StringName if id is passed as String
	if all_glyphs.has(s_name_id):
		return all_glyphs[s_name_id]
	printerr("GlyphDB Error: Glyph with ID '", id, "' (StringName: '", str(s_name_id), "') not found.")
	return null

var force_specific_loot_for_testing: bool = true
var test_loot_sequence: Array[String] = [
	"photon_alpha", # Test getting photon twins
	"photon_beta",
	"superposition_dice_or_card",
	"superposition_dice_or_rune",
	"rune_sowilo", 
	"rune_fehu", 
	"rune_laguz", 
	"rune_ansuz"
]
var current_test_loot_index: int = 0

func _get_truly_random_loot(count: int) -> Array[GlyphData]:
	var available_loot_pool: Array[GlyphData] = potential_loot_glyphs.duplicate()
	var loot_options: Array[GlyphData] = []
	if available_loot_pool.is_empty(): return loot_options
	
	available_loot_pool.shuffle()
	for i in range(min(count, available_loot_pool.size())):
		loot_options.append(available_loot_pool[i])
	return loot_options

func get_random_loot_options(count: int, _current_player_dice_faces_unused: Array[GlyphData] = []) -> Array[GlyphData]:
	if force_specific_loot_for_testing:
		var forced_loot_options: Array[GlyphData] = []
		var attempted_ids_this_call: Array[String] = [] # To avoid offering same test item twice in one call if count > 1

		for i in range(count):
			if current_test_loot_index < test_loot_sequence.size():
				var glyph_id_to_force = test_loot_sequence[current_test_loot_index]
				
				# Ensure we don't offer the same forced item multiple times in a single loot offering
				var max_attempts_for_unique_test_item = test_loot_sequence.size() # Safety break
				var attempts = 0
				while attempted_ids_this_call.has(glyph_id_to_force) and attempts < max_attempts_for_unique_test_item :
					current_test_loot_index = (current_test_loot_index + 1) % test_loot_sequence.size() # Cycle through test loot
					glyph_id_to_force = test_loot_sequence[current_test_loot_index]
					attempts += 1
				
				if not attempted_ids_this_call.has(glyph_id_to_force):
					var glyph_data = get_glyph_by_id(glyph_id_to_force)
					if is_instance_valid(glyph_data):
						forced_loot_options.append(glyph_data)
						attempted_ids_this_call.append(glyph_id_to_force)
					else:
						printerr("GlyphDB Test Loot: Could not find glyph with ID: ", glyph_id_to_force)
					current_test_loot_index = (current_test_loot_index + 1) # Move to next for next *call* or next item in *this* call
				else: # Could not find a unique test item for this slot
					pass # Will fall through to random if not enough unique test items for 'count'
			else: # Ran out of specific test loot sequence
				current_test_loot_index = 0 # Reset for next time if desired
				break # Stop trying to add forced items if sequence exhausted

		# If not enough forced items were found for the requested count, fill with random
		var remaining_to_fill = count - forced_loot_options.size()
		if remaining_to_fill > 0:
			var random_fill_options = _get_truly_random_loot(remaining_to_fill)
			# Ensure no duplicates with already forced ones (simple check by id)
			for random_glyph in random_fill_options:
				var already_forced = false
				for forced_glyph in forced_loot_options:
					if forced_glyph.id == random_glyph.id:
						already_forced = true
						break
				if not already_forced:
					forced_loot_options.append(random_glyph)
					if forced_loot_options.size() == count: break # Stop if we filled up
		
		print("GlyphDB: FORCING/PROVIDING TEST LOOT: ", forced_loot_options)
		return forced_loot_options

	# --- Original random loot logic (kept as fallback) ---
	return _get_truly_random_loot(count)
