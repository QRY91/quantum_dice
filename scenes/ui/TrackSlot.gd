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
# Optional: Add an AnimationPlayer node to TrackSlot.tscn for more complex animations
# @onready var animation_player: AnimationPlayer = $AnimationPlayer

var _idle_float_tween: Tween = null
const IDLE_FLOAT_AMOUNT: float = 3.0 # Pixels to float up/down
const IDLE_FLOAT_DURATION: float = 1.5 # Seconds for one full cycle (up and down)

# Temporarily disable shader loading
# const SYNERGY_GLOW_SHADER: Shader = preload("res://shaders/synergy_glow.gdshader")
var _original_slot_background_material: Material = null
var _synergy_glow_active: bool = false

# REMOVED: var PaletteManager: Node = null

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
	
	# Stop/Start idle animation based on whether a glyph is visible
	if is_instance_valid(glyph_display) and glyph_display.visible:
		_start_idle_float_animation()
	else:
		_stop_idle_float_animation()
	
	_update_visuals() # Always update visuals

func _ready():
	print("TrackSlot _ready: Name: %s, Path: %s, current slot_idx_var: %d" % [name, get_path(), slot_index])
	_set_current_state(SlotState.INACTIVE) # Set initial state
	_stop_idle_float_animation() # Ensure it's stopped initially
	
	# Temporarily disable material handling
	# if is_instance_valid(slot_background):
	#     _original_slot_background_material = slot_background.material
	# else:
	#     printerr("TrackSlot '%s': SlotBackground node not found in _ready." % name)

	# Connect to PaletteManager for glyph color
	var palette_manager = get_node_or_null("/root/PaletteManager")
	if is_instance_valid(palette_manager):
		palette_manager.active_palette_updated.connect(_on_palette_changed_for_glyph)
		_on_palette_changed_for_glyph(palette_manager.get_current_palette_colors())
	else:
		printerr("TrackSlot '%s': PaletteManager autoload not found. Glyph color will not be dynamic." % name)

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
	
	# Ensure idle animation is stopped as glyph_display is not yet visible or populated.
	_stop_idle_float_animation()
	deactivate_synergy_visuals() # Ensure synergy visuals are off on init

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
	deactivate_synergy_visuals() # Ensure visuals are reset when slot (re)activates for a round
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
	_stop_idle_float_animation() # Explicitly stop on deactivate
	deactivate_synergy_visuals() # Deactivate synergy visuals when slot deactivates

func deactivate_slot(): # Called by TrackManager when round ends
	# print("TrackSlot[%d Path: %s]: deactivate_slot called." % [slot_index, get_path()])
	# Clear glyph first, which might change state to an "empty" variant
	if occupied_glyph_data:
		clear_glyph() 
	# Then explicitly set to INACTIVE
	_set_current_state(SlotState.INACTIVE)
	_stop_idle_float_animation() # Explicitly stop on deactivate
	deactivate_synergy_visuals() # Deactivate synergy visuals when slot deactivates


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
	
	if is_instance_valid(glyph_display) and glyph_display.visible:
		_start_idle_float_animation()
	else:
		_stop_idle_float_animation()

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
	_stop_idle_float_animation() # Stop animation when glyph is cleared


func _update_visuals():
	if slot_index == 2:
		print("TrackSlot[2] (Path: %s): _update_visuals METHOD ENTERED. Current state: %s" % [get_path(), SlotState.keys()[current_state]])

	if not is_instance_valid(glyph_display) or not is_instance_valid(slot_background):
		printerr("TrackSlot[%d Path: %s]: _update_visuals - glyph_display or slot_background node is not valid!" % [slot_index, get_path()])
		if slot_index == 2:
			print("TrackSlot[2] (Path: %s): _update_visuals - EXITING due to invalid nodes." % get_path())
		return

	# Apply current palette's main color to the glyph if visible
	var palette_manager = get_node_or_null("/root/PaletteManager")
	if is_instance_valid(palette_manager) and is_instance_valid(glyph_display):
		glyph_display.modulate = palette_manager.get_current_palette_colors().get("main", Color.WHITE)

	var show_glyph: bool = false
	if occupied_glyph_data != null:
		if current_state in [SlotState.OCCUPIED, SlotState.CORNERSTONE_ACTIVE_OCCUPIED, SlotState.CORNERSTONE_INACTIVE]:
			show_glyph = true
	
	if is_instance_valid(glyph_display): # Check again before using
		glyph_display.visible = show_glyph
		if show_glyph:
			if _idle_float_tween == null or not _idle_float_tween.is_valid(): # Start if not already running and glyph is visible
				_start_idle_float_animation()
		else:
			_stop_idle_float_animation() # Stop if glyph is not shown
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
		
	
# --- New function for entanglement visual effect ---
func play_entanglement_effect_animation():
	# Simple pulse effect using a tween on the glyph_display
	if not is_instance_valid(glyph_display):
		printerr("TrackSlot[%d]: Cannot play entanglement animation, glyph_display is invalid." % slot_index)
		return

	print("TrackSlot[%d]: Playing entanglement effect animation." % slot_index)
	
	var tween = create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS) # Ensure it plays even if game pauses briefly
	tween.set_parallel(true) # Scale and modulate can happen together

	var original_scale = glyph_display.scale
	var pulse_scale = original_scale * 1.3
	var original_modulate = glyph_display.modulate
	var pulse_modulate_color = Color.LIGHT_SKY_BLUE # Or Color.CYAN, or a custom "energy" color

	# Pulse scale
	tween.tween_property(glyph_display, "scale", pulse_scale, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(glyph_display, "scale", original_scale, 0.25).set_delay(0.15).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	
	# Pulse color (modulate)
	tween.tween_property(glyph_display, "modulate", pulse_modulate_color, 0.1).set_trans(Tween.TRANS_LINEAR)
	tween.tween_property(glyph_display, "modulate", original_modulate, 0.3).set_delay(0.1).set_trans(Tween.TRANS_LINEAR)

	# If using AnimationPlayer:
	# if is_instance_valid(animation_player) and animation_player.has_animation("entangled_pulse"):
	# 	animation_player.play("entangled_pulse")
	# else:
	# 	# Fallback to tween or print error
	# 	printerr("TrackSlot[%d]: Entanglement AnimationPlayer or 'entangled_pulse' animation not found." % slot_index)

# --- Idle Float Animation ---
func _start_idle_float_animation():
	if not is_instance_valid(glyph_display) or not glyph_display.visible:
		_stop_idle_float_animation() # Ensure it's stopped if glyph isn't visible
		return

	if _idle_float_tween != null and _idle_float_tween.is_valid():
		# Already running or being set up, no need to restart unless properties change
		# If you want to ensure it restarts from base position, kill and recreate:
		# _idle_float_tween.kill() 
		# _idle_float_tween = null
		return

	_idle_float_tween = create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	
	# Ensure glyph_display is at its base position before starting
	glyph_display.position.y = 0 
	
	var half_duration = IDLE_FLOAT_DURATION / 2.0
	_idle_float_tween.tween_property(glyph_display, "position:y", -IDLE_FLOAT_AMOUNT, half_duration)
	_idle_float_tween.tween_property(glyph_display, "position:y", IDLE_FLOAT_AMOUNT, half_duration)
	_idle_float_tween.tween_property(glyph_display, "position:y", 0.0, half_duration) # Back to center

func _stop_idle_float_animation():
	if _idle_float_tween != null and _idle_float_tween.is_valid():
		_idle_float_tween.kill() # Stop the tween
	_idle_float_tween = null
	if is_instance_valid(glyph_display): # Reset position when stopping
		glyph_display.position = Vector2.ZERO


func _exit_tree():
	_stop_idle_float_animation() # Clean up tween when node exits tree
	# Disconnect from PaletteManager
	var palette_manager = get_node_or_null("/root/PaletteManager")
	if is_instance_valid(palette_manager) and palette_manager.is_connected("active_palette_updated", Callable(self, "_on_palette_changed_for_glyph")):
		palette_manager.active_palette_updated.disconnect(_on_palette_changed_for_glyph)

# --- Synergy Visuals ---
func activate_synergy_visuals(glow_color: Color = Color(1.0, 0.8, 0.0, 0.7), strength: float = 0.6, speed: float = 1.5):
	if not is_instance_valid(slot_background):
		printerr("TrackSlot '%s': Cannot activate synergy visuals. SlotBackground missing." % name)
		return
	
	print("TrackSlot '%s': Activating synergy visuals (simplified)." % name)
	# Temporarily just change the modulate color for synergy effect
	slot_background.modulate = glow_color
	_synergy_glow_active = true

func deactivate_synergy_visuals():
	if is_instance_valid(slot_background):
		slot_background.material = _original_slot_background_material
		# Reset modulate to default
		slot_background.modulate = Color(0.580392, 0.580392, 0.580392, 1)
	_synergy_glow_active = false

func is_synergy_glow_active() -> bool:
	return _synergy_glow_active

# --- Palette Change Handler for Glyph ---
func _on_palette_changed_for_glyph(palette_colors: Dictionary) -> void:
	if not is_instance_valid(glyph_display):
		return

	var main_color = palette_colors.get("main", Color.WHITE) # Default to white
	glyph_display.modulate = main_color
	# print("TrackSlot '%s': Updated glyph modulate color to: %s" % [name, main_color])
