# res://scripts/ui/HUD.gd
# TABS FOR INDENTATION
extends Control

signal inventory_toggled(is_now_visible: bool) # Existing signal
signal fanfare_animation_finished 

# --- UI Node References ---
@onready var score_label: Label = $ScoreLabel
@onready var target_label: Label = $TargetLabel
@onready var rolls_label: Label = $RollsLabel
@onready var level_label: Label = $LevelLabel

@onready var synergy_notification_label: Label = $SynergyNotificationLabel

@onready var dice_face_scroll_container: ScrollContainer = $DiceFaceScrollContainer
@onready var dice_face_display_container: GridContainer = $DiceFaceScrollContainer/dice_face_display_container
@onready var inventory_toggle_button: TextureButton = $InventoryToggleButton # HUD's own inventory button

@onready var boss_indicator_label: Label = $BossIndicatorLabel
@onready var track_manager: Control = $LogicTrackDisplay

var fanfare_check_timer: Timer = null 
var _fanfare_active_tweens: int = 0

var current_target_score: int = 0 # Add a variable to store the current target

const SCORE_POPUP_DURATION: float = 1.2
const SCORE_POPUP_TRAVEL_Y: float = -70.0

func _ready():
	print("HUD _ready: Start.")
	if not is_instance_valid(dice_face_scroll_container):
		printerr("HUD _ready: DiceFaceScrollContainer NOT FOUND.")
	if not is_instance_valid(dice_face_display_container):
		printerr("HUD _ready: dice_face_display_container NOT FOUND.")
	
	if not is_instance_valid(track_manager):
		printerr("HUD _ready: LogicTrackDisplay (TrackManager) node NOT FOUND!")
	else:
		print("HUD _ready: LogicTrackDisplay (TrackManager) node found.")
		
	if is_instance_valid(inventory_toggle_button):
		inventory_toggle_button.pressed.connect(_on_hud_inventory_toggle_button_pressed) # Renamed for clarity
	else:	
		printerr("HUD _ready: InventoryToggleButton (HUD's own) NOT FOUND.")
		
	if PlayerDiceManager.has_signal("player_dice_changed"):
		PlayerDiceManager.player_dice_changed.connect(_on_player_dice_manager_changed)
		print("HUD: Connected to PlayerDiceManager.player_dice_changed signal.")
	
	# Ensure inventory is hidden by default and updated
	set_inventory_visibility(false) # Use the new public method
	
	# Ensure the score label has a material for the shader
	if is_instance_valid(score_label) and not score_label.material:
		printerr("HUD _ready: ScoreLabel material is not set! Creating a new ShaderMaterial.")
		# This is a fallback, ideally it's set in the .tscn file
		var mat = ShaderMaterial.new()
		var loaded_shader = load("res://score_display.gdshader") # Make sure path is correct
		if loaded_shader:
			mat.shader = loaded_shader
			score_label.material = mat
			# Initialize shader params if created dynamically
			score_label.material.set_shader_parameter("score_ratio", 0.0) # Assumes 'score_ratio' exists
		else:
			printerr("HUD _ready: FAILED to load 'res://score_display.gdshader'. Shader effects will not work.")
	
	print("HUD _ready: End.")

func _process(delta: float):
	# Update shader time uniform if the material and parameter exist
	if is_instance_valid(score_label) and score_label.material is ShaderMaterial:
		var mat: ShaderMaterial = score_label.material
		if mat.shader: # Check if a shader is assigned to the material
			mat.set_shader_parameter("time", Time.get_ticks_msec() / 1000.0)

# --- Public Functions for Game.gd to Call ---

func update_score_target_display(p_score: int, p_target: int):
	current_target_score = p_target # Store the target score
	if is_instance_valid(score_label):
		score_label.text = "Score " + str(p_score)
		# Update shader score_ratio
		if score_label.material is ShaderMaterial:
			var mat: ShaderMaterial = score_label.material
			if mat.shader: # Check if a shader is assigned
				var score_ratio = 0.0
				if current_target_score > 0:
					score_ratio = clampf(float(p_score) / float(current_target_score), 0.0, 1.0)
				mat.set_shader_parameter("score_ratio", score_ratio)

	if is_instance_valid(target_label): target_label.text = "Target " + str(p_target)

func update_level_display(p_level: int):
	if is_instance_valid(level_label): level_label.text = "Level " + str(p_level)
	
func update_rolls_display(p_rolls_available: int, p_max_rolls_this_round: int):
	if is_instance_valid(rolls_label):
		rolls_label.text = "Rolls " + str(p_rolls_available) + "/" + str(p_max_rolls_this_round)
	else:
		printerr("HUD: rolls_label not valid in update_rolls_display")

func show_synergy_message(full_message: String):
	if is_instance_valid(synergy_notification_label) and not full_message.is_empty():
		synergy_notification_label.text = full_message
		var clear_timer = get_tree().create_timer(SCORE_POPUP_DURATION + 0.5)
		clear_timer.timeout.connect(Callable(synergy_notification_label, "set_text").bind(""))

func update_dice_inventory_display(current_player_dice_array: Array[GlyphData]):
	if not is_instance_valid(dice_face_display_container):
		printerr("HUD: DiceFaceDisplayContainer is not valid.")
		return
	for child in dice_face_display_container.get_children():
		child.queue_free()
	if current_player_dice_array.is_empty():
		var empty_label := Label.new()
		empty_label.text = "[No Faces]"
		dice_face_display_container.add_child(empty_label)
		return
	for glyph_data in current_player_dice_array:
		if not is_instance_valid(glyph_data): continue
		var face_rect := TextureRect.new()
		face_rect.custom_minimum_size = Vector2(40, 40) # Ensure this matches your design
		face_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		face_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		face_rect.texture = glyph_data.texture
		face_rect.tooltip_text = glyph_data.display_name + " (Val: " + str(glyph_data.value) + ")"
		face_rect.set_meta("glyph_id", glyph_data.id) # <<< STORE GLYPH ID
		dice_face_display_container.add_child(face_rect)

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
	
	emit_signal("inventory_toggled", is_visible)

# Renamed for clarity: This is for the HUD's own inventory toggle button
func _on_hud_inventory_toggle_button_pressed():
	if not is_instance_valid(dice_face_scroll_container): return
	# Toggle visibility based on current state
	set_inventory_visibility(!dice_face_scroll_container.visible)


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
	if is_instance_valid(dice_face_display_container) and is_instance_valid(partner_glyph_on_die_data):
		for child_node in dice_face_display_container.get_children():
			if child_node is TextureRect:
				var face_rect: TextureRect = child_node
				var meta_glyph_id = face_rect.get_meta("glyph_id", "")
				if meta_glyph_id == partner_glyph_on_die_data.id:
					print("HUD: Found partner glyph '%s' in inventory for animation." % partner_glyph_on_die_data.id)
					var tween = create_tween()
					tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
					tween.set_parallel(true)
					var original_scale = face_rect.scale
					var pulse_scale = original_scale * 1.4 # Make inventory pulse a bit more distinct
					var original_modulate = face_rect.modulate
					var pulse_modulate_color = Color.SKY_BLUE # Slightly different shade

					tween.tween_property(face_rect, "scale", pulse_scale, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
					tween.tween_property(face_rect, "scale", original_scale, 0.25).set_delay(0.15).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
					tween.tween_property(face_rect, "modulate", pulse_modulate_color, 0.1).set_trans(Tween.TRANS_LINEAR)
					tween.tween_property(face_rect, "modulate", original_modulate, 0.3).set_delay(0.1).set_trans(Tween.TRANS_LINEAR)
					break 
	
	# 3. Score pop-up for entanglement bonus
	if entanglement_bonus_amount > 0 and is_instance_valid(score_label):
		var popup_text = "+%d Entangled!" % entanglement_bonus_amount
		var popup_color = Color.CYAN # Or Color.SKY_BLUE
		# Position it slightly differently from other popups
		var start_pos = score_label.global_position + Vector2(randf_range(-10, 10), -60 + randf_range(-5, 5)) 
		_create_score_popup_label(popup_text, start_pos, popup_color, 0.15) # Slight delay

func play_score_fanfare(points_from_roll: int, points_from_synergy: int, new_total_round_score: int, synergy_messages: Array[String], success_tier: int):
	# print("HUD: play_score_fanfare. Roll pts: %d, Synergy pts: %d, NEW TOTAL SCORE: %d, Tier: %d, Msgs: %s" % [points_from_roll, points_from_synergy, new_total_round_score, success_tier, str(synergy_messages)])
	_fanfare_active_tweens = 0 

	if is_instance_valid(score_label):
		_fanfare_active_tweens += 1
		var score_anim_tween = create_tween()
		score_anim_tween.set_parallel(false) 
		var original_scale = score_label.scale
		var original_modulate = score_label.modulate
		var original_pos = score_label.position
		var pop_scale_factor = 1.1 + (success_tier * 0.1)

		# Update shader score_ratio based on new_total_round_score and target
		if score_label.material is ShaderMaterial:
			var mat: ShaderMaterial = score_label.material
			if mat.shader: # Check if a shader is assigned
				var score_ratio = 0.0
				if current_target_score > 0:
					score_ratio = clampf(float(new_total_round_score) / float(current_target_score), 0.0, 1.0)
				print("HUD Fanfare: Updating score_ratio to: ", score_ratio)
				mat.set_shader_parameter("score_ratio", score_ratio)

		score_anim_tween.tween_property(score_label, "scale", original_scale * pop_scale_factor, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		score_anim_tween.tween_property(score_label, "scale", original_scale, 0.2).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		score_anim_tween.tween_callback(Callable(score_label, "set_text").bind("Score " + str(new_total_round_score)))
		if success_tier > 0:
			var flash_color = Color.YELLOW
			if success_tier >= 3: flash_color = Color.GOLD
			if success_tier >= 4: flash_color = Color.ORANGE_RED
			score_anim_tween.tween_property(score_label, "modulate", flash_color, 0.1)
			score_anim_tween.tween_property(score_label, "modulate", original_modulate, 0.1).set_delay(0.1)
			if success_tier >= 2:
				score_anim_tween.tween_property(score_label, "modulate", flash_color, 0.1)
				score_anim_tween.tween_property(score_label, "modulate", original_modulate, 0.1).set_delay(0.1)
		if success_tier >= 2:
			var shake_amount = 3.0 + success_tier
			var shake_duration_each = 0.05
			for _i in range(3 + success_tier):
				score_anim_tween.tween_property(score_label, "position", original_pos + Vector2(randf_range(-shake_amount, shake_amount), randf_range(-shake_amount, shake_amount)), shake_duration_each)
			score_anim_tween.tween_property(score_label, "position", original_pos, shake_duration_each)
		score_anim_tween.finished.connect(_on_individual_fanfare_tween_finished.bind("Score Label"))
	else:
		printerr("HUD: score_label is not valid for fanfare animation!")

	if points_from_roll != 0:
		_fanfare_active_tweens += 1
		var roll_popup_text: String = "+" + str(points_from_roll)
		var roll_popup_color: Color = Color.WHITE
		if points_from_roll < 0: roll_popup_color = Color.RED
		var roll_popup_tween = _create_score_popup_label(roll_popup_text, score_label.global_position + Vector2(0, -20), roll_popup_color)
		roll_popup_tween.finished.connect(_on_individual_fanfare_tween_finished.bind("Roll Points Popup"))
	
	if points_from_synergy != 0:
		_fanfare_active_tweens += 1
		var synergy_popup_text: String = "+" + str(points_from_synergy) + " Synergy!"
		var synergy_popup_color: Color = Color.GOLD 
		var synergy_popup_tween = _create_score_popup_label(synergy_popup_text, score_label.global_position + Vector2(20, -40), synergy_popup_color, 0.2)
		synergy_popup_tween.finished.connect(_on_individual_fanfare_tween_finished.bind("Synergy Points Popup"))
	
	if not synergy_messages.is_empty():
		var combined_message = ""
		for msg in synergy_messages: combined_message += msg + "\n"
		show_synergy_message(combined_message.strip_edges())

	if _fanfare_active_tweens == 0:
		emit_signal("fanfare_animation_finished")

func _on_individual_fanfare_tween_finished(tween_name: String):
	# print("HUD: Tween '%s' FINISHED." % tween_name)
	if _fanfare_active_tweens > 0:
		_fanfare_active_tweens -= 1
	if _fanfare_active_tweens == 0:
		emit_signal("fanfare_animation_finished")

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
	if not is_instance_valid(boss_indicator_label):
		return
	if show:
		boss_indicator_label.text = message
		boss_indicator_label.tooltip_text = "The next round features a powerful Boss!"
		boss_indicator_label.visible = true
	else:
		boss_indicator_label.visible = false

