# res://scripts/ui/HUD.gd (or res://scenes/ui/HUD.gd)
# TABS FOR INDENTATION
extends Control

# --- UI Node References ---
@onready var score_label: Label = $ScoreLabel # Adjust paths if you nested them further under HUD root
@onready var target_label: Label = $TargetLabel
@onready var rolls_label: Label = $RollsLabel
@onready var level_label: Label = $LevelLabel

@onready var last_roll_display: TextureRect = $LastRollDisplay
@onready var synergy_notification_label: Label = $SynergyNotificationLabel

@onready var roll_history_display_container: Control = $RollHistoryDisplayContainer
@onready var dice_face_scroll_container: ScrollContainer = $DiceFaceScrollContainer
@onready var dice_face_display_container: GridContainer = $DiceFaceScrollContainer/dice_face_display_container # Child of ScrollContainer
@onready var inventory_toggle_button: TextureButton = $InventoryToggleButton

# --- Visual Roll History Data (moved from Game.gd) ---
const MAX_VISUAL_HISTORY_SLOTS: int = 15 
var roll_history_slot_positions: Array[Vector2] = [] # Will be initialized in _ready
var current_visual_history_index: int = 0

func _ready():
	# --- DEBUG CHECK ---
	if not is_instance_valid(dice_face_scroll_container):
		printerr("HUD _ready: DiceFaceScrollContainer NOT FOUND or invalid. Path used: $DiceFaceScrollContainer")
	else:
		print("HUD _ready: DiceFaceScrollContainer found.")
		
	if not is_instance_valid(dice_face_display_container):
		printerr("HUD _ready: dice_face_display_container (GridContainer) NOT FOUND or invalid. Path used: $DiceFaceScrollContainer/dice_face_display_container")
	else:
		print("HUD _ready: dice_face_display_container (GridContainer) found.")
	# --- END DEBUG CHECK ---
	
	# Initialize history slot positions (as it was in Game.gd's _ready)
	roll_history_slot_positions = [
		Vector2(240, 480), Vector2(160, 480), Vector2(80, 480),
		Vector2(80, 400), Vector2(80, 320), Vector2(80, 240), Vector2(80, 160), Vector2(80, 80),
		Vector2(160, 80), Vector2(240, 80), Vector2(320, 80), Vector2(400, 80), Vector2(480, 80),
		Vector2(480, 160), Vector2(480, 240)
	]
	if roll_history_slot_positions.size() != MAX_VISUAL_HISTORY_SLOTS:
		printerr("HUD CRITICAL: roll_history_slot_positions size mismatch!")
	
	_initialize_visual_history_slots() # Renamed from _initialize_visual_history_display

	if is_instance_valid(inventory_toggle_button):
		inventory_toggle_button.pressed.connect(Callable(self, "_on_inventory_toggle_button_pressed"))
	
	if is_instance_valid(dice_face_scroll_container):
		dice_face_scroll_container.visible = false # Inventory starts hidden


# --- Public Functions for Game.gd to Call ---

func update_score_target_display(p_score: int, p_target: int):
	if is_instance_valid(score_label): score_label.text = "Score " + str(p_score)
	if is_instance_valid(target_label): target_label.text = "Target " + str(p_target)

func update_rolls_display(p_rolls_left: int, p_max_rolls_for_round: int):
	if is_instance_valid(rolls_label):
		rolls_label.text = "Rolls " + str(p_rolls_left) + "/" + str(p_max_rolls_for_round)

func update_level_display(p_level: int):
	if is_instance_valid(level_label): level_label.text = "Level " + str(p_level)

func update_last_rolled_glyph_display(glyph: GlyphData):
	if is_instance_valid(last_roll_display):
		if is_instance_valid(glyph) and is_instance_valid(glyph.texture):
			last_roll_display.texture = glyph.texture
		else:
			last_roll_display.texture = null

func show_synergy_message(full_message: String): # Renamed from display_synergy_activation_message_custom
	if is_instance_valid(synergy_notification_label) and not full_message.is_empty():
		synergy_notification_label.text = full_message
		var clear_timer = get_tree().create_timer(3.0)
		clear_timer.timeout.connect(Callable(synergy_notification_label, "set_text").bind("")) # Clear text after timeout

func update_dice_inventory_display(current_player_dice_array: Array[GlyphData]):
	if not is_instance_valid(dice_face_display_container):
		printerr("HUD: DiceFaceDisplayContainer (GridContainer) is not valid.")
		return

	for child in dice_face_display_container.get_children():
		child.queue_free()

	if current_player_dice_array.is_empty():
		var empty_label := Label.new()
		empty_label.text = "[No Faces]"
		dice_face_display_container.add_child(empty_label)
		return

	for glyph_data in current_player_dice_array:
		if not is_instance_valid(glyph_data):
			printerr("HUD: Invalid glyph_data found in current_player_dice_array.")
			continue
		var face_rect := TextureRect.new()
		face_rect.custom_minimum_size = Vector2(40, 40)
		face_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		face_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		face_rect.texture = glyph_data.texture
		face_rect.tooltip_text = glyph_data.display_name + " (Val: " + str(glyph_data.value) + ")"
		dice_face_display_container.add_child(face_rect)

func add_glyph_to_visual_history(glyph: GlyphData):
	if not is_instance_valid(roll_history_display_container): return
	if not is_instance_valid(glyph): return
		
	if current_visual_history_index < MAX_VISUAL_HISTORY_SLOTS and \
	   current_visual_history_index < roll_history_display_container.get_child_count():
		
		var history_item_node = roll_history_display_container.get_child(current_visual_history_index)
		if history_item_node is TextureRect:
			var item_rect := history_item_node as TextureRect
			item_rect.texture = glyph.texture
			item_rect.visible = true
		current_visual_history_index += 1
	elif current_visual_history_index >= MAX_VISUAL_HISTORY_SLOTS:
		# This print can be noisy, maybe remove or make it a debug flag
		# print("HUD: Visual history slots full.")
		pass


func reset_round_visuals():
	# Reset visual history track
	current_visual_history_index = 0
	if is_instance_valid(roll_history_display_container):
		for i in range(roll_history_display_container.get_child_count()):
			var child_node = roll_history_display_container.get_child(i)
			if child_node is TextureRect:
				var item_rect := child_node as TextureRect
				item_rect.visible = false
				item_rect.texture = null
	
	# Clear last rolled glyph display (the separate one, not on button)
	if is_instance_valid(last_roll_display):
		last_roll_display.texture = null
	
	# Clear synergy message
	if is_instance_valid(synergy_notification_label):
		synergy_notification_label.text = ""

	# Inventory display will be updated when toggled on or game starts
	# If inventory starts visible, you might want to call update_dice_inventory_display here too.


# --- Internal HUD Functions ---
func _initialize_visual_history_slots(): # Renamed
	if not is_instance_valid(roll_history_display_container):
		printerr("HUD: RollHistoryDisplayContainer not found!")
		return
	for child in roll_history_display_container.get_children():
		child.queue_free()
	for i in range(MAX_VISUAL_HISTORY_SLOTS):
		var history_item_rect := TextureRect.new()
		history_item_rect.custom_minimum_size = Vector2(80, 80)
		history_item_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		history_item_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if i < roll_history_slot_positions.size():
			history_item_rect.position = roll_history_slot_positions[i]
		else:
			history_item_rect.position = Vector2(-200, -200) # Hide off-screen
		history_item_rect.visible = false
		roll_history_display_container.add_child(history_item_rect)
	print("HUD: Visual history display initialized with ", roll_history_display_container.get_child_count(), " slots.")

func _on_inventory_toggle_button_pressed():
	if not is_instance_valid(dice_face_scroll_container):
		printerr("HUD: DiceFaceScrollContainer not found for toggle.")
		return
	dice_face_scroll_container.visible = not dice_face_scroll_container.visible
	if dice_face_scroll_container.visible:
		# Game.gd needs to pass current_player_dice to this HUD
		# This requires Game.gd to have a reference to HUD and call a method on it.
		# For now, this button is on the HUD, so it can call its own update method
		# if it had access to the dice data (which it doesn't directly yet).
		# This highlights the need for Game.gd to tell HUD to update.
		# Let's assume Game.gd will call hud.update_dice_inventory_display(current_player_dice)
		# when the inventory is toggled ON via a signal or direct call.
		# For now, we'll just print. The actual update will be triggered by Game.gd.
		print("HUD: Inventory toggled ON. Game.gd should refresh its content.")
	else:
		print("HUD: Inventory toggled OFF.")
