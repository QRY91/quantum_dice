extends Control

@onready var background_rect: ColorRect = $BackgroundRect

func _ready():
	if not is_instance_valid(background_rect):
		printerr("CosmicBackground: BackgroundRect node not found!")
		return

	if PaletteManager:
		PaletteManager.active_palette_updated.connect(_on_palette_changed)
		# Apply initial palette
		_on_palette_changed(PaletteManager.get_current_palette_colors())
	else:
		printerr("CosmicBackground: PaletteManager not found.")
		# Fallback colors if PaletteManager is missing
		if background_rect.material is ShaderMaterial:
			var mat: ShaderMaterial = background_rect.material
			var fallback_bg = Color(0.02, 0.01, 0.04, 1.0)
			var fallback_fg = Color(0.93, 0.87, 0.8, 1.0)
			mat.set_shader_parameter("background_color", fallback_bg)
			mat.set_shader_parameter("foreground_color", fallback_fg)

func _on_palette_changed(palette_colors: Dictionary) -> void:
	if not is_instance_valid(background_rect) or not background_rect.material is ShaderMaterial:
		return

	var mat: ShaderMaterial = background_rect.material
	var bg_color = palette_colors.get("background", Color(0.02, 0.01, 0.04, 1.0))
	var fg_color = palette_colors.get("main", Color(0.93, 0.87, 0.8, 1.0))
	
	mat.set_shader_parameter("background_color", bg_color)
	mat.set_shader_parameter("foreground_color", fg_color)

func _exit_tree():
	if PaletteManager and PaletteManager.is_connected("active_palette_updated", Callable(self, "_on_palette_changed")):
		PaletteManager.active_palette_updated.disconnect(_on_palette_changed) 
