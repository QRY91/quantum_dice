# res://scripts/ui/TrackManager.gd
# TABS FOR INDENTATION
extends Control

const NUM_SLOTS: int = 15
var track_slots: Array[Node] = [] 
var track_slot_scene: PackedScene = preload("res://scenes/ui/TrackSlot.tscn")
const TrackSlotScript: Script = preload("res://scenes/ui/TrackSlot.gd") # Path to your TrackSlot.gd

var slot_local_positions: Array[Vector2] = [
	Vector2(240, 480), Vector2(160, 480), Vector2(80, 480),  # Indices 0, 1, 2 (Slot 3)
	Vector2(80, 400), Vector2(80, 320), Vector2(80, 240), Vector2(80, 160), Vector2(80, 80),
	Vector2(160, 80), Vector2(240, 80), Vector2(320, 80), Vector2(400, 80), Vector2(480, 80),
	Vector2(480, 160), Vector2(480, 240)
]
var current_next_slot_index: int = 0

var cornerstone_slot_indices: Dictionary = { # 0-based index -> effect_id (from spec)
	2: "cornerstone_slot_3_bonus",  # Slot 3
	# 7: "cornerstone_slot_8_effect", # Slot 8
	# 12: "cornerstone_slot_13_effect",# Slot 13
	# 14: "cornerstone_slot_15_effect" # Slot 15
}

func _ready():
	if not is_instance_valid(track_slot_scene):
		printerr("TrackManager: TrackSlot.tscn not loaded!"); return
	_setup_track_slots_and_cornerstones() # Combined setup

func _setup_track_slots_and_cornerstones():
	for child in get_children(): child.queue_free()
	track_slots.clear()

	for i in range(NUM_SLOTS):
		var slot_instance = track_slot_scene.instantiate()
		if slot_instance is Control:
			add_child(slot_instance)
			if i < slot_local_positions.size():
				(slot_instance as Control).position = slot_local_positions[i]
			
			var is_cs = i in cornerstone_slot_indices
			var cs_id = cornerstone_slot_indices[i] if is_cs else ""
			
			if slot_instance.has_method("initialize"):
				slot_instance.initialize(i, is_cs, cs_id) # Pass cornerstone info
			track_slots.append(slot_instance)
		else:
			printerr("TrackManager: Instantiated TrackSlot is not a Control node!")
	print("TrackManager: Setup complete with %d slots." % track_slots.size())
	current_next_slot_index = 0
	# All slots start INACTIVE, Game.gd will activate them per round

func activate_slots_for_round(num_active_slots: int): # Called by Game.gd via HUD
	for i in range(NUM_SLOTS):
		var slot_node = track_slots[i]
		if is_instance_valid(slot_node) and slot_node.has_method("activate_slot") and slot_node.has_method("deactivate_slot"):
			if i < num_active_slots:
				slot_node.activate_slot()
			else:
				slot_node.deactivate_slot()
	current_next_slot_index = 0 # Reset for placing glyphs

func place_glyph_on_next_available_slot(glyph_data: GlyphData):
	if current_next_slot_index < track_slots.size():
		var target_slot = track_slots[current_next_slot_index]
		if is_instance_valid(target_slot) and target_slot.has_method("place_glyph"):
			# First, ensure this slot is considered active for the current round
			if target_slot.current_state == TrackSlotScript.SlotState.INACTIVE: # Should be activated by activate_slots_for_round
				target_slot.activate_slot() # Activate if somehow missed
				
			target_slot.place_glyph(glyph_data)
			current_next_slot_index += 1
		else:
			printerr("TrackManager: Slot %d is invalid or missing place_glyph method." % current_next_slot_index)
	else:
		print("TrackManager: All slots full, cannot place glyph.")

func clear_track_for_new_round(): # Called by HUD
	for slot_node in track_slots:
		if is_instance_valid(slot_node) and slot_node.has_method("clear_glyph"): # Also deactivates
			slot_node.clear_glyph() # This will set it to an appropriate EMPTY or CORNERSTONE_EMPTY state
			if slot_node.has_method("deactivate_slot"): # Then fully deactivate for non-active slots
				slot_node.deactivate_slot() # This ensures they go to INACTIVE if not part of next round
	current_next_slot_index = 0

func get_global_position_of_slot(slot_index: int) -> Vector2:
	if slot_index >= 0 and slot_index < track_slots.size():
		var slot_node = track_slots[slot_index]
		if slot_node is Control:
			return (slot_node as Control).global_position + (slot_node as Control).size / 2.0 # Center
	printerr("TrackManager: Invalid slot_index %d for get_global_position_of_slot." % slot_index)
	return get_viewport_rect().size / 2.0 # Fallback

func get_global_position_of_next_slot() -> Vector2:
	return get_global_position_of_slot(current_next_slot_index)

# --- Cornerstone related (Phase B) ---
func mark_cornerstone_slots(): # Call this once after _setup_track perhaps
	# Placeholder: Slot 3 (index 2), Slot 8 (index 7), Slot 13 (index 12), Slot 15 (index 14)
	var cornerstone_indices = [2, 7, 12, 14] 
	for i in range(track_slots.size()):
		var slot_node = track_slots[i]
		if is_instance_valid(slot_node) and slot_node.has_method("set_as_cornerstone"): # New method in TrackSlot.gd
			if i in cornerstone_indices:
				slot_node.set_as_cornerstone(true, "cs_effect_" + str(i)) # Example effect ID
			else:
				slot_node.set_as_cornerstone(false)


func update_specific_cornerstone_visual(slot_index: int, is_logic_active: bool):
	if slot_index >= 0 and slot_index < track_slots.size():
		var slot_node = track_slots[slot_index]
		if is_instance_valid(slot_node) and slot_node.has_method("update_cornerstone_visual"): # Using existing placeholder
			# For now, TrackSlot.update_cornerstone_visual just takes one bool
			# We'll refine this in Phase B to use the full SlotState enum
			slot_node.update_cornerstone_visual(is_logic_active)
		else:
			printerr("TrackManager: Slot %d cannot update cornerstone visual." % slot_index)

func update_specific_cornerstone_logic_unlocked(slot_index_zero_based: int, is_unlocked: bool): # Called by HUD via Game.gd
	if slot_index_zero_based >= 0 and slot_index_zero_based < track_slots.size():
		var slot_node = track_slots[slot_index_zero_based]
		if is_instance_valid(slot_node) and slot_node.has_method("unlock_cornerstone_logic"):
			slot_node.unlock_cornerstone_logic(is_unlocked)
		else:
			printerr("TrackManager: Slot %d cannot update cornerstone logic (unlock_cornerstone_logic method missing or invalid slot)." % slot_index_zero_based)
