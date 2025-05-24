# res://scenes/ui/MainMenu.gd
# TABS
extends Control

signal start_game_pressed

@onready var start_button: Button = $StartButton 

func _ready():
	if is_instance_valid(start_button):
		start_button.pressed.connect(Callable(self, "_on_start_button_pressed"))
	else:
		printerr("MainMenu.gd: StartButton node not found!")

func _on_start_button_pressed():
	emit_signal("start_game_pressed")
	print("MainMenu: Start Game button pressed, emitting signal.")

func show_menu():
	visible = true
	if is_instance_valid(start_button):
		start_button.grab_focus() # This is key for keyboard/controller, helps with mouse too
	print("MainMenu: show_menu() called.")

func hide_menu():
	visible = false
	print("MainMenu: hide_menu() called.")
