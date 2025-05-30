# res://scripts/ui/TrackManager.gd
# TABS FOR INDENTATION
extends Control

const NUM_SLOTS: int = 15
var track_slots: Array[Node] = [] 
var track_slot_scene: PackedScene = preload("res://scenes/ui/TrackSlot.tscn")
const TrackSlotScript: Script = preload("res://scenes/ui/TrackSlot.gd")

var slot_local_positions: Array[Vector2] = [
	Vector2(240, 480), # Slot 0 (Index 0) -> Matrix [6,3]
	Vector2(160, 480), # Slot 1 (Index 1) -> Matrix [6,2]
	Vector2(80, 480),  # Slot 2 (Index 2) -> Matrix [6,1]
	Vector2(80, 400),  # Slot 3 (Index 3) -> Matrix [5,1]
	Vector2(80, 320),  # Slot 4 (Index 4) -> Matrix [4,1]
	Vector2(80, 240),  # Slot 5 (Index 5) -> Matrix [3,1]
	Vector2(80, 160),  # Slot 6 (Index 6) -> Matrix [2,1]
	Vector2(80, 80),   # Slot 7 (Index 7) -> Matrix [1,1]
	Vector2(160, 80),  # Slot 8 (Index 8) -> Matrix [1,2]
	Vector2(240, 80),  # Slot 9 (Index 9) -> Matrix [1,3]
	Vector2(320, 80),  # Slot 10 (Index 10) -> Matrix [1,4]
	Vector2(400, 80),  # Slot 11 (Index 11) -> Matrix [1,5]
	Vector2(480, 80),  # Slot 12 (Index 12) -> Matrix [1,6]
	Vector2(480, 160), # Slot 13 (Index 13) -> Matrix [2,6]
	Vector2(480, 240)  # Slot 14 (Index 14) -> Matrix [3,6]
]
var current_next_slot_index: int = 0

var cornerstone_slot_indices: Dictionary = {
	2: "cornerstone_slot_3_bonus",
}

func _ready():
	if not is_instance_valid(track_slot_scene):
		printerr("TrackManager: TrackSlot.tscn not loaded!"); return
	_setup_track_slots_and_cornerstones()

func _setup_track_slots_and_cornerstones():
	print("TrackManager: _setup_track_slots_and_cornerstones() START")
	for child in get_children(): child.queue_free()
	track_slots.clear()

	# First verify we can instantiate a single slot
	var test_slot = track_slot_scene.instantiate()
	if not is_instance_valid(test_slot):
		printerr("TrackManager: CRITICAL - Cannot instantiate TrackSlot scene!")
		return
	test_slot.queue_free()
	
	print("TrackManager: Test slot instantiation successful, proceeding with setup.")

	for i in range(NUM_SLOTS):
		print("TrackManager: Creating slot %d..." % i)
		var slot_instance = track_slot_scene.instantiate()
		if not is_instance_valid(slot_instance):
			printerr("TrackManager: CRITICAL - Failed to instantiate slot %d!" % i)
			continue
			
		if not (slot_instance is Control):
			printerr("TrackManager: CRITICAL - Slot %d is not a Control node!" % i)
			slot_instance.queue_free()
			continue

		add_child(slot_instance)
		
		# Set position with error checking
		if i < slot_local_positions.size():
			var pos = slot_local_positions[i]
			print("TrackManager: Setting predefined position for slot %d: %s" % [i, str(pos)])
			(slot_instance as Control).position = pos
		else:
			printerr("TrackManager: No predefined position for slot %d, using fallback position." % i)
			(slot_instance as Control).position = Vector2(i * 60, 0)
		
		# Initialize with error checking
		var is_cs = i in cornerstone_slot_indices
		var cs_id_val = cornerstone_slot_indices.get(i, "")
		
		print("TrackManager: Initializing slot %d (is_cornerstone: %s)..." % [i, str(is_cs)])
		if not slot_instance.has_method("initialize"):
			printerr("TrackManager: CRITICAL - Slot %d missing initialize method!" % i)
			continue
			
		slot_instance.initialize(i, is_cs, cs_id_val)
		track_slots.append(slot_instance)
		print("TrackManager: Slot %d created and initialized successfully." % i)

	print("TrackManager: Setup complete with %d slots." % track_slots.size())
	current_next_slot_index = 0
	print("TrackManager: _setup_track_slots_and_cornerstones() END")

func activate_slots_for_round(num_active_slots: int):
	for i in range(NUM_SLOTS):
		if i < track_slots.size(): # Boundary check
			var slot_node = track_slots[i]
			if is_instance_valid(slot_node) and slot_node.has_method("activate_slot") and slot_node.has_method("deactivate_slot"):
				if i < num_active_slots:
					slot_node.activate_slot()
				else:
					slot_node.deactivate_slot()
		else:
			printerr("TrackManager: activate_slots_for_round - index %d out of bounds for track_slots (size %d)" % [i, track_slots.size()])
	current_next_slot_index = 0

func place_glyph_on_next_available_slot(glyph_data: GlyphData):
	print("TrackManager: Attempting to place glyph '%s'. current_next_slot_index: %d" % [glyph_data.display_name if is_instance_valid(glyph_data) else "INVALID_GLYPH_DATA", current_next_slot_index])

	if not is_instance_valid(glyph_data):
		printerr("TrackManager: Received invalid glyph_data to place.")
		return

	if current_next_slot_index >= 0 and current_next_slot_index < track_slots.size():
		var target_slot = track_slots[current_next_slot_index]
		
		print("TrackManager: Target slot for index %d is: %s. Is valid: %s. Has place_glyph: %s" % [
			current_next_slot_index, 
			target_slot.name if is_instance_valid(target_slot) else "NULL_SLOT_INSTANCE",
			is_instance_valid(target_slot),
			target_slot.has_method("place_glyph") if is_instance_valid(target_slot) else "N/A"
		])

		if is_instance_valid(target_slot) and target_slot.has_method("place_glyph"):
			# Ensure this slot is considered active for the current round
			# This check might be redundant if activate_slots_for_round works perfectly, but good for safety.
			if target_slot.current_state == TrackSlotScript.SlotState.INACTIVE:
				print("TrackManager: Target slot %d was INACTIVE, activating it before placing glyph." % current_next_slot_index)
				target_slot.activate_slot()
				
			target_slot.place_glyph(glyph_data)
			current_next_slot_index += 1
		else:
			printerr("TrackManager: Slot %d (instance: %s) is invalid or missing place_glyph method." % [current_next_slot_index, str(target_slot)])
	else:
		printerr("TrackManager: current_next_slot_index (%d) is out of bounds for track_slots (size %d). Cannot place glyph." % [current_next_slot_index, track_slots.size()])


func clear_track_for_new_round():
	for slot_node in track_slots:
		if is_instance_valid(slot_node): # Check validity before calling methods
			if slot_node.has_method("clear_glyph"):
				slot_node.clear_glyph()
			if slot_node.has_method("deactivate_slot"):
				slot_node.deactivate_slot()
	current_next_slot_index = 0

func get_global_position_of_slot(slot_index: int) -> Vector2:
	if slot_index >= 0 and slot_index < track_slots.size():
		var slot_node = track_slots[slot_index]
		if slot_node is Control:
			return (slot_node as Control).global_position + ((slot_node as Control).size / 2.0)
	printerr("TrackManager: Invalid slot_index %d for get_global_position_of_slot." % slot_index)
	return get_viewport_rect().size / 2.0

func get_global_position_of_next_slot() -> Vector2:
	return get_global_position_of_slot(current_next_slot_index)

func mark_cornerstone_slots():
	# This was already handled by initialize in _setup_track_slots_and_cornerstones
	pass

func update_specific_cornerstone_visual(slot_index: int, is_logic_active: bool):
	# This method seems deprecated by unlock_cornerstone_logic, but keeping for now if used elsewhere
	if slot_index >= 0 and slot_index < track_slots.size():
		var slot_node = track_slots[slot_index]
		if is_instance_valid(slot_node) and slot_node.has_method("unlock_cornerstone_logic"): # Assuming this is the intended method
			slot_node.unlock_cornerstone_logic(is_logic_active)
		elif is_instance_valid(slot_node) and slot_node.has_method("update_cornerstone_visual"): # Fallback to old method name
			slot_node.update_cornerstone_visual(is_logic_active)
		else:
			printerr("TrackManager: Slot %d cannot update cornerstone visual/logic." % slot_index)

func update_specific_cornerstone_logic_unlocked(slot_index_zero_based: int, is_unlocked: bool):
	if slot_index_zero_based >= 0 and slot_index_zero_based < track_slots.size():
		var slot_node = track_slots[slot_index_zero_based]
		if is_instance_valid(slot_node) and slot_node.has_method("unlock_cornerstone_logic"):
			slot_node.unlock_cornerstone_logic(is_unlocked)
		else:
			printerr("TrackManager: Slot %d cannot update cornerstone logic (unlock_cornerstone_logic method missing or invalid slot)." % slot_index_zero_based)

func get_track_slot_by_index(index: int) -> Node: # Return type Node for flexibility, cast to TrackSlot later
	if index >= 0 and index < track_slots.size():
		return track_slots[index]
	printerr("TrackManager: get_track_slot_by_index - Index %d out of bounds." % index)
	return null

func get_track_slots_array() -> Array[Node]: # New getter
	return track_slots


# You might also need a way to find a slot by the GlyphData it contains if the index isn't readily available
# func get_track_slot_by_glyph_id(glyph_id: String) -> Node:
# 	for slot_node in track_slots:
# 		if is_instance_valid(slot_node) and slot_node.has_method("get_occupied_glyph_data"):
# 			var occupied_glyph = slot_node.get_occupied_glyph_data() # Assumes TrackSlot has this getter
# 			if is_instance_valid(occupied_glyph) and occupied_glyph.id == glyph_id:
# 				return slot_node
# 	return null
