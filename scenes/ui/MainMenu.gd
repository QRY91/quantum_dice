# res://scenes/ui/MainMenu.gd
# TABS
extends Control

signal start_game_pressed

@onready var start_button: Button = $StartButton 
@onready var high_score_label: Label = $HighScoreLabel

func _ready():
	if is_instance_valid(start_button):
		start_button.pressed.connect(Callable(self, "_on_start_button_pressed"))
	else:
		printerr("MainMenu.gd: StartButton node not found!")

	# Connect to ScoreManager's signal to update high score if it changes while menu is visible
	if ScoreManager.has_signal("high_score_updated"):
		ScoreManager.high_score_updated.connect(Callable(self, "_on_high_score_updated"))
	
	# Initial display of high score
	_update_high_score_display()


func _on_start_button_pressed():
	emit_signal("start_game_pressed")
	print("MainMenu: Start Game button pressed, emitting signal.")

func show_menu():
	visible = true
	if is_instance_valid(start_button):
		start_button.grab_focus()
	
	_update_high_score_display() # Update when shown
		
	print("MainMenu: show_menu() called.")

func hide_menu():
	visible = false
	print("MainMenu: hide_menu() called.")

func _update_high_score_display():
	if is_instance_valid(high_score_label):
		# Get high score from ScoreManager Autoload
		if ScoreManager: # Check if ScoreManager Autoload is available
			high_score_label.text = "High Score: " + str(ScoreManager.get_high_score())
		else:
			high_score_label.text = "High Score: Error" # Should not happen if Autoload is set up
			printerr("MainMenu: ScoreManager Autoload not found!")
	elif not is_instance_valid(high_score_label):
		printerr("MainMenu: high_score_label node not found!")

func _on_high_score_updated(new_high_score: int):
	# This function is called if ScoreManager emits its high_score_updated signal
	print("MainMenu: Received high_score_updated signal. New high score: ", new_high_score)
	if is_instance_valid(high_score_label):
		high_score_label.text = "High Score: " + str(new_high_score)
