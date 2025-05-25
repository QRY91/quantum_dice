# res://scenes/ui/GameOverScreen.gd
# TABS FOR INDENTATION
extends Control

signal retry_pressed
signal main_menu_pressed

@onready var final_score_label: Label = $ScoreContainer/FinalScoreLabel # Adjust path if nested
@onready var level_reached_label: Label = $ScoreContainer/LevelReachedLabel # Adjust path
@onready var retry_button: Button = $ButtonsContainer/RetryButton # Adjust path
@onready var main_menu_button: Button = $ButtonsContainer/MainMenuButton # Adjust path

func _ready():
	hide() # Start hidden

	if is_instance_valid(retry_button):
		retry_button.pressed.connect(Callable(self, "_on_retry_button_pressed"))
	else:
		printerr("GameOverScreen: RetryButton not found!")
		
	if is_instance_valid(main_menu_button):
		main_menu_button.pressed.connect(Callable(self, "_on_main_menu_button_pressed"))
	else:
		printerr("GameOverScreen: MainMenuButton not found!")

func show_screen(final_score: int, level_reached: int):
	if is_instance_valid(final_score_label):
		final_score_label.text = "Final Score: " + str(final_score)
	if is_instance_valid(level_reached_label):
		level_reached_label.text = "Level Reached: " + str(level_reached)
	
	visible = true
	if is_instance_valid(retry_button): # Give focus for navigation
		retry_button.grab_focus()

func hide_screen():
	visible = false

func _on_retry_button_pressed():
	emit_signal("retry_pressed")
	hide_screen() # Hide self after emitting

func _on_main_menu_button_pressed():
	emit_signal("main_menu_pressed")
	hide_screen() # Hide self after emitting
