# res://scenes/ui/LootScreen.gd
extends Control

signal loot_selected(chosen_glyph: GlyphData)
signal loot_screen_closed # If you add a cancel/skip option

@onready var title_label: Label = $TitleLabel
@onready var loot_options_container: HBoxContainer = $LootOptionsContainer
# @onready var help_label: Label = $HelpLabel # If you added it

var loot_glyphs_data: Array[GlyphData] = []
var selected_index: int = 0
var loot_option_buttons: Array[Button] = [] # To store references to created buttons

# Preload a scene for individual loot option buttons if you make one
# var loot_button_scene: PackedScene = preload("res://scenes/ui/LootOptionButton.tscn")


func _ready():
	hide() # Initially hidden, Game.gd will show it.
	# Ensure the container is empty if we're re-using the scene
	for child in loot_options_container.get_children():
		child.queue_free()


func display_loot_options(options: Array[GlyphData]):
	loot_glyphs_data = options
	selected_index = 0
	loot_option_buttons.clear()

	# Clear previous buttons if any
	for child in loot_options_container.get_children():
		child.queue_free()

	if loot_glyphs_data.is_empty():
		printerr("LootScreen: No loot options provided to display.")
		# Optionally, show a message and close, or emit a signal
		emit_signal("loot_screen_closed") 
		hide()
		return

	for i in range(loot_glyphs_data.size()):
		var glyph: GlyphData = loot_glyphs_data[i]
		var button := Button.new() # Create a new button programmatically
		button.text = glyph.display_name # Or use glyph.id or just icon
		button.icon = glyph.texture
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER # Or as desired
		button.expand_icon = true # Make icon scale with button
		button.custom_minimum_size = Vector2(80, 80) # Example size
		
		# Store index in button's metadata for easy retrieval
		button.set_meta("glyph_index", i) 
		button.pressed.connect(_on_loot_option_button_pressed.bind(button))

		loot_options_container.add_child(button)
		loot_option_buttons.append(button)

	_update_selection_visuals()
	show()
	# Optional: Grab focus for keyboard navigation
	if not loot_option_buttons.is_empty():
		loot_option_buttons[0].grab_focus()


func _unhandled_input(event: InputEvent): # event is still passed, but we use Input singleton for checks
	if not visible: 
		return

	if loot_glyphs_data.is_empty():
		if Input.is_action_just_pressed("cancel_action"): # Use Input singleton
			print("LootScreen: Cancelled/Closed (no loot options).")
			emit_signal("loot_screen_closed")
			hide()
			get_viewport().set_input_as_handled()
		return

	if Input.is_action_just_pressed("navigate_left"): # Use Input singleton
		selected_index = (selected_index - 1 + loot_glyphs_data.size()) % loot_glyphs_data.size()
		_update_selection_visuals()
		get_viewport().set_input_as_handled()
	elif Input.is_action_just_pressed("navigate_right"): # Use Input singleton
		selected_index = (selected_index + 1) % loot_glyphs_data.size()
		_update_selection_visuals()
		get_viewport().set_input_as_handled()
	elif Input.is_action_just_pressed("confirm_action"): # Use Input singleton
		if selected_index >= 0 and selected_index < loot_glyphs_data.size():
			var chosen_glyph = loot_glyphs_data[selected_index]
			print("LootScreen: Confirmed selection - ", chosen_glyph.display_name)
			emit_signal("loot_selected", chosen_glyph)
			hide()
			get_viewport().set_input_as_handled()
	elif Input.is_action_just_pressed("cancel_action"): # Use Input singleton
		print("LootScreen: Cancelled/Closed by player.")
		emit_signal("loot_screen_closed")
		hide()
		get_viewport().set_input_as_handled()


func _on_loot_option_button_pressed(button_node: Button):
	var index = button_node.get_meta("glyph_index")
	if index != null and index >= 0 and index < loot_glyphs_data.size():
		selected_index = index
		var chosen_glyph = loot_glyphs_data[selected_index]
		print("LootScreen: Button clicked for - ", chosen_glyph.display_name)
		emit_signal("loot_selected", chosen_glyph)
		hide()


func _update_selection_visuals():
	# Example: visually indicate the selected button
	# This is basic; you might use tweens, borders, or a separate cursor sprite
	for i in range(loot_option_buttons.size()):
		var button = loot_option_buttons[i]
		if i == selected_index:
			button.modulate = Color(1.2, 1.2, 0.8) # Highlight: slightly brighter/yellowish
			button.grab_focus() # Ensure the selected button has focus for confirm
		else:
			button.modulate = Color.WHITE # Normal
	# print("Selected loot index: ", selected_index)

