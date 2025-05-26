# res://scenes/ui_elements/PlaybackSpeedButton.gd

extends TextureButton

signal speed_changed(new_speed_multiplier: float)

const SPEED_OPTIONS: Array[float] = [1.0, 1.5, 2.0, 4.0, 8.0, 16.0, 0.5]
# @export var speed_textures: Array[Texture2D] = [] # Keep if you plan to use textures

var current_speed_index: int = 0

func _ready():
	pressed.connect(_on_button_pressed)
	_update_display()

func _on_button_pressed():
	current_speed_index = (current_speed_index + 1) % SPEED_OPTIONS.size()
	var new_speed = SPEED_OPTIONS[current_speed_index]
	emit_signal("speed_changed", new_speed)
	_update_display()
	print("PlaybackSpeedButton: Clicked! New speed index: ", current_speed_index, ", Speed: ", new_speed)

func _update_display():
	var current_speed_text = str(SPEED_OPTIONS[current_speed_index]) + "x"

	# Option 1: Change Texture (if you have different textures per speed)
	# if speed_textures.size() == SPEED_OPTIONS.size() and current_speed_index < speed_textures.size():
	#    if is_instance_valid(speed_textures[current_speed_index]):
	#        self.texture_normal = speed_textures[current_speed_index]
	#        # Optionally update texture_pressed, texture_hover, texture_disabled, texture_focused
	#        self.tooltip_text = "Speed: " + current_speed_text # Still good to have tooltip
	#        return # Texture updated, no need for label fallback if texture is primary
	#    else:
	#        print("PlaybackSpeedButton: Missing texture for speed index ", current_speed_index)
	# else:
	#    if not speed_textures.is_empty(): # Only print error if textures were expected
	#        print("PlaybackSpeedButton: speed_textures array size mismatch or not configured.")

	# Option 2: Update a child Label (Preferred if not using distinct textures for button itself)
	var label_node = get_node_or_null("Label") # Assuming child Label is named "Label"
	if is_instance_valid(label_node) and label_node is Label:
		label_node.text = current_speed_text
		self.tooltip_text = "Current Speed: " + current_speed_text # Update tooltip as well
	else:
		# Fallback for TextureButton if no child Label: Only tooltip can be updated directly for text.
		# If you *really* need text on the button itself without a child Label,
		# you'd have to dynamically generate a texture with the text drawn onto it,
		# which is much more complex.
		self.tooltip_text = "Speed: " + current_speed_text
		print("PlaybackSpeedButton: No child Label node found or it's not a Label. Updated tooltip only. Speed: ", SPEED_OPTIONS[current_speed_index])

func get_current_speed() -> float: # Getter for Game.gd
	return SPEED_OPTIONS[current_speed_index]

func set_current_speed(speed_value: float):
	var found_index = -1
	for i in range(SPEED_OPTIONS.size()):
		if abs(SPEED_OPTIONS[i] - speed_value) < 0.01:
			found_index = i
			break
	if found_index != -1:
		current_speed_index = found_index
		_update_display()
		# No need to emit speed_changed here, as this is for setting initial/loaded state
	else:
		printerr("PlaybackSpeedButton: Speed value ", speed_value, " not in options.")
