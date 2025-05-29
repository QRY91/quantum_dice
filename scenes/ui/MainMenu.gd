# res://scenes/ui/MainMenu.gd
# TABS
extends Control

signal start_game_pressed

@onready var start_button: Button = $StartButton 
@onready var high_score_label: Label = $HighScoreLabel
@onready var title_label: Label = $TitleLabel
@onready var background_rect: ColorRect = $BackgroundRect

var title_original_pos: Vector2
var title_animation_time: float = 0.0
const TITLE_FLOAT_SPEED: float = 1.0
const TITLE_FLOAT_AMOUNT: float = 10.0

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

	# Store original title position for animation
	if is_instance_valid(title_label):
		title_original_pos = title_label.position
	
	# Set up background shader with palette colors
	if is_instance_valid(background_rect) and background_rect.material:
		_update_shader_colors()
	
	# Connect to palette manager for color updates
	if PaletteManager:
		PaletteManager.active_palette_updated.connect(_on_palette_changed)

func _process(delta: float):
	if is_instance_valid(title_label):
		title_animation_time += delta
		
		# Gentle floating animation
		var float_offset = sin(title_animation_time * TITLE_FLOAT_SPEED) * TITLE_FLOAT_AMOUNT
		title_label.position = title_original_pos + Vector2(0, float_offset)
		
		# Subtle scale pulse
		var scale_pulse = 1.0 + sin(title_animation_time * 0.8) * 0.02
		title_label.scale = Vector2(scale_pulse, scale_pulse)

func _on_start_button_pressed():
	emit_signal("start_game_pressed")
	print("MainMenu: Start Game button pressed, emitting signal.")

func show_menu():
	visible = true
	if is_instance_valid(start_button):
		start_button.grab_focus()
	
	_update_high_score_display() # Update when shown
	_update_shader_colors() # Ensure colors are current
		
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

func _update_shader_colors():
	if not is_instance_valid(background_rect) or not background_rect.material:
		return
		
	if PaletteManager:
		var colors = PaletteManager.get_current_palette_colors()
		background_rect.material.set_shader_parameter("background_color", colors.background)
		background_rect.material.set_shader_parameter("foreground_color", colors.main)

func _on_palette_changed(_colors: Dictionary):
	_update_shader_colors()
