# res://scripts/ui/HUD.gd
# TABS FOR INDENTATION
extends Control

signal inventory_toggled(is_inventory_visible: bool)
signal fanfare_animation_finished
signal game_menu_button_pressed # New signal for the game menu button

# Constants for node paths (can be adjusted if your scene structure changes)
# Score fanfare is now handled directly in HUD, no separate node needed
# ... other const paths
const HISTORY_TRACK_PATH = "%HistoryTrackContainer"
const DICE_FACE_SCROLL_CONTAINER_PATH = "%DiceFaceScrollContainer"
const DICE_FACE_VBOX_PATH = "%DiceFaceScrollContainer/VBoxContainer"
const DICE_FACE_GRID_PATH = "%DiceFaceScrollContainer/DiceDisplayGrid"
const INVENTORY_TOGGLE_BUTTON_PATH = "%InventoryToggleButton"

const LEVEL_DISPLAY_PATH = "%LevelLabel"
const ROLLS_DISPLAY_PATH = "%RollsLabel"
const SCORE_TARGET_DISPLAY_PATH = "%ScoreLabel"

const CORNERSTONE_SLOT_1_PATH = "%CornerstoneSlot1"
const CORNERSTONE_SLOT_2_PATH = "%CornerstoneSlot2"
const CORNERSTONE_SLOT_3_PATH = "%CornerstoneSlot3"
const CORNERSTONE_GLYPH_1_PATH = "%CornerstoneSlot1/CornerstoneGlyph1"
const CORNERSTONE_GLYPH_2_PATH = "%CornerstoneSlot2/CornerstoneGlyph2"
const CORNERSTONE_GLYPH_3_PATH = "%CornerstoneSlot3/CornerstoneGlyph3"

const BOSS_INDICATOR_PANEL_PATH = "%BossIndicatorPanel"
const BOSS_INDICATOR_LABEL_PATH = "%BossIndicatorPanel/BossIndicatorLabel"

const GAME_MENU_BUTTON_PATH = "%GameMenuButton" # Path for the new button
const SYNERGY_NOTIFICATION_LABEL_PATH = "%SynergyNotificationLabel" # Path for SynergyNotificationLabel
const TRACK_MANAGER_PATH = "%LogicTrackDisplay" # Path for TrackManager (LogicTrackDisplay)

# Configuration
@export var MAX_HISTORY_SLOTS = 5
@export var GLYPH_HISTORY_SIZE = Vector2(80, 80)
@export var GLYPH_INVENTORY_SIZE = Vector2(64, 64)
@export var GLYPH_INVENTORY_GRID_ITEM_SIZE = Vector2(40,40)
@export var GLYPH_INVENTORY_GRID_COLUMNS = 7
@export var RUNESLOT_OVERLAY_TEXTURE: Texture2D

# Node references
@onready var history_track_container: HBoxContainer = get_node_or_null(HISTORY_TRACK_PATH)
@onready var dice_face_scroll_container: ScrollContainer = get_node_or_null(DICE_FACE_SCROLL_CONTAINER_PATH)
@onready var dice_face_vbox: VBoxContainer = get_node_or_null(DICE_FACE_VBOX_PATH)
@onready var dice_face_grid: GridContainer = get_node_or_null(DICE_FACE_GRID_PATH)
@onready var inventory_toggle_button: TextureButton = get_node_or_null(INVENTORY_TOGGLE_BUTTON_PATH)

@onready var level_display_label: Label = get_node_or_null(LEVEL_DISPLAY_PATH)
@onready var rolls_display_label: Label = get_node_or_null(ROLLS_DISPLAY_PATH)
@onready var score_target_display_label: Label = get_node_or_null(SCORE_TARGET_DISPLAY_PATH)

@onready var cornerstone_slots: Array[Panel] = [
	get_node_or_null(CORNERSTONE_SLOT_1_PATH),
	get_node_or_null(CORNERSTONE_SLOT_2_PATH),
	get_node_or_null(CORNERSTONE_SLOT_3_PATH)
]
@onready var cornerstone_glyphs: Array[TextureRect] = [
	get_node_or_null(CORNERSTONE_GLYPH_1_PATH),
	get_node_or_null(CORNERSTONE_GLYPH_2_PATH),
	get_node_or_null(CORNERSTONE_GLYPH_3_PATH)
]

@onready var boss_indicator_panel: PanelContainer = get_node_or_null(BOSS_INDICATOR_PANEL_PATH)
@onready var boss_indicator_label: Label = get_node_or_null(BOSS_INDICATOR_LABEL_PATH)

@onready var game_menu_button: TextureButton = get_node_or_null(GAME_MENU_BUTTON_PATH)
@onready var synergy_notification_label: Label = get_node_or_null(SYNERGY_NOTIFICATION_LABEL_PATH)
@onready var track_manager: Control = get_node_or_null(TRACK_MANAGER_PATH)

var history_slots_nodes: Array[TextureRect] = []

var fanfare_check_timer: Timer = null 
var _fanfare_active_tweens: int = 0

var current_target_score: int = 0 # Add a variable to store the current target

# No longer @onready, directly use the autoload name
# @onready var palette_manager = get_node_or_null("/root/PaletteManager")
# We will use PaletteManager directly where needed.

const SCORE_POPUP_DURATION: float = 1.2
const SCORE_POPUP_TRAVEL_Y: float = -70.0

func _ready():
	print("HUD _ready: Start.")
	if not is_instance_valid(dice_face_scroll_container):
		printerr("HUD _ready: DiceFaceScrollContainer NOT FOUND.")
	if not is_instance_valid(dice_face_grid):
		printerr("HUD _ready: DiceDisplayGrid NOT FOUND at path: " + DICE_FACE_GRID_PATH)
	else:
		dice_face_grid.columns = GLYPH_INVENTORY_GRID_COLUMNS
	
	if not is_instance_valid(history_track_container):
		printerr("HUD _ready: HistoryTrackContainer node NOT FOUND!")
	else:
		print("HUD _ready: HistoryTrackContainer node found.")
		
	if not is_instance_valid(synergy_notification_label):
		printerr("HUD: SynergyNotificationLabel node not found at path: ", SYNERGY_NOTIFICATION_LABEL_PATH)
	else:
		print("HUD: SynergyNotificationLabel node found.")

	if not is_instance_valid(track_manager):
		printerr("HUD: TrackManager (LogicTrackDisplay) node not found at path: ", TRACK_MANAGER_PATH)
	else:
		print("HUD: TrackManager (LogicTrackDisplay) node found.")
		
	if not is_instance_valid(inventory_toggle_button):
		printerr("HUD _ready: InventoryToggleButton (HUD\'s own) NOT FOUND.")
	else:	
		inventory_toggle_button.toggle_mode = true # Ensure toggle_mode is true
		inventory_toggle_button.toggled.connect(_on_inventory_toggle_button_toggled)

	if is_instance_valid(game_menu_button):
		game_menu_button.pressed.connect(self._on_game_menu_button_pressed)
		print("HUD: Connected GameMenuButton.pressed to _on_game_menu_button_pressed.")
	else:
		printerr("HUD: GameMenuButton node not found at path: %s" % GAME_MENU_BUTTON_PATH)
		
	if PlayerDiceManager.has_signal("player_dice_changed"):
		PlayerDiceManager.player_dice_changed.connect(_on_player_dice_manager_changed)
		print("HUD: Connected to PlayerDiceManager.player_dice_changed signal.")
	
	# Ensure inventory is hidden by default and updated
	set_inventory_visibility(false) # Use the new public method
	
	# Ensure the score label has a material for the shader
	if is_instance_valid(score_target_display_label) and not score_target_display_label.material:
		printerr("HUD _ready: ScoreTargetDisplay material is not set! Creating a new ShaderMaterial.")
		# This is a fallback, ideally it's set in the .tscn file
		var mat = ShaderMaterial.new()
		var loaded_shader = load("res://score_display.gdshader") # Make sure path is correct
		if loaded_shader:
			mat.shader = loaded_shader
			score_target_display_label.material = mat
			# Initialize shader params if created dynamically
			# score_target_display_label.material.set_shader_parameter("score_ratio", 0.0) # score_ratio is set in update_score_target_display
		else:
			printerr("HUD _ready: FAILED to load 'res://score_display.gdshader'. Shader effects will not work.")

	# Connect to PaletteManager and apply initial palette
	if PaletteManager: # Check if the autoload exists
		PaletteManager.active_palette_updated.connect(_on_palette_changed)
		# Apply initial palette colors if material exists
		if is_instance_valid(score_target_display_label) and score_target_display_label.material:
			_on_palette_changed(PaletteManager.get_current_palette_colors())
		elif is_instance_valid(score_target_display_label) and not score_target_display_label.material:
			printerr("HUD _ready: ScoreTargetDisplay material not ready for initial palette application. Should be created above.")
		else: # score_target_display_label itself might not be valid
			pass # Error already printed if material wasn't created due to no score_target_display_label
	else:
		printerr("HUD _ready: PaletteManager not found. Make sure it's an autoload. Shader colors will not be dynamic.")
	
	print("HUD _ready: End.")

func _process(delta: float):
	# Update shader time uniform if the material and parameter exist
	if is_instance_valid(score_target_display_label) and score_target_display_label.material is ShaderMaterial:
		var mat: ShaderMaterial = score_target_display_label.material
		if mat.shader: # Check if a shader is assigned to the material
			mat.set_shader_parameter("time", Time.get_ticks_msec() / 1000.0)

# --- Public Functions for Game.gd to Call ---

func update_score_target_display(p_score: int, p_target: int):
	current_target_score = p_target # Store the target score
	if is_instance_valid(score_target_display_label):
		score_target_display_label.text = "Score: %d / %d" % [p_score, p_target]
		# Update shader score_ratio
		if score_target_display_label.material is ShaderMaterial:
			var mat: ShaderMaterial = score_target_display_label.material
			if mat.shader: # Check if a shader is assigned
				var score_ratio = 0.0
				if current_target_score > 0:
					score_ratio = clampf(float(p_score) / float(current_target_score), 0.0, 1.0)
				mat.set_shader_parameter("score_ratio", score_ratio)
				# Ensure palette colors are applied if they haven't been due to timing
				# This is a bit of a safeguard, ideally _on_palette_changed handles it.
				if not mat.get_shader_parameter("tier_base_color"): # Check if a color is missing
					if PaletteManager: # Check if the autoload exists
						_on_palette_changed(PaletteManager.get_current_palette_colors())

func update_level_display(p_level: int):
	if is_instance_valid(level_display_label): level_display_label.text = "Level: %d" % p_level
	
func update_rolls_display(p_rolls_available: int, p_max_rolls_this_round: int):
	if is_instance_valid(rolls_display_label):
		rolls_display_label.text = "Rolls: %d/%d" % [p_rolls_available, p_max_rolls_this_round]
	else:
		printerr("HUD: rolls_display_label not valid in update_rolls_display")

func show_synergy_message(full_message: String):
	if is_instance_valid(synergy_notification_label) and not full_message.is_empty():
		synergy_notification_label.text = full_message
		var clear_timer = get_tree().create_timer(SCORE_POPUP_DURATION + 0.5)
		clear_timer.timeout.connect(Callable(synergy_notification_label, "set_text").bind(""))

func update_dice_inventory_display(current_player_dice_array: Array[GlyphData]):
	if not is_instance_valid(dice_face_grid):
		printerr("HUD: Cannot update dice inventory, DiceDisplayGrid for glyphs is missing.")
		return
	for child in dice_face_grid.get_children():
		child.queue_free()
	if current_player_dice_array.is_empty():
		var empty_label := Label.new()
		empty_label.text = "Dice Bag is Empty"
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dice_face_grid.add_child(empty_label)
		return
	for glyph_data in current_player_dice_array:
		if not is_instance_valid(glyph_data): continue

		var texture_rect = TextureRect.new()
		texture_rect.texture = glyph_data.texture
		texture_rect.custom_minimum_size = GLYPH_INVENTORY_GRID_ITEM_SIZE
		texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		texture_rect.tooltip_text = glyph_data.display_name
		
		dice_face_grid.add_child(texture_rect)

	print("HUD: Dice inventory display updated with %d glyphs." % current_player_dice_array.size())

# --- Inventory Management ---
func set_inventory_visibility(is_visible: bool):
	if not is_instance_valid(dice_face_scroll_container):
		printerr("HUD: Cannot set inventory visibility, dice_face_scroll_container is null.")
		return

	if dice_face_scroll_container.visible == is_visible:
		# If showing, and already visible, still refresh content in case dice changed
		# while it was open from a different context (e.g. HUD's own button)
		if is_visible:
			if PlayerDiceManager: # Check if Autoload is available
				update_dice_inventory_display(PlayerDiceManager.get_current_dice())
		return # No change in visibility state

	dice_face_scroll_container.visible = is_visible
	print("HUD: Inventory visibility set to: ", is_visible)

	if is_visible:
		# Ensure the inventory display is up-to-date when shown
		if PlayerDiceManager: # Check if Autoload is available
			update_dice_inventory_display(PlayerDiceManager.get_current_dice())
		else:
			printerr("HUD: PlayerDiceManager not available to update inventory display.")
	
	# Update the modulate of the toggle button based on visibility
	if is_instance_valid(inventory_toggle_button):
		if is_visible:
			inventory_toggle_button.modulate = Color.WHITE # Fully opaque when open
		else:
			inventory_toggle_button.modulate = Color(1, 1, 1, 0.380392) # Semi-transparent when closed
	
	emit_signal("inventory_toggled", is_visible)

# Renamed for clarity: This is for the HUD's own inventory toggle button
func _on_inventory_toggle_button_toggled(button_pressed: bool):
	if not is_instance_valid(dice_face_scroll_container): return
	# Toggle visibility based on current state
	set_inventory_visibility(button_pressed)


func _on_player_dice_manager_changed(new_dice_array: Array[GlyphData]):
	print("HUD: PlayerDiceManager reported dice changed. Updating inventory display if visible.")
	# Only update if the inventory is currently meant to be visible
	if is_instance_valid(dice_face_scroll_container) and dice_face_scroll_container.visible:
		update_dice_inventory_display(new_dice_array)

# --- Animation Sequence Callbacks & Fanfare (largely unchanged) ---
func start_roll_button_animation():
	pass

func stop_roll_button_animation_show_result(glyph_data: GlyphData):
	pass

func trigger_entanglement_visuals(rolled_glyph_slot_index: int, partner_glyph_on_die_data: GlyphData, entanglement_bonus_amount: int):
	print("HUD: Triggering entanglement visuals for rolled glyph in slot %d and partner '%s' on die. Bonus: +%d" % [rolled_glyph_slot_index, partner_glyph_on_die_data.id, entanglement_bonus_amount])

	# 1. Animate the rolled glyph on the track
	if is_instance_valid(track_manager) and track_manager.has_method("get_track_slot_by_index"):
		var slot_node = track_manager.get_track_slot_by_index(rolled_glyph_slot_index)
		if is_instance_valid(slot_node) and slot_node.has_method("play_entanglement_effect_animation"):
			slot_node.play_entanglement_effect_animation()
		elif is_instance_valid(slot_node):
			printerr("HUD: TrackSlot %d missing play_entanglement_effect_animation method." % rolled_glyph_slot_index)
		else:
			printerr("HUD: Could not get valid TrackSlot node for index %d." % rolled_glyph_slot_index)
	
	# 2. Animate the partner glyph in the inventory (DiceFaceDisplayContainer)
	# (This part remains the same as the previous HUD.gd snippet, using metadata)
	if is_instance_valid(dice_face_vbox) and is_instance_valid(partner_glyph_on_die_data):
		for child_node in dice_face_vbox.get_children():
			if child_node is HBoxContainer and child_node.get_child_count() > 1:
				var label_node = child_node.get_child(1) # Assuming label is second child
				if label_node is Label and label_node.text == partner_glyph_on_die_data.display_name:
					print("HUD: Found partner glyph '%s' in inventory for animation." % partner_glyph_on_die_data.id)
					var tween = create_tween()
					tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
					tween.set_parallel(true)
					var original_scale = child_node.get_child(0).scale
					var pulse_scale = original_scale * 1.4 # Make inventory pulse a bit more distinct
					var original_modulate = child_node.get_child(0).modulate
					var pulse_modulate_color = Color.SKY_BLUE # Slightly different shade

					tween.tween_property(child_node.get_child(0), "scale", pulse_scale, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
					tween.tween_property(child_node.get_child(0), "scale", original_scale, 0.25).set_delay(0.15).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
					tween.tween_property(child_node.get_child(0), "modulate", pulse_modulate_color, 0.1).set_trans(Tween.TRANS_LINEAR)
					tween.tween_property(child_node.get_child(0), "modulate", original_modulate, 0.3).set_delay(0.1).set_trans(Tween.TRANS_LINEAR)
					break 
	
	# 3. Score pop-up for entanglement bonus
	if entanglement_bonus_amount > 0 and is_instance_valid(score_target_display_label):
		var popup_text = "+%d Entangled!" % entanglement_bonus_amount
		var popup_color = Color.CYAN # Or Color.SKY_BLUE
		# Position it slightly differently from other popups
		var base_start_pos = score_target_display_label.global_position + score_target_display_label.size / 2.0
		var start_pos = base_start_pos + Vector2(randf_range(-20, 20), randf_range(10, 20) + randf_range(-5, 5)) 
		_create_score_popup_label(popup_text, start_pos, popup_color, 0.15) # Slight delay

func play_score_fanfare(points_from_roll: int, points_from_synergy: int, new_total_round_score: int, synergy_messages: Array[String], success_tier: int):
	# print("HUD: play_score_fanfare. Roll pts: %d, Synergy pts: %d, NEW TOTAL SCORE: %d, Tier: %d, Msgs: %s" % [points_from_roll, points_from_synergy, new_total_round_score, success_tier, str(synergy_messages)])
	_fanfare_active_tweens = 0 
	var base_start_pos = score_target_display_label.global_position + score_target_display_label.size / 2.0


	# Create score popup for roll points if any
	if points_from_roll > 0:
		_fanfare_active_tweens += 1
		var roll_points_text = "+%d" % points_from_roll
		var start_pos = base_start_pos + Vector2(randf_range(-20, 20), randf_range(0, 10))
		var popup_tween = _create_score_popup_label(roll_points_text, start_pos)
		popup_tween.finished.connect(_on_fanfare_tween_finished)

	# Create score popup for synergy points if any
	if points_from_synergy > 0:
		_fanfare_active_tweens += 1
		var synergy_points_text = "+%d SYNERGY!" % points_from_synergy
		var start_pos = base_start_pos + Vector2(randf_range(-20, 20), randf_range(20, 30))
		var popup_tween = _create_score_popup_label(synergy_points_text, start_pos, Color.YELLOW)
		popup_tween.finished.connect(_on_fanfare_tween_finished)

	# Show synergy messages with slight delays
	for i in range(synergy_messages.size()):
		_fanfare_active_tweens += 1
		var msg = synergy_messages[i]
		var start_pos = Vector2(400, 320) + Vector2(randf_range(-20, 20), i * 20) # Centered around (400, 320)
		var popup_tween = _create_score_popup_label(msg, start_pos, Color.CYAN, 0.15 * i)
		popup_tween.finished.connect(_on_fanfare_tween_finished)

	# If no animations were created, emit finished immediately
	if _fanfare_active_tweens == 0:
		emit_signal("fanfare_animation_finished")

func _on_fanfare_tween_finished():
	_fanfare_active_tweens -= 1
	if _fanfare_active_tweens <= 0:
		emit_signal("fanfare_animation_finished")

func _on_palette_changed(palette_colors: Dictionary) -> void:
	if not is_instance_valid(score_target_display_label) or not score_target_display_label.material or not score_target_display_label.material.shader:
		# print("HUD: ScoreTargetDisplay material or shader not found, cannot apply palette colors.")
		# This can happen if _ready order is such that material isn't set when first signal arrives
		return

	var main_color = palette_colors.get("main", Color.WHITE)
	var accent_color = palette_colors.get("accent", Color.RED)

	var mat: ShaderMaterial = score_target_display_label.material

	mat.set_shader_parameter("tier_base_color", main_color)
	
	var bronze_color = main_color.lerp(Color(0.5,0.5,0.5,1.0), 0.3) 
	mat.set_shader_parameter("tier_bronze_color", bronze_color)

	var silver_color = main_color.lightened(0.1)
	mat.set_shader_parameter("tier_silver_color", silver_color)

	mat.set_shader_parameter("tier_gold_color", accent_color)

	var platinum_color = accent_color.lightened(0.2).lerp(Color.WHITE, 0.3)
	mat.set_shader_parameter("tier_platinum_color", platinum_color)
	
	# print("HUD: Updated ScoreTargetDisplay shader colors from palette.")

func _create_score_popup_label(text_to_display: String, start_global_pos: Vector2, color: Color = Color.WHITE, delay: float = 0.0) -> Tween:
	var popup_label = Label.new()
	popup_label.text = text_to_display
	popup_label.modulate = color
	popup_label.global_position = start_global_pos 
	add_child(popup_label)
	var popup_tween = create_tween()
	popup_tween.set_parallel(true)
	if delay > 0.0:
		popup_tween.tween_interval(delay)
	var target_pos = popup_label.position + Vector2(0, SCORE_POPUP_TRAVEL_Y)
	popup_tween.tween_property(popup_label, "position", target_pos, SCORE_POPUP_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	popup_tween.tween_property(popup_label, "modulate:a", 0.0, SCORE_POPUP_DURATION * 0.7).set_delay(SCORE_POPUP_DURATION * 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	popup_tween.finished.connect(popup_label.queue_free)
	return popup_tween

func get_next_history_slot_global_position() -> Vector2:
	if is_instance_valid(track_manager) and track_manager.has_method("get_global_position_of_next_slot"):
		return track_manager.get_global_position_of_next_slot()
	printerr("HUD: TrackManager not found or no get_global_position_of_next_slot method for get_next_history_slot_global_position.")
	return get_viewport_rect().size / 2.0

func add_glyph_to_visual_history(glyph: GlyphData):
	if is_instance_valid(track_manager) and track_manager.has_method("place_glyph_on_next_available_slot"):
		track_manager.place_glyph_on_next_available_slot(glyph)
	else:
		printerr("HUD: TrackManager not found or no place_glyph_on_next_available_slot method.")

func reset_full_game_visuals():
	print("HUD: reset_full_game_visuals called.")
	if is_instance_valid(track_manager) and track_manager.has_method("clear_track_for_new_round"):
		track_manager.clear_track_for_new_round() 
	if is_instance_valid(track_manager) and track_manager.has_method("update_specific_cornerstone_logic_unlocked"):
		track_manager.update_specific_cornerstone_logic_unlocked(2, false)
	show_boss_incoming_indicator(false)
	set_inventory_visibility(false) # Ensure inventory is hidden on full reset

func reset_round_visuals():
	if is_instance_valid(synergy_notification_label): synergy_notification_label.text = ""
	if is_instance_valid(track_manager) and track_manager.has_method("clear_track_for_new_round"):
		track_manager.clear_track_for_new_round() 
	else:
		printerr("HUD: TrackManager not found or no clear_track_for_new_round method.")
	# Inventory visibility is not reset per round, only on full game reset or when loot screen closes.

func activate_track_slots(num_slots_to_activate: int):
	if is_instance_valid(track_manager) and track_manager.has_method("activate_slots_for_round"):
		track_manager.activate_slots_for_round(num_slots_to_activate)
	else:
		printerr("HUD: TrackManager not found or no activate_slots_for_round method.")

func update_cornerstone_display(slot_index_zero_based: int, is_logic_unlocked: bool):
	if is_instance_valid(track_manager) and track_manager.has_method("update_specific_cornerstone_logic_unlocked"):
		track_manager.update_specific_cornerstone_logic_unlocked(slot_index_zero_based, is_logic_unlocked)
	else:
		printerr("HUD: TrackManager not found for update_cornerstone_display (update_specific_cornerstone_logic_unlocked).")

func show_boss_incoming_indicator(show: bool, message: String = "Boss Incoming!"):
	if not is_instance_valid(boss_indicator_panel):
		return
	if show:
		boss_indicator_panel.visible = true
		boss_indicator_label.text = message
		boss_indicator_label.tooltip_text = "The next round features a powerful Boss!"
	else:
		boss_indicator_panel.visible = false

# Helper for Game.gd to access track slot nodes for synergy visuals
func get_track_slot_node_by_index(index: int) -> Node:
	if is_instance_valid(track_manager) and track_manager.has_method("get_track_slot_by_index"):
		return track_manager.get_track_slot_by_index(index)
	printerr("HUD: Cannot get_track_slot_node_by_index. TrackManager is invalid or missing method.")
	return null

func _on_game_menu_button_pressed():
	emit_signal("game_menu_button_pressed")
	print("HUD: Game menu button pressed, emitting signal.")

