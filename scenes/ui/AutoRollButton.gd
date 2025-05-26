# res://scenes/ui/AutoRollButton.gd
extends TextureButton

signal auto_roll_toggled(is_enabled: bool)

# REMOVE: @onready var state_label: Label = $StateLabel
# We will use textures instead of the label. Delete the StateLabel node from AutoRollButton.tscn as well.

var is_auto_rolling: bool = false

# Add these in the Inspector for your AutoRollButton scene
@export var texture_auto_on: Texture2D
@export var texture_auto_off: Texture2D

func _ready():
	pressed.connect(_on_button_pressed)
	_update_display()

func _on_button_pressed():
	is_auto_rolling = not is_auto_rolling
	emit_signal("auto_roll_toggled", is_auto_rolling)
	_update_display()
	print("AutoRollButton: Clicked! Auto-roll now: ", "ON" if is_auto_rolling else "OFF")

func _update_display():
	if is_auto_rolling:
		if is_instance_valid(texture_auto_on):
			self.texture_normal = texture_auto_on
		else:
			printerr("AutoRollButton: texture_auto_on not set!")
		tooltip_text = "Auto-Roll: ON (Click to turn OFF)"
	else:
		if is_instance_valid(texture_auto_off):
			self.texture_normal = texture_auto_off
		else:
			printerr("AutoRollButton: texture_auto_off not set!")
		tooltip_text = "Auto-Roll: OFF (Click to turn ON)"
	
	# If you have hover/pressed states for these textures, set them too:
	# self.texture_hover = ...
	# self.texture_pressed = ...

func set_auto_roll_state(enable: bool):
	if is_auto_rolling != enable:
		is_auto_rolling = enable
		_update_display()
		print("AutoRollButton: State set externally to: ", "ON" if is_auto_rolling else "OFF")

func get_current_state() -> bool:
	return is_auto_rolling
