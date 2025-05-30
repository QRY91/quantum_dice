extends Control

signal back_pressed

@onready var music_slider = %MusicSlider
@onready var sfx_slider = %SFXSlider
@onready var music_toggle = %MusicToggle
@onready var sfx_toggle = %SFXToggle
@onready var palette_button = %PaletteButton
@onready var ambient_sound_button = %AmbientSoundButton
@onready var back_button = %BackButton
@onready var settings_panel = $Panel

var palette_swapper_scene = preload("res://scenes/ui/palette_swapper.tscn")
var ambient_sound_panel_scene = preload("res://scenes/ui/AmbientSoundPanel.tscn")
var palette_swapper: Control
var ambient_sound_panel: Control

# Track if we're opened from the main menu (where we don't want to pause)
var opened_from_main_menu: bool = false

func _ready():
	# Set process mode to handle input while game is paused
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Connect signals
	music_slider.value_changed.connect(_on_music_volume_changed)
	sfx_slider.value_changed.connect(_on_sfx_volume_changed)
	music_toggle.toggled.connect(_on_music_toggled)
	sfx_toggle.toggled.connect(_on_sfx_toggled)
	palette_button.pressed.connect(_on_palette_button_pressed)
	ambient_sound_button.pressed.connect(_on_ambient_sound_button_pressed)
	back_button.pressed.connect(_on_back_button_pressed)
	
	# Initialize values from AudioManager
	music_slider.value = AudioManager.music_volume
	sfx_slider.value = AudioManager.sfx_volume
	music_toggle.button_pressed = AudioManager.music_enabled
	sfx_toggle.button_pressed = AudioManager.sfx_enabled
	
	# Hide on start
	hide_menu()

func _on_music_volume_changed(value: float):
	AudioManager.set_music_volume(value)

func _on_sfx_volume_changed(value: float):
	AudioManager.set_sfx_volume(value)

func _on_music_toggled(enabled: bool):
	AudioManager.toggle_music(enabled)

func _on_sfx_toggled(enabled: bool):
	AudioManager.toggle_sfx(enabled)

func _on_palette_button_pressed():
	if not palette_swapper:
		palette_swapper = palette_swapper_scene.instantiate()
		add_child(palette_swapper)
		palette_swapper.back_pressed.connect(_on_palette_swapper_back)
	palette_swapper.show()
	# Hide the settings menu panel but keep the script running
	settings_panel.hide()

func _on_ambient_sound_button_pressed():
	if not ambient_sound_panel:
		ambient_sound_panel = ambient_sound_panel_scene.instantiate()
		add_child(ambient_sound_panel)
		ambient_sound_panel.back_pressed.connect(_on_ambient_sound_panel_back)
		# Make it smaller and center it
		ambient_sound_panel.custom_minimum_size = Vector2(500, 600)
		ambient_sound_panel.position = Vector2(
			(get_viewport_rect().size.x - ambient_sound_panel.custom_minimum_size.x) / 2,
			(get_viewport_rect().size.y - ambient_sound_panel.custom_minimum_size.y) / 2
		)
	ambient_sound_panel.show()
	# Hide the settings menu panel but keep the script running
	settings_panel.hide()

func _on_palette_swapper_back():
	if palette_swapper:
		palette_swapper.hide()
	settings_panel.show()

func _on_ambient_sound_panel_back():
	if ambient_sound_panel:
		ambient_sound_panel.hide()
	settings_panel.show()

func _on_back_button_pressed():
	emit_signal("back_pressed")

func show_menu(from_main_menu: bool = false):
	opened_from_main_menu = from_main_menu
	get_parent().show() # Show CanvasLayer
	show() # Show Control
	settings_panel.show()
	if palette_swapper:
		palette_swapper.hide()
	if ambient_sound_panel:
		ambient_sound_panel.hide()
	
	# Only pause if not opened from main menu
	if not opened_from_main_menu:
		get_tree().paused = true

func hide_menu():
	get_parent().hide() # Hide CanvasLayer
	hide() # Hide Control
	if palette_swapper:
		palette_swapper.hide()
	if ambient_sound_panel:
		ambient_sound_panel.hide()
	
	# Only unpause if we weren't opened from main menu
	if not opened_from_main_menu:
		get_tree().paused = false

func _input(event: InputEvent):
	if not visible:
		return

	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		
		if is_instance_valid(palette_swapper) and palette_swapper.visible:
			_on_palette_swapper_back()
			return

		if is_instance_valid(ambient_sound_panel) and ambient_sound_panel.visible:
			_on_ambient_sound_panel_back()
			return
		
		# If no sub-panel handled it, then trigger the main settings back action
		_on_back_button_pressed() 
