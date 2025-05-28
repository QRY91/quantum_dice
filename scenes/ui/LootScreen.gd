# res://scenes/ui/LootScreen.gd
extends Control

signal loot_selected(chosen_glyph: GlyphData)
# loot_screen_closed is kept for general closure,
# but "cancel_action" will now use skip_loot_pressed
signal loot_screen_closed 
signal skip_loot_pressed
signal request_inventory_panel_show # New signal for inventory

@onready var title_label: Label = $TitleLabel
@onready var loot_options_container: HBoxContainer = $LootOptionsContainer
@onready var skip_button: TextureButton = $SkipButton
@onready var inventory_toggle_button: TextureButton = $InventoryToggleButton

var loot_glyphs_data: Array[GlyphData] = []
var selected_index: int = 0
var loot_option_buttons: Array[Button] = []

func _ready():
	if is_instance_valid(skip_button):
		skip_button.pressed.connect(_on_internal_skip_button_pressed)
	else:
		printerr("LootScreen: SkipButton node not found!")
	
	if is_instance_valid(inventory_toggle_button):
		inventory_toggle_button.pressed.connect(_on_inventory_toggle_button_pressed)
	else:
		printerr("LootScreen: InventoryToggleButton node not found!")
		
	hide() 
	for child in loot_options_container.get_children():
		child.queue_free()


func display_loot_options(options: Array[GlyphData]):
	loot_glyphs_data = options
	selected_index = 0
	loot_option_buttons.clear()

	for child in loot_options_container.get_children():
		child.queue_free()

	if loot_glyphs_data.is_empty():
		printerr("LootScreen: No loot options provided to display.")
		emit_signal("skip_loot_pressed") # Or loot_screen_closed if skipping isn't appropriate
		hide()
		return

	for i in range(loot_glyphs_data.size()):
		var glyph: GlyphData = loot_glyphs_data[i]
		var button := Button.new()
		button.text = glyph.display_name
		button.icon = glyph.texture
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.expand_icon = true
		button.custom_minimum_size = Vector2(80, 80) # Ensure this is large enough for visibility
		
		button.set_meta("glyph_index", i) 
		button.pressed.connect(_on_loot_option_button_pressed.bind(button))

		loot_options_container.add_child(button)
		loot_option_buttons.append(button)

	# Make inventory button visible only when options are displayed
	if is_instance_valid(inventory_toggle_button):
		inventory_toggle_button.visible = true
		
	_update_selection_visuals()
	show()
	if not loot_option_buttons.is_empty():
		loot_option_buttons[0].grab_focus()


func _unhandled_input(event: InputEvent):
	if not visible: 
		return

	# If inventory panel is active (assuming SceneUIManager or Game manages this state),
	# LootScreen might not process further input to avoid conflicts.
	# This part requires knowing how inventory panel blocks input, or if it does.
	# For now, we assume LootScreen still processes input unless inventory is modal.

	if Input.is_action_just_pressed("cancel_action"):
		# Check if an inventory panel is open and should be closed first.
		# This logic might be better handled in Game.gd or SceneUIManager if inventory is global.
		# For now, pressing Escape on LootScreen will act as "skip loot".
		print("LootScreen: 'cancel_action' pressed, emitting skip_loot_pressed.")
		emit_signal("skip_loot_pressed")
		_cleanup_and_hide() # Consolidate hiding logic
		get_viewport().set_input_as_handled()
		return # Important: return after handling cancel

	if loot_glyphs_data.is_empty(): # Should ideally not happen if cancel is handled above
		return

	if Input.is_action_just_pressed("navigate_left"):
		selected_index = (selected_index - 1 + loot_glyphs_data.size()) % loot_glyphs_data.size()
		_update_selection_visuals()
		get_viewport().set_input_as_handled()
	elif Input.is_action_just_pressed("navigate_right"):
		selected_index = (selected_index + 1) % loot_glyphs_data.size()
		_update_selection_visuals()
		get_viewport().set_input_as_handled()
	elif Input.is_action_just_pressed("confirm_action"):
		if selected_index >= 0 and selected_index < loot_glyphs_data.size():
			var chosen_glyph = loot_glyphs_data[selected_index]
			print("LootScreen: Confirmed selection - ", chosen_glyph.display_name)
			emit_signal("loot_selected", chosen_glyph)
			_cleanup_and_hide()
			get_viewport().set_input_as_handled()


func _on_loot_option_button_pressed(button_node: Button):
	var index = button_node.get_meta("glyph_index")
	if index != null and index >= 0 and index < loot_glyphs_data.size():
		selected_index = index
		var chosen_glyph = loot_glyphs_data[selected_index]
		print("LootScreen: Button clicked for - ", chosen_glyph.display_name)
		emit_signal("loot_selected", chosen_glyph)
		_cleanup_and_hide()
		# get_viewport().set_input_as_handled() # Already handled by _unhandled_input if confirm_action

func _update_selection_visuals():
	for i in range(loot_option_buttons.size()):
		var button = loot_option_buttons[i]
		if i == selected_index:
			button.modulate = Color(1.2, 1.2, 0.8)
			button.grab_focus()
		else:
			button.modulate = Color.WHITE

func _on_internal_skip_button_pressed():
	print("LootScreen: Skip button pressed, emitting skip_loot_pressed signal.")
	emit_signal("skip_loot_pressed")
	_cleanup_and_hide()

func _on_inventory_toggle_button_pressed():
	print("LootScreen: Inventory toggle button pressed.")
	emit_signal("request_inventory_panel_show")
	# The loot screen itself remains open. Game.gd will show the inventory panel.

func _cleanup_and_hide():
	# Hide inventory button when loot screen is about to hide
	if is_instance_valid(inventory_toggle_button):
		inventory_toggle_button.visible = false
	hide()
	# Optionally emit loot_screen_closed if other systems need a generic close signal
	# emit_signal("loot_screen_closed") # Game.gd's _on_loot_screen_closed might still be useful for generic cleanup
