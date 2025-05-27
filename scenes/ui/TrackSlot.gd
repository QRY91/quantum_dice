# res://scenes/ui_elements/TrackSlot.gd
# TABS FOR INDENTATION
extends Control

signal slot_clicked(slot_index: int)
signal glyph_landed_on_slot(slot_index: int, glyph_data: GlyphData)
# signal synergy_component_activated(slot_index: int) # For later

# --- Configuration ---
var slot_index: int = -1

# --- State Properties (from spec) ---
enum SlotState { 
	INACTIVE,                 # Not part of the current round's usable track
	EMPTY,                    # Active and usable, but no glyph
	OCCUPIED,                 # Active with a glyph
	CORNERSTONE_INACTIVE,     # Is a cornerstone, but its special logic is not yet unlocked/active
	CORNERSTONE_ACTIVE_EMPTY, # Cornerstone, logic unlocked, no glyph
	CORNERSTONE_ACTIVE_OCCUPIED # Cornerstone, logic unlocked, with a glyph
}
var current_state: SlotState = SlotState.INACTIVE

var occupied_glyph_data: GlyphData = null

# --- Cornerstone Properties (from spec) ---
var is_cornerstone: bool = false
var cornerstone_effect_id: StringName = "" # e.g., "slot_3_bonus_score"
var is_cornerstone_logic_unlocked: bool = false # Has the player unlocked this cornerstone's special rule?

# --- Visual Node References ---
@onready var glyph_display: TextureRect = $GlyphDisplay
@onready var slot_background: TextureRect = $SlotBackground
# @onready var effect_overlay: TextureRect = $EffectOverlay # For later
# @onready var animation_player: AnimationPlayer = $AnimationPlayer # For later

func _set_current_state(new_state: SlotState):
	if current_state == new_state:
		return
	# print("TrackSlot %d: State changing from %s to %s" % [slot_index, SlotState.keys()[current_state] if current_state != null else "NULL", SlotState.keys()[new_state]])
	current_state = new_state
	_update_visuals()

func _ready():
	_set_current_state(SlotState.INACTIVE) # Initial default

func initialize(p_index: int, p_is_cornerstone: bool = false, p_cs_effect_id: StringName = ""):
	slot_index = p_index
	is_cornerstone = p_is_cornerstone
	cornerstone_effect_id = p_cs_effect_id
	is_cornerstone_logic_unlocked = false # Starts locked
	
	# Initial state is INACTIVE, Game/TrackManager will activate it
	_set_current_state(SlotState.INACTIVE)


func set_as_cornerstone(cs_flag: bool, cs_id: StringName = ""): # Called by TrackManager
	is_cornerstone = cs_flag
	cornerstone_effect_id = cs_id
	if is_cornerstone and current_state == SlotState.EMPTY: # If it was already an active empty slot
		_set_current_state(SlotState.CORNERSTONE_INACTIVE)
	elif is_cornerstone and current_state == SlotState.OCCUPIED:
		_set_current_state(SlotState.CORNERSTONE_INACTIVE) # Needs logic to become OCCUPIED CORNERSTONE
	elif not is_cornerstone and (current_state == SlotState.CORNERSTONE_INACTIVE or current_state == SlotState.CORNERSTONE_ACTIVE_EMPTY or current_state == SlotState.CORNERSTONE_ACTIVE_OCCUPIED) :
		_set_current_state(SlotState.EMPTY if not occupied_glyph_data else SlotState.OCCUPIED) # Revert to normal
	_update_visuals()


func activate_slot(): # Called by TrackManager when round starts/slots become available
	if is_cornerstone:
		if is_cornerstone_logic_unlocked:
			_set_current_state(SlotState.CORNERSTONE_ACTIVE_EMPTY)
		else:
			_set_current_state(SlotState.CORNERSTONE_INACTIVE) # Acts like normal slot but looks like inactive CS
	else:
		_set_current_state(SlotState.EMPTY)

func deactivate_slot(): # Called by TrackManager when round ends
	_set_current_state(SlotState.INACTIVE)
	clear_glyph() # Ensure glyph is cleared

func unlock_cornerstone_logic(unlocked: bool): # Called by TrackManager via Game.gd
	if not is_cornerstone: return
	is_cornerstone_logic_unlocked = unlocked
	# Update state based on new unlocked status
	if is_cornerstone_logic_unlocked:
		if current_state == SlotState.CORNERSTONE_INACTIVE or current_state == SlotState.EMPTY: # Or was just a normal slot
			_set_current_state(SlotState.CORNERSTONE_ACTIVE_EMPTY if not occupied_glyph_data else SlotState.CORNERSTONE_ACTIVE_OCCUPIED)
	else: # Logic is being locked (if that's a game mechanic)
		if current_state == SlotState.CORNERSTONE_ACTIVE_EMPTY or current_state == SlotState.CORNERSTONE_ACTIVE_OCCUPIED:
			_set_current_state(SlotState.CORNERSTONE_INACTIVE)
	_update_visuals()


func place_glyph(glyph: GlyphData):
	occupied_glyph_data = glyph
	if is_cornerstone:
		_set_current_state(SlotState.CORNERSTONE_ACTIVE_OCCUPIED if is_cornerstone_logic_unlocked else SlotState.CORNERSTONE_INACTIVE) # If CS inactive, it still gets occupied
	else:
		_set_current_state(SlotState.OCCUPIED)
	
	if is_instance_valid(glyph_display) and is_instance_valid(occupied_glyph_data):
		if is_instance_valid(occupied_glyph_data.texture):
			glyph_display.texture = occupied_glyph_data.texture
		else:
			glyph_display.texture = null
	
	emit_signal("glyph_landed_on_slot", slot_index, occupied_glyph_data)
	# process_on_land_effects() # For later

func clear_glyph():
	occupied_glyph_data = null
	# State will be set by activate_slot or if it's a cornerstone
	if is_cornerstone:
		_set_current_state(SlotState.CORNERSTONE_ACTIVE_EMPTY if is_cornerstone_logic_unlocked else SlotState.CORNERSTONE_INACTIVE)
	elif current_state != SlotState.INACTIVE : # Only revert to EMPTY if it's not fully INACTIVE
		_set_current_state(SlotState.EMPTY)

	if is_instance_valid(glyph_display):
		glyph_display.texture = null

func _update_visuals():
	if not is_instance_valid(glyph_display) or not is_instance_valid(slot_background):
		return

	glyph_display.visible = (current_state == SlotState.OCCUPIED or \
							 current_state == SlotState.CORNERSTONE_ACTIVE_OCCUPIED or \
							 (current_state == SlotState.CORNERSTONE_INACTIVE and occupied_glyph_data != null) ) # Show glyph if CS inactive but occupied

	match current_state:
		SlotState.INACTIVE:
			slot_background.modulate = Color.DARK_GRAY * Color(1,1,1,0.5) # More dim
			glyph_display.visible = false # Ensure no glyph shows
		SlotState.EMPTY:
			slot_background.modulate = Color.GRAY
		SlotState.OCCUPIED:
			slot_background.modulate = Color.LIGHT_GRAY
		SlotState.CORNERSTONE_INACTIVE:
			slot_background.modulate = Color.PURPLE # Distinct color for CS not yet active
		SlotState.CORNERSTONE_ACTIVE_EMPTY:
			slot_background.modulate = Color.GOLD # Glowing/active empty CS
		SlotState.CORNERSTONE_ACTIVE_OCCUPIED:
			slot_background.modulate = Color.GOLD.lightened(0.2) # Slightly different if occupied
