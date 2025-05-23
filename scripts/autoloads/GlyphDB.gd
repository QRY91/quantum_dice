# res://scripts/autoloads/GlyphDB.gd
extends Node

## Dictionary to hold all loaded glyph data, keyed by glyph ID.
var all_glyphs: Dictionary = {}

## Array defining the glyphs on the player's starting die.
var starting_die_configuration: Array[GlyphData] = []

## List of glyphs that can be offered as loot.
var potential_loot_glyphs: Array[GlyphData] = []


func _ready():
	_load_all_glyph_resources()
	_setup_starting_configurations()
	print("GlyphDB initialized. Loaded %d glyphs. Starting die: %d faces. Potential loot: %d types." % [all_glyphs.size(), starting_die_configuration.size(), potential_loot_glyphs.size()])


func _load_all_glyph_resources():
	all_glyphs.clear()
	var dir = DirAccess.open("res://resources/glyphs/")
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".tres"): # Ensure it's a .tres file
				var glyph_resource_path = "res://resources/glyphs/" + file_name
				var glyph_data: GlyphData = load(glyph_resource_path)
				if glyph_data and glyph_data is GlyphData: # Check if loaded and correct type
					if not all_glyphs.has(glyph_data.id):
						all_glyphs[glyph_data.id] = glyph_data
					else:
						printerr("GlyphDB Error: Duplicate glyph ID found: '", glyph_data.id, "' from path: ", glyph_resource_path)
				else:
					printerr("GlyphDB Error: Failed to load GlyphData resource at path: ", glyph_resource_path, " or it's not of type GlyphData.")
			file_name = dir.get_next()
		# dir.list_dir_end() # No longer needed in Godot 4 for DirAccess
	else:
		printerr("GlyphDB Error: Could not open directory 'res://resources/glyphs/'")


func _setup_starting_configurations():
	starting_die_configuration.clear()
	potential_loot_glyphs.clear()

	# Define the player's starting die faces by their IDs
	# Ensure these IDs match the 'id' field in your .tres files
	var starting_ids = ["dice_1", "dice_2", "dice_3", "dice_4", "dice_5", "dice_6"]
	
	for glyph_id in starting_ids:
		if all_glyphs.has(glyph_id):
			starting_die_configuration.append(all_glyphs[glyph_id])
		else:
			printerr("GlyphDB Warning: Starting glyph ID '", glyph_id, "' not found in all_glyphs.")

	# Define potential loot glyphs
	# For example, anything not of type "dice"
	for glyph_id in all_glyphs: # Iterate through dictionary keys
		var glyph: GlyphData = all_glyphs[glyph_id]
		if glyph.type != "dice": # Customize this logic as needed
			potential_loot_glyphs.append(glyph)
	
	if starting_die_configuration.is_empty() and not all_glyphs.is_empty():
		print("GlyphDB Warning: Starting die configuration is empty despite loaded glyphs. Check starting_ids.")
	if potential_loot_glyphs.is_empty() and all_glyphs.size() > starting_die_configuration.size():
		print("GlyphDB Warning: No potential loot glyphs identified based on current criteria (type != 'dice').")

## Retrieves a specific glyph by its ID.
func get_glyph_by_id(id: String) -> GlyphData:
	if all_glyphs.has(id):
		return all_glyphs[id]
	printerr("GlyphDB Error: Glyph with ID '", id, "' not found.")
	return null

## Returns a specified number of random glyphs suitable for loot.
## Can exclude glyphs already owned by the player or recently offered.
func get_random_loot_options(count: int, exclude_current_die_faces: Array[GlyphData] = []) -> Array[GlyphData]:
	var available_loot: Array[GlyphData] = []
	var exclude_ids: Array[String] = [] # Store IDs of glyphs to exclude

	for glyph_to_exclude in exclude_current_die_faces:
		if glyph_to_exclude and glyph_to_exclude is GlyphData: # Ensure it's not null and is Glyph
			exclude_ids.append(glyph_to_exclude.id)

	for glyph in potential_loot_glyphs: # potential_loot_glyphs should already be populated with GlyphData objects
		if not glyph.id in exclude_ids:
			available_loot.append(glyph)
	
	var loot_options: Array[GlyphData] = []
	if available_loot.is_empty():
		# print("GlyphDB: No available loot options to choose from after exclusions.")
		return loot_options # Return empty if no suitable loot

	available_loot.shuffle() # Randomize the order
	
	for i in range(min(count, available_loot.size())):
		loot_options.append(available_loot[i])
		
	return loot_options
