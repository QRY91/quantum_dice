# res://scripts/managers/PlayerDiceManager.gd
# TABS FOR INDENTATION
extends Node

signal player_dice_changed(new_dice_array: Array[GlyphData]) # Emitted when dice composition changes

var current_player_dice: Array[GlyphData] = []

func _ready():
	print("PlayerDiceManager: Initialized.")
	# Initial dice setup is now handled by reset_for_new_run, called by Game.gd

func reset_for_new_run():
	current_player_dice.clear()
	if GlyphDB and not GlyphDB.starting_dice_configuration.is_empty():
		current_player_dice = GlyphDB.starting_dice_configuration.duplicate(true) # Ensure deep copy
		print("PlayerDiceManager: Dice initialized for new run with %d faces." % current_player_dice.size())
	else:
		printerr("PlayerDiceManager: GlyphDB not ready or starting_dice_configuration is empty!")
	emit_signal("player_dice_changed", current_player_dice)


func add_glyph_to_dice(glyph_data: GlyphData):
	if not is_instance_valid(glyph_data):
		printerr("PlayerDiceManager: Attempted to add invalid glyph data to dice.")
		return
		
	current_player_dice.append(glyph_data)
	print("PlayerDiceManager: Added glyph '%s' to player dice. Total faces: %d" % [glyph_data.display_name, current_player_dice.size()])
	emit_signal("player_dice_changed", current_player_dice)


func get_current_dice() -> Array[GlyphData]:
	return current_player_dice # Returns a reference, be careful if modifying externally (use .duplicate() if needed)

func get_random_glyph_from_dice() -> GlyphData:
	if current_player_dice.is_empty():
		printerr("PlayerDiceManager: CRITICAL - Attempted to get glyph from empty dice!")
		return null # Or a default error glyph
	
	var rolled_glyph_index = randi() % current_player_dice.size()
	return current_player_dice[rolled_glyph_index]
