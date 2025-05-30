extends CanvasLayer

signal resume_pressed
signal settings_pressed
signal retry_pressed
signal quit_to_main_menu_pressed

@onready var resume_button = %ResumeButton
@onready var settings_button = %SettingsButton
@onready var retry_button = %RetryButton
@onready var quit_button = %QuitButton

func _ready():
	resume_button.pressed.connect(_on_resume_button_pressed)
	settings_button.pressed.connect(_on_settings_button_pressed)
	retry_button.pressed.connect(_on_retry_button_pressed)
	quit_button.pressed.connect(_on_quit_button_pressed)
	
	# The menu should not be visible by default, Game.gd will control visibility.
	hide()

func _on_resume_button_pressed():
	emit_signal("resume_pressed")
	hide()

func _on_settings_button_pressed():
	emit_signal("settings_pressed")
	# The menu itself doesn't hide here, Game.gd will manage showing/hiding Settings and this menu.

func _on_retry_button_pressed():
	emit_signal("retry_pressed")
	hide()

func _on_quit_button_pressed():
	emit_signal("quit_to_main_menu_pressed")
	hide()

func show_menu():
	show()
	# Ensure buttons are re-enabled in case they were disabled by settings screen
	resume_button.disabled = false
	settings_button.disabled = false
	retry_button.disabled = false
	quit_button.disabled = false


func hide_menu():
	hide()

# Called by Game.gd when settings are opened
func disable_buttons_for_settings():
	resume_button.disabled = true
	settings_button.disabled = true # Or hide this one specifically
	retry_button.disabled = true
	quit_button.disabled = true

# Called by Game.gd when settings are closed
func enable_buttons_after_settings():
	resume_button.disabled = false
	settings_button.disabled = false
	retry_button.disabled = false
	quit_button.disabled = false

func _unhandled_input(event: InputEvent):
	if event.is_action_pressed("ui_cancel") and visible: # "ui_cancel" is typically Escape
		_on_resume_button_pressed()
		get_viewport().set_input_as_handled() 
