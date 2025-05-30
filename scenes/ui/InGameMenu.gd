extends CanvasLayer

signal resume_pressed
signal settings_pressed
signal retry_pressed
signal quit_to_main_menu_pressed

@onready var resume_button = $Control/CenterContainer/Panel/VBoxContainer/ResumeButton
@onready var settings_button = $Control/CenterContainer/Panel/VBoxContainer/SettingsButton
@onready var retry_button = $Control/CenterContainer/Panel/VBoxContainer/RetryButton
@onready var quit_button = $Control/CenterContainer/Panel/VBoxContainer/QuitButton

func _ready():
	print("InGameMenu: _ready() START")
	if not is_instance_valid(resume_button):
		printerr("InGameMenu: ResumeButton not found at path: Control/CenterContainer/Panel/VBoxContainer/ResumeButton")
	if not is_instance_valid(settings_button):
		printerr("InGameMenu: SettingsButton not found at path: Control/CenterContainer/Panel/VBoxContainer/SettingsButton")
	if not is_instance_valid(retry_button):
		printerr("InGameMenu: RetryButton not found at path: Control/CenterContainer/Panel/VBoxContainer/RetryButton")
	if not is_instance_valid(quit_button):
		printerr("InGameMenu: QuitButton not found at path: Control/CenterContainer/Panel/VBoxContainer/QuitButton")
		
	if is_instance_valid(resume_button): resume_button.pressed.connect(_on_resume_button_pressed)
	if is_instance_valid(settings_button): settings_button.pressed.connect(_on_settings_button_pressed)
	if is_instance_valid(retry_button): retry_button.pressed.connect(_on_retry_button_pressed)
	if is_instance_valid(quit_button): quit_button.pressed.connect(_on_quit_button_pressed)
	
	# The menu should not be visible by default, Game.gd will control visibility.
	hide()
	print("InGameMenu: _ready() END")

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
	if is_instance_valid(resume_button): resume_button.disabled = false
	if is_instance_valid(settings_button): settings_button.disabled = false
	if is_instance_valid(retry_button): retry_button.disabled = false
	if is_instance_valid(quit_button): quit_button.disabled = false

func hide_menu():
	hide()

# Called by Game.gd when settings are opened
func disable_buttons_for_settings():
	if is_instance_valid(resume_button): resume_button.disabled = true
	if is_instance_valid(settings_button): settings_button.disabled = true
	if is_instance_valid(retry_button): retry_button.disabled = true
	if is_instance_valid(quit_button): quit_button.disabled = true

# Called by Game.gd when settings are closed
func enable_buttons_after_settings():
	if is_instance_valid(resume_button): resume_button.disabled = false
	if is_instance_valid(settings_button): settings_button.disabled = false
	if is_instance_valid(retry_button): retry_button.disabled = false
	if is_instance_valid(quit_button): quit_button.disabled = false

func _unhandled_input(event: InputEvent):
	if event.is_action_pressed("ui_cancel") and visible: # "ui_cancel" is typically Escape
		_on_resume_button_pressed()
		get_viewport().set_input_as_handled() 
