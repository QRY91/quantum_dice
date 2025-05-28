# res://scenes/ui/TrackSlot.gd
# TABS FOR INDENTATION
extends Control

signal slot_clicked(slot_index: int)
signal glyph_landed_on_slot(slot_index: int, glyph_data: GlyphData)

# --- Configuration ---
var slot_index: int = -1

# --- State Properties (from spec) ---
enum SlotState { 
	INACTIVE,
	EMPTY,
	OCCUPIED,
	CORNERSTONE_INACTIVE,
	CORNERSTONE_ACTIVE_EMPTY,
	CORNERSTONE_ACTIVE_OCCUPIED
}
var current_state: SlotState = SlotState.INACTIVE

var occupied_glyph_data: GlyphData = null

# --- Cornerstone Properties (from spec) ---
var is_cornerstone: bool = false
var cornerstone_effect_id: StringName = ""
var is_cornerstone_logic_unlocked: bool = false

# --- Visual Node References ---
@onready var glyph_display: TextureRect = $GlyphDisplay
@onready var slot_background: TextureRect = $SlotBackground

func _set_current_state(new_state: SlotState):
	if slot_index == 2:
		print("TrackSlot[2] (Path: %s): _set_current_state ENTERED. current_state: %s, new_state: %s" % [get_path(), SlotState.keys()[current_state] if current_state != null else "NULL", SlotState.keys()[new_state]])

	var old_state_enum_val = current_state # For logging comparison
	current_state = new_state # Assign the new state

	if slot_index == 2:
		if old_state_enum_val == new_state:
			print("TrackSlot[2] (Path: %s): _set_current_state - state enum value (%s) did not change, but proceeding to _update_visuals." % [get_path(), SlotState.keys()[current_state]])
		else:
			print("TrackSlot[2] (Path: %s): _set_current_state - state changed from %s to %s. Calling _update_visuals." % [get_path(), SlotState.keys()[old_state_enum_val] if old_state_enum_val != null else "NULL", SlotState.keys()[current_state]])
	
	_update_visuals() # Always update visuals

func _ready():
	# slot_index is typically -1 here as initialize() is called by TrackManager after _ready()
	print("TrackSlot _ready: Name: %s, Path: %s, current slot_idx_var: %d" % [name, get_path(), slot_index])
	_set_current_state(SlotState.INACTIVE) # Set initial state


func initialize(p_index: int, p_is_cornerstone: bool = false, p_cs_effect_id: StringName = ""):
	slot_index = p_index
	is_cornerstone = p_is_cornerstone
	cornerstone_effect_id = p_cs_effect_id
	is_cornerstone_logic_unlocked = false
	print("TrackSlot INITIALIZE: Name: %s, Path: %s, slot_idx_set_to: %d, is_cs: %s" % [name, get_path(), slot_index, str(p_is_cornerstone)])
	# _set_current_state(SlotState.INACTIVE) # State is already INACTIVE from _ready, will be updated by activate_slot or set_as_cornerstone
	# Let's ensure visuals are updated after initialization, especially if it's a cornerstone
	if is_cornerstone:
		_set_current_state(SlotState.CORNERSTONE_INACTIVE) # Default for a cornerstone before logic unlock/activation
	else:
		_set_current_state(SlotState.INACTIVE) # Default for non-cornerstone, will be EMPTY upon activation


func set_as_cornerstone(cs_flag: bool, cs_id: StringName = ""): # Called by TrackManager during its setup
	# This might be called before activate_slot
	# print("TrackSlot[%d Path: %s]: set_as_cornerstone called. cs_flag: %s" % [slot_index, get_path(), str(cs_flag)])
	is_cornerstone = cs_flag
	cornerstone_effect_id = cs_id
	
	# Update state based on being set as cornerstone, assuming it's not yet "active" for the round
	if is_cornerstone:
		if is_cornerstone_logic_unlocked: # Should be false at this stage normally
			_set_current_state(SlotState.CORNERSTONE_ACTIVE_EMPTY if not occupied_glyph_data else SlotState.CORNERSTONE_ACTIVE_OCCUPIED)
		else:
			_set_current_state(SlotState.CORNERSTONE_INACTIVE)
	else: # No longer a cornerstone
		if occupied_glyph_data:
			_set_current_state(SlotState.OCCUPIED)
		elif current_state != SlotState.INACTIVE : # If it was some form of active/empty cornerstone
			_set_current_state(SlotState.EMPTY) 
		# else it remains INACTIVE if it was already so
	# _update_visuals() is called by _set_current_state

func activate_slot(): # Called by TrackManager when round starts/slots become available
	# print("TrackSlot[%d Path: %s]: activate_slot called." % [slot_index, get_path()])
	if is_cornerstone:
		if is_cornerstone_logic_unlocked:
			_set_current_state(SlotState.CORNERSTONE_ACTIVE_EMPTY)
		else:
			# It's a cornerstone, but its special logic isn't unlocked.
			# It should behave like an EMPTY slot visually for now, but its background might differ.
			# The CORNERSTONE_INACTIVE state is for this.
			_set_current_state(SlotState.CORNERSTONE_INACTIVE) # It's "active" for the round but CS logic is off
	else:
		_set_current_state(SlotState.EMPTY)
	# _update_visuals() is called by _set_current_state

func deactivate_slot(): # Called by TrackManager when round ends
	# print("TrackSlot[%d Path: %s]: deactivate_slot called." % [slot_index, get_path()])
	# Clear glyph first, which might change state to an "empty" variant
	if occupied_glyph_data:
		clear_glyph() 
	# Then explicitly set to INACTIVE
	_set_current_state(SlotState.INACTIVE)


func unlock_cornerstone_logic(unlocked: bool): # Called by TrackManager via Game.gd
	# print("TrackSlot[%d Path: %s]: unlock_cornerstone_logic called. Unlocked: %s" % [slot_index, get_path(), str(unlocked)])
	if not is_cornerstone: return
	
	var old_unlocked_state = is_cornerstone_logic_unlocked
	is_cornerstone_logic_unlocked = unlocked

	if old_unlocked_state == is_cornerstone_logic_unlocked: return

	# Re-evaluate current state based on new lock status and whether it's occupied
	if is_cornerstone_logic_unlocked:
		if occupied_glyph_data:
			_set_current_state(SlotState.CORNERSTONE_ACTIVE_OCCUPIED)
		else: # No glyph
			_set_current_state(SlotState.CORNERSTONE_ACTIVE_EMPTY)
	else: # Logic is being locked
		# If occupied, it remains CORNERSTONE_INACTIVE (but occupied). If empty, also CORNERSTONE_INACTIVE (and empty).
		_set_current_state(SlotState.CORNERSTONE_INACTIVE)
	# _update_visuals() is called by _set_current_state


func place_glyph(glyph: GlyphData):
	print("TrackSlot (Path: %s, Name: %s, slot_idx_var: %d): place_glyph METHOD ENTERED. Glyph: '%s'" % [
		get_path(), 
		name, 
		slot_index, 
		glyph.display_name if is_instance_valid(glyph) else "INVALID_GLYPH_ARG"
	])

	if not is_instance_valid(glyph):
		printerr("TrackSlot[%d Path: %s]: place_glyph called with invalid GlyphData." % [slot_index, get_path()])
		occupied_glyph_data = null
		if is_instance_valid(glyph_display):
			glyph_display.texture = null
		if is_cornerstone:
			_set_current_state(SlotState.CORNERSTONE_ACTIVE_EMPTY if is_cornerstone_logic_unlocked else SlotState.CORNERSTONE_INACTIVE)
		else:
			_set_current_state(SlotState.EMPTY)
		return

	occupied_glyph_data = glyph
	
	var new_state: SlotState
	if is_cornerstone:
		if is_cornerstone_logic_unlocked:
			new_state = SlotState.CORNERSTONE_ACTIVE_OCCUPIED
		else:
			new_state = SlotState.CORNERSTONE_INACTIVE
	else:
		new_state = SlotState.OCCUPIED
	
	if slot_index == 2:
		print("TrackSlot[2] (Path: %s): In place_glyph, before setting texture. Glyph: %s, Texture valid: %s" % [get_path(), occupied_glyph_data.display_name, is_instance_valid(occupied_glyph_data.texture)])

	if is_instance_valid(glyph_display):
		if is_instance_valid(occupied_glyph_data.texture):
			glyph_display.texture = occupied_glyph_data.texture
		else:
			glyph_display.texture = null
			# This printerr is fine as is.
			if slot_index == 2: 
				printerr("TrackSlot[2] (Path: %s): In place_glyph, SETTING TEXTURE TO NULL because glyph.texture is invalid. Glyph: '%s'" % [get_path(), occupied_glyph_data.display_name])
	
	if slot_index == 2:
		print("TrackSlot[2] (Path: %s): In place_glyph, after setting texture. New state to set: %s" % [get_path(), SlotState.keys()[new_state]])

	_set_current_state(new_state) 
	
	if slot_index == 2:
		print("TrackSlot[2] (Path: %s): In place_glyph, AFTER calling _set_current_state. Emitting signal." % get_path())

	emit_signal("glyph_landed_on_slot", slot_index, occupied_glyph_data)
	

func clear_glyph():
	# print("TrackSlot[%d Path: %s]: clear_glyph called." % [slot_index, get_path()])
	occupied_glyph_data = null
	if is_instance_valid(glyph_display):
		glyph_display.texture = null

	var new_empty_state: SlotState
	if current_state == SlotState.INACTIVE: # If it's already fully inactive, keep it that way
		new_empty_state = SlotState.INACTIVE
	elif is_cornerstone:
		if is_cornerstone_logic_unlocked:
			new_empty_state = SlotState.CORNERSTONE_ACTIVE_EMPTY
		else:
			new_empty_state = SlotState.CORNERSTONE_INACTIVE # Inactive cornerstone, now empty
	else: # Not a cornerstone, and was not INACTIVE
		new_empty_state = SlotState.EMPTY
		
	_set_current_state(new_empty_state)


func _update_visuals():
	if slot_index == 2:
		print("TrackSlot[2] (Path: %s): _update_visuals METHOD ENTERED. Current state: %s" % [get_path(), SlotState.keys()[current_state]])

	if not is_instance_valid(glyph_display) or not is_instance_valid(slot_background):
		printerr("TrackSlot[%d Path: %s]: _update_visuals - glyph_display or slot_background node is not valid!" % [slot_index, get_path()])
		if slot_index == 2:
			print("TrackSlot[2] (Path: %s): _update_visuals - EXITING due to invalid nodes." % get_path())
		return

	var show_glyph: bool = false
	if occupied_glyph_data != null:
		if current_state in [SlotState.OCCUPIED, SlotState.CORNERSTONE_ACTIVE_OCCUPIED, SlotState.CORNERSTONE_INACTIVE]:
			show_glyph = true
	
	if is_instance_valid(glyph_display): # Check again before using
		glyph_display.visible = show_glyph
	elif slot_index == 2:
		print("TrackSlot[2] (Path: %s): _update_visuals - glyph_display became invalid before setting visibility." % get_path())


	match current_state:
		SlotState.INACTIVE:
			slot_background.modulate = Color.DARK_GRAY * Color(1,1,1,0.5)
			if is_instance_valid(glyph_display): glyph_display.visible = false # Ensure hidden
		SlotState.EMPTY:
			slot_background.modulate = Color.GRAY
		SlotState.OCCUPIED:
			slot_background.modulate = Color.LIGHT_GRAY
		SlotState.CORNERSTONE_INACTIVE:
			slot_background.modulate = Color.PURPLE 
		SlotState.CORNERSTONE_ACTIVE_EMPTY:
			slot_background.modulate = Color.GOLD
		SlotState.CORNERSTONE_ACTIVE_OCCUPIED:
			slot_background.modulate = Color.GOLD.lightened(0.2)

	# Conditional print for slot_index 2 (IMMEDIATE Status) remains the same.
	if slot_index == 2:
		var tex_status = "null"
		# ... (tex_status logic as before) ...
		if is_instance_valid(glyph_display) and is_instance_valid(glyph_display.texture):
			tex_status = glyph_display.texture.resource_path if glyph_display.texture.resource_path else "Valid Texture Object (no path)"
		elif is_instance_valid(glyph_display):
			tex_status = "<TextureRect valid, texture field null>"
		else:
			tex_status = "<glyph_display node invalid>"
			
		print("TrackSlot[2] IMMEDIATE Status (Path: %s): Visible: %s, TextureField: %s, State: %s, GlyphData: %s" % [
			get_path(),
			glyph_display.visible if is_instance_valid(glyph_display) else "glyph_display_invalid",
			tex_status,
			SlotState.keys()[current_state],
			occupied_glyph_data.display_name if occupied_glyph_data else "None"
		])
		print("TrackSlot[2] (Path: %s): _update_visuals METHOD COMPLETED." % get_path()) # New line
		
	
