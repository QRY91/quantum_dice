# res://scenes/ui/LootScreen.gd
extends Control

signal loot_selected(chosen_glyph: GlyphData)
signal loot_screen_closed 
signal skip_loot_pressed
signal request_inventory_panel_show

@onready var title_label: Label = $TitleLabel
@onready var loot_options_container: HBoxContainer = $LootOptionsContainer
@onready var skip_button: TextureButton = $SkipButton
@onready var inventory_toggle_button: TextureButton = $InventoryToggleButton

var loot_glyphs_data: Array[GlyphData] = []
var selected_index: int = 0
var loot_option_buttons: Array[Button] = [] # Still stores the main clickable button for each option

# --- Configuration for Loot Option Display ---
const LOOT_OPTION_SIZE: Vector2 = Vector2(160, 160) # Desired size for each loot item
const LOOT_ICON_MAX_SIZE: Vector2 = Vector2(100, 100) # Max size for the icon within the button
# Increased label height to potentially accommodate two lines of wrapped text
const LOOT_LABEL_MIN_HEIGHT: float = 45.0 # Min height for the label area
const LOOT_LABEL_FONT_SIZE: int = 18 # Example font size for loot labels
# New: Minimum display size for the icon itself
const LOOT_ICON_TARGET_MIN_DISPLAY_SIZE: Vector2 = Vector2(40, 40) 
# Max size for the icon (if it were larger than this, it would scale down)
const LOOT_ICON_MAX_BOUNDS_SIZE: Vector2 = Vector2(100, 100) # e.g. Max area icon can take

func _ready():
	if is_instance_valid(skip_button):
		skip_button.pressed.connect(_on_internal_skip_button_pressed)
	else:
		printerr("LootScreen: SkipButton node not found!")
	
	if is_instance_valid(inventory_toggle_button):
		inventory_toggle_button.pressed.connect(_on_inventory_toggle_button_pressed)
	else:
		printerr("LootScreen: InventoryToggleButton node not found!")
		
	if is_instance_valid(loot_options_container):
		# Example: Add some separation between loot items in the HBoxContainer
		loot_options_container.add_theme_constant_override("separation", 20)
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
		emit_signal("skip_loot_pressed")
		hide()
		return

	# Adjust LootOptionsContainer properties if needed
	# Example: Ensure it's centered and has some spacing
	# loot_options_container.alignment = HBoxContainer.ALIGNMENT_CENTER # Already set in .tscn
	# loot_options_container.add_theme_constant_override("separation", 20) # Add space between items

	for i in range(loot_glyphs_data.size()):
		var glyph: GlyphData = loot_glyphs_data[i]

		var option_button_container := Button.new()
		option_button_container.custom_minimum_size = LOOT_OPTION_SIZE
		option_button_container.size = LOOT_OPTION_SIZE 
		option_button_container.clip_text = true
		option_button_container.text = "" 

		var vbox := VBoxContainer.new()
		vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
		vbox.mouse_filter = Control.MOUSE_FILTER_PASS # Already set, good.
		option_button_container.add_child(vbox)

		# 1. Label for the glyph name
		var name_label := Label.new()
		name_label.text = glyph.display_name
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_label.clip_text = true
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.custom_minimum_size = Vector2(0, LOOT_LABEL_MIN_HEIGHT) 
		name_label.mouse_filter = Control.MOUSE_FILTER_PASS # Also set for label
		
		if name_label.has_theme_font("font"):
			name_label.add_theme_font_size_override("font_size", LOOT_LABEL_FONT_SIZE)
		
		vbox.add_child(name_label)

		# 2. Container for the Icon
		var icon_container := Control.new()
		icon_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		icon_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
		icon_container.custom_minimum_size = LOOT_ICON_TARGET_MIN_DISPLAY_SIZE
		icon_container.mouse_filter = Control.MOUSE_FILTER_PASS # <<< ADD THIS LINE
		vbox.add_child(icon_container)
		
		# 3. TextureRect for the glyph icon
		var icon_rect := TextureRect.new()
		icon_rect.texture = glyph.texture
		icon_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL 
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon_rect.mouse_filter = Control.MOUSE_FILTER_PASS # <<< ADD THIS LINE (or ensure it inherits PASS)
		icon_container.add_child(icon_rect)
		
		option_button_container.set_meta("glyph_index", i) 
		option_button_container.pressed.connect(_on_loot_option_button_pressed.bind(option_button_container))

		loot_options_container.add_child(option_button_container)
		loot_option_buttons.append(option_button_container)

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
