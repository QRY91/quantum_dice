# res://scenes/ui/MainMenu.gd
# TABS
extends Control

signal start_game_pressed

@onready var start_button: Button = $StartButton 
@onready var high_score_label: Label = $HighScoreLabel # Add this @onready var

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
		start_button.grab_focus()
	
	# Assuming Game node is always at /root/Game
	var game_node = get_node_or_null("/root/Game")
	if is_instance_valid(game_node) and is_instance_valid(high_score_label):
		high_score_label.text = "High Score: " + str(game_node.high_score)
	elif is_instance_valid(high_score_label):
		high_score_label.text = "High Score: N/A"
		
	print("MainMenu: show_menu() called.")

func hide_menu():
	visible = false
	print("MainMenu: hide_menu() called.")
