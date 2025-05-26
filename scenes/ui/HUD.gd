# res://scripts/ui/HUD.gd
# TABS FOR INDENTATION
extends Control

signal inventory_toggled(is_now_visible: bool)
signal fanfare_animation_finished # Emitted when all score/synergy popups and animations are done

# --- UI Node References ---
@onready var score_label: Label = $ScoreLabel
@onready var target_label: Label = $TargetLabel
@onready var rolls_label: Label = $RollsLabel
@onready var level_label: Label = $LevelLabel

@onready var last_roll_display: TextureRect = $LastRollDisplay # Separate display, not on button
@onready var synergy_notification_label: Label = $SynergyNotificationLabel # Used for synergy text

@onready var roll_history_display_container: Control = $RollHistoryDisplayContainer
@onready var dice_face_scroll_container: ScrollContainer = $DiceFaceScrollContainer
@onready var dice_face_display_container: GridContainer = $DiceFaceScrollContainer/dice_face_display_container
@onready var inventory_toggle_button: TextureButton = $InventoryToggleButton

@onready var boss_indicator_label: Label = $BossIndicatorLabel

# For easier debugging of the timer
var fanfare_check_timer: Timer = null 
# --- Member variables for fanfare tracking ---
var _fanfare_active_tweens: int = 0 # Count of currently running fanfare tweens

# --- Visual Roll History Data ---
const MAX_VISUAL_HISTORY_SLOTS: int = 15 
# roll_history_slot_positions are local positions relative to roll_history_display_container
# We will get global positions when needed.
var current_visual_history_index: int = 0

# --- Config for Score Popups ---
const SCORE_POPUP_DURATION: float = 1.2 # How long score popups animate
const SCORE_POPUP_TRAVEL_Y: float = -70.0 # How far up they move
const MY_LIGHT_GOLD: Color = Color(1.0, 0.843, 0.0, 0.7) # Example: Color.gold with some transparency or custom mix

func _ready():
	print("HUD _ready: Start.")
	if not is_instance_valid(dice_face_scroll_container):
		printerr("HUD _ready: DiceFaceScrollContainer NOT FOUND.")
	if not is_instance_valid(dice_face_display_container):
		printerr("HUD _ready: dice_face_display_container NOT FOUND.")
	
	_initialize_visual_history_slots()

	if is_instance_valid(inventory_toggle_button):
		inventory_toggle_button.pressed.connect(Callable(self, "_on_inventory_toggle_button_pressed"))
	else:
		printerr("HUD _ready: InventoryToggleButton NOT FOUND.")
	
	if is_instance_valid(dice_face_scroll_container):
		dice_face_scroll_container.visible = false
	print("HUD _ready: End.")

# --- Public Functions for Game.gd to Call ---

func update_score_target_display(p_score: int, p_target: int):
	if is_instance_valid(score_label): score_label.text = "Score " + str(p_score)
	if is_instance_valid(target_label): target_label.text = "Target " + str(p_target)


func update_level_display(p_level: int):
	if is_instance_valid(level_label): level_label.text = "Level " + str(p_level)

func update_last_rolled_glyph_display(glyph: GlyphData): # Updates the HUD's static last_roll_display
	if is_instance_valid(last_roll_display):
		if is_instance_valid(glyph) and is_instance_valid(glyph.texture):
			last_roll_display.texture = glyph.texture
			last_roll_display.visible = true
		else:
			last_roll_display.texture = null
			last_roll_display.visible = false # Hide if no glyph

func show_synergy_message(full_message: String): # Used by fanfare now
	if is_instance_valid(synergy_notification_label) and not full_message.is_empty():
		synergy_notification_label.text = full_message
		# Timer to clear this can be managed by fanfare logic or kept simple like this
		var clear_timer = get_tree().create_timer(SCORE_POPUP_DURATION + 0.5) # Last a bit longer
		clear_timer.timeout.connect(Callable(synergy_notification_label, "set_text").bind(""))

func update_dice_inventory_display(current_player_dice_array: Array[GlyphData]):
	if not is_instance_valid(dice_face_display_container):
		printerr("HUD: DiceFaceDisplayContainer is not valid.")
		return
	for child in dice_face_display_container.get_children():
		child.queue_free()
	if current_player_dice_array.is_empty():
		var empty_label := Label.new()
		empty_label.text = "[No Faces]" # TODO: Style this
		dice_face_display_container.add_child(empty_label)
		return
	for glyph_data in current_player_dice_array:
		if not is_instance_valid(glyph_data): continue
		var face_rect := TextureRect.new()
		face_rect.custom_minimum_size = Vector2(40, 40)
		face_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		face_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		face_rect.texture = glyph_data.texture
		face_rect.tooltip_text = glyph_data.display_name + " (Val: " + str(glyph_data.value) + ")"
		dice_face_display_container.add_child(face_rect)

# --- New Animation Sequence Callbacks from Game.gd ---

func start_roll_button_animation():
	# Game.gd handles the actual AnimatedSprite2D on its roll_button.
	# This HUD function could trigger other HUD-specific effects if desired.
	print("HUD: start_roll_button_animation called (currently no-op in HUD).")
	pass

func stop_roll_button_animation_show_result(glyph_data: GlyphData):
	print("HUD: stop_roll_button_animation_show_result called for glyph: ", glyph_data.display_name if is_instance_valid(glyph_data) else "Invalid Glyph")
	# OLD LOGIC that showed the "middle glyph" too early:
	# update_last_rolled_glyph_display(glyph_data) 
	
	# NEW: This function might not need to do anything for the new sequence,
	# as Game.gd handles the on-button display, and the fanfare handles the center reveal.
	# If HUD.last_roll_display is for a different purpose, it should be updated elsewhere.
	print("HUD: stop_roll_button_animation_show_result - No visual action taken on HUD.last_roll_display by this function anymore.")
	pass


func play_score_fanfare(points_from_roll: int, points_from_synergy: int, new_total_round_score: int, synergy_messages: Array[String], success_tier: int):
	print("HUD: play_score_fanfare. Roll pts: %d, Synergy pts: %d, NEW TOTAL SCORE: %d, Tier: %d, Msgs: %s" % [points_from_roll, points_from_synergy, new_total_round_score, success_tier, str(synergy_messages)])
	
	_fanfare_active_tweens = 0 # Reset for this call

	# 1. Animate main score_label
	if is_instance_valid(score_label):
		_fanfare_active_tweens += 1
		var score_anim_tween = create_tween()
		#score_anim_tween.set_name("ScoreLabelFanfareTween")
		score_anim_tween.set_parallel(false) 

		var original_scale = score_label.scale
		var original_modulate = score_label.modulate
		var original_pos = score_label.position

		var pop_scale_factor = 1.1 + (success_tier * 0.1)
		score_anim_tween.tween_property(score_label, "scale", original_scale * pop_scale_factor, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		score_anim_tween.tween_property(score_label, "scale", original_scale, 0.2).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		
		score_anim_tween.tween_callback(Callable(score_label, "set_text").bind("Score " + str(new_total_round_score))) # Update text

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

		score_anim_tween.finished.connect(Callable(self, "_on_individual_fanfare_tween_finished").bind("Score Label"))
		print("HUD: Score label animation tween STARTED.")
	else:
		printerr("HUD: score_label is not valid for fanfare animation!")

	# 2. Create score popups for roll points
	if points_from_roll != 0:
		_fanfare_active_tweens += 1
		var roll_popup_text: String = "+" + str(points_from_roll)
		var roll_popup_color: Color = Color.WHITE
		if points_from_roll < 0: roll_popup_color = Color.RED
		
		var roll_popup_tween = _create_score_popup_label(roll_popup_text, score_label.global_position + Vector2(0, -20), roll_popup_color)
		#roll_popup_tween.set_name("RollPointsPopupTween")
		roll_popup_tween.finished.connect(Callable(self, "_on_individual_fanfare_tween_finished").bind("Roll Points Popup"))
		print("HUD: Roll points popup tween STARTED.")
	else:
		print("HUD: No roll points, skipping roll_popup_tween.")

	# 3. Create score popups for synergy points
	if points_from_synergy != 0:
		_fanfare_active_tweens += 1
		var synergy_popup_text: String = "+" + str(points_from_synergy) + " Synergy!"
		var synergy_popup_color: Color = Color.GOLD 
		
		var synergy_popup_tween = _create_score_popup_label(synergy_popup_text, score_label.global_position + Vector2(20, -40), synergy_popup_color, 0.2)
		#synergy_popup_tween.set_name("SynergyPointsPopupTween")
		synergy_popup_tween.finished.connect(Callable(self, "_on_individual_fanfare_tween_finished").bind("Synergy Points Popup"))
		print("HUD: Synergy points popup tween STARTED.")
	else:
		print("HUD: No synergy points, skipping synergy_popup_tween.")
	
	print("HUD: Total fanfare tweens initiated: ", _fanfare_active_tweens)

	# 4. Display synergy text messages
	if not synergy_messages.is_empty():
		var combined_message = ""
		for msg in synergy_messages: combined_message += msg + "\n"
		show_synergy_message(combined_message.strip_edges())

	# If no tweens were ever started, emit signal immediately
	if _fanfare_active_tweens == 0:
		print("HUD: No fanfare tweens were initiated. Emitting fanfare_animation_finished immediately.")
		emit_signal("fanfare_animation_finished")

# New helper method to handle completion of each tween
func _on_individual_fanfare_tween_finished(tween_name: String):
	print("HUD: Tween '%s' FINISHED." % tween_name)
	if _fanfare_active_tweens > 0: # Defensive check
		_fanfare_active_tweens -= 1
		print("HUD: Remaining active fanfare tweens: ", _fanfare_active_tweens)
	
	if _fanfare_active_tweens == 0:
		print("HUD: All fanfare tweens reported completed. Emitting fanfare_animation_finished.")
		emit_signal("fanfare_animation_finished")



func _create_score_popup_label(text_to_display: String, start_global_pos: Vector2, color: Color = Color.WHITE, delay: float = 0.0) -> Tween:
	var popup_label = Label.new()
	popup_label.text = text_to_display
	popup_label.modulate = color
	# TODO: Set font, font_size, outline from Theme or code
	# popup_label.add_theme_font_size_override("font_size", 24) # Example
	# popup_label.add_theme_color_override("font_outline_color", Color.BLACK) # Example
	# popup_label.add_theme_constant_override("outline_size", 2) # Example
	
	# Convert global start position to HUD's local coordinates
	popup_label.global_position = start_global_pos 
	add_child(popup_label) # Add to HUD itself

	var popup_tween = create_tween()
	popup_tween.set_parallel(true) # Position and alpha fade together
	if delay > 0.0:
		popup_tween.tween_interval(delay)
	
	var target_pos = popup_label.position + Vector2(0, SCORE_POPUP_TRAVEL_Y)
	popup_tween.tween_property(popup_label, "position", target_pos, SCORE_POPUP_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	popup_tween.tween_property(popup_label, "modulate:a", 0.0, SCORE_POPUP_DURATION * 0.7).set_delay(SCORE_POPUP_DURATION * 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	popup_tween.finished.connect(Callable(popup_label, "queue_free")) # Clean up label
	return popup_tween


func get_next_history_slot_global_position() -> Vector2:
	if not is_instance_valid(roll_history_display_container):
		printerr("HUD: RollHistoryDisplayContainer not valid for getting slot position.")
		return get_viewport_rect().size / 2.0 

	if current_visual_history_index < roll_history_display_container.get_child_count():
		var slot_node = roll_history_display_container.get_child(current_visual_history_index)
		if slot_node is Control:
			var slot_control = slot_node as Control
			# Ensure the slot_control has the correct size (e.g., 80x80)
			# Return the global center of this slot
			return slot_control.global_position + (slot_control.size / 2.0)
		else:
			printerr("HUD: History slot node is not a Control.")
	else:
		printerr("HUD: current_visual_history_index out of bounds for slot positions.")
	
	return get_viewport_rect().size / 2.0 # Fallback

# --- Visual History Management ---

func add_glyph_to_visual_history(glyph: GlyphData): # Called by Game.gd AFTER glyph animates to slot
	if not is_instance_valid(roll_history_display_container): return
	if not is_instance_valid(glyph): return
		
	if current_visual_history_index < MAX_VISUAL_HISTORY_SLOTS and \
	   current_visual_history_index < roll_history_display_container.get_child_count():
		
		var history_item_node = roll_history_display_container.get_child(current_visual_history_index)
		if history_item_node is TextureRect:
			var item_rect := history_item_node as TextureRect
			item_rect.texture = glyph.texture
			item_rect.visible = true # Make the static slot visible
		current_visual_history_index += 1
	# else: print("HUD: Visual history slots full or index issue.")


func reset_round_visuals():
	current_visual_history_index = 0
	if is_instance_valid(roll_history_display_container):
		for i in range(roll_history_display_container.get_child_count()):
			var child_node = roll_history_display_container.get_child(i)
			if child_node is TextureRect:
				var item_rect := child_node as TextureRect
				item_rect.visible = false # Hide placeholder
				item_rect.texture = null  # Clear texture
	
	if is_instance_valid(last_roll_display):
		last_roll_display.texture = null
		last_roll_display.visible = false
	
	if is_instance_valid(synergy_notification_label):
		synergy_notification_label.text = ""
	
	# Score label will be updated by Game.gd with initial round score.

# --- Internal HUD Functions ---

func _initialize_visual_history_slots():
	if not is_instance_valid(roll_history_display_container):
		printerr("HUD: RollHistoryDisplayContainer not found!")
		return
	for child in roll_history_display_container.get_children():
		child.queue_free() # Clear previous if any (e.g. editor placeholders)

	# These positions are relative to the roll_history_display_container itself
	var slot_positions_local = [
		Vector2(240, 480), Vector2(160, 480), Vector2(80, 480),
		Vector2(80, 400), Vector2(80, 320), Vector2(80, 240), Vector2(80, 160), Vector2(80, 80),
		Vector2(160, 80), Vector2(240, 80), Vector2(320, 80), Vector2(400, 80), Vector2(480, 80),
		Vector2(480, 160), Vector2(480, 240)
	] # These are the same as Game.gd's old ones, assuming they are local to the container now.
	# If roll_history_display_container is at (0,0) of the logo, these are fine.
	# Otherwise, these should be adjusted or calculated based on the logo image.

	for i in range(MAX_VISUAL_HISTORY_SLOTS):
		var history_item_rect := TextureRect.new()
		history_item_rect.custom_minimum_size = Vector2(80, 80) # As per context doc
		history_item_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		history_item_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		
		if i < slot_positions_local.size():
			history_item_rect.position = slot_positions_local[i]
		else: # Should not happen if MAX_VISUAL_HISTORY_SLOTS matches array
			history_item_rect.position = Vector2(-200, -200) # Hide off-screen
			
		history_item_rect.visible = false # Start hidden, no texture
		roll_history_display_container.add_child(history_item_rect)
	print("HUD: Visual history display initialized with ", roll_history_display_container.get_child_count(), " slots.")


func _on_inventory_toggle_button_pressed():
	if not is_instance_valid(dice_face_scroll_container): return
	dice_face_scroll_container.visible = not dice_face_scroll_container.visible
	emit_signal("inventory_toggled", dice_face_scroll_container.visible)

func reset_full_game_visuals(): # NEW - Called when a brand new game session starts
	print("HUD: reset_full_game_visuals called.")
	reset_round_visuals() # Clear current round stuff
	update_cornerstone_display(3, false) # Ensure cornerstone visuals are reset
	show_boss_incoming_indicator(false) # Hide boss indicator
	# Any other HUD elements specific to a run that need resetting

func update_cornerstone_display(slot_index: int, is_active: bool): # NEW
	# This is a placeholder. You'll need to identify the UI element for cornerstone slot 3.
	# For example, if your roll history slots are TextureRects and slot 3 is the child at index 2:
	if not is_instance_valid(roll_history_display_container): return
	
	if slot_index == 3 and roll_history_display_container.get_child_count() > 2:
		var slot_3_node = roll_history_display_container.get_child(2) # Slot 3 is index 2
		if slot_3_node is Control: # TextureRect inherits Control
			if is_active:
				(slot_3_node as Control).modulate = Color.GOLD # Example: make it glow gold
				# Could also change a border texture, play an animation, etc.
				print("HUD: Cornerstone Slot 3 visual activated.")
			else:
				(slot_3_node as Control).modulate = Color.WHITE # Reset to default
				print("HUD: Cornerstone Slot 3 visual deactivated.")
	else:
		print("HUD: update_cornerstone_display called for unhandled slot: ", slot_index)

func show_boss_incoming_indicator(show: bool, message: String = "Boss Incoming!"): # NEW
	if not is_instance_valid(boss_indicator_label):
		# If you don't have a dedicated label, you could print or use PlayerNotificationSystem
		if show: PlayerNotificationSystem.display_message(message, 5.0) # Longer duration
		print("HUD: Boss indicator label not found. Show: %s, Msg: %s" % [str(show), message])
		return

	if show:
		boss_indicator_label.text = message
		boss_indicator_label.tooltip_text = "The next round features a powerful Boss!" # Example tooltip
		boss_indicator_label.visible = true
		print("HUD: Boss incoming indicator SHOWN: ", message)
	else:
		boss_indicator_label.visible = false
		print("HUD: Boss incoming indicator HIDDEN.")


# --- Ensure rolls display uses explicit counts from Game.gd ---
func update_rolls_display(p_rolls_available: int, p_max_rolls_this_round: int): # Arguments changed
	if is_instance_valid(rolls_label):
		rolls_label.text = "Rolls " + str(p_rolls_available) + "/" + str(p_max_rolls_this_round)
