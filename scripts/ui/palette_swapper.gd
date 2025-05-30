extends Control

signal back_pressed

@onready var palette_container = $VBoxContainer/ScrollContainer/PaletteContainer
@onready var palette_button_group = ButtonGroup.new()
@onready var back_button = %BackButton

var palette_button_scene = preload("res://scenes/ui/palette_button.tscn")

func _ready():
	back_button.pressed.connect(_on_back_button_pressed)
	load_palettes()
	
func load_palettes():
	# Clear existing buttons
	for child in palette_container.get_children():
		child.queue_free()
	
	# Get all displayable (unlocked) palettes from the PaletteManager
	var palettes = PaletteManager.get_all_displayable_palettes()
	for palette_info in palettes:
		add_palette_button(palette_info)

func add_palette_button(palette_info: Dictionary):
	var button = palette_button_scene.instantiate()
	palette_container.add_child(button)
	button.setup_from_info(palette_info)
	button.button_group = palette_button_group
	button.pressed.connect(_on_palette_button_pressed.bind(palette_info.id))
	
	# Select the current palette if it matches
	if PaletteManager.current_user_palette_id == palette_info.id:
		button.button_pressed = true

func _on_palette_button_pressed(palette_id: StringName):
	PaletteManager.set_user_palette(palette_id)

func _on_back_button_pressed():
	emit_signal("back_pressed") 
