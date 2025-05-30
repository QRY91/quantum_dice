extends Button

@onready var preview_bg = $PreviewRect/Background
@onready var preview_main = $PreviewRect/MainColor
@onready var preview_accent = $PreviewRect/AccentColor
@onready var name_label = $NameLabel

var palette_id: StringName

func setup_from_info(palette_info: Dictionary):
	palette_id = palette_info.id
	name_label.text = palette_info.display_name
	
	# Update preview colors
	preview_bg.color = palette_info.background_color
	preview_main.color = palette_info.main_color
	preview_accent.color = palette_info.accent_color
	
	tooltip_text = "Switch to %s palette" % palette_info.display_name 