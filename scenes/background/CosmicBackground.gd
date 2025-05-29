extends Control

@onready var background_rect: ColorRect = $BackgroundRect

func _ready():
	print("CosmicBackground _ready: Node Name: ", name)
	print("CosmicBackground _ready: Is Visible in Tree: ", is_visible_in_tree())
	print("CosmicBackground _ready: Global Position: ", global_position)
	print("CosmicBackground _ready: Own Size: ", size)
	if is_instance_valid(background_rect):
		print("CosmicBackground _ready: BackgroundRect Size: ", background_rect.size)
		print("CosmicBackground _ready: BackgroundRect GlobalPosition: ", background_rect.global_position)
		print("CosmicBackground _ready: BackgroundRect Anchors: Left: %s, Top: %s, Right: %s, Bottom: %s" % [background_rect.anchor_left, background_rect.anchor_top, background_rect.anchor_right, background_rect.anchor_bottom])
		print("CosmicBackground _ready: BackgroundRect Offsets: Left: %s, Top: %s, Right: %s, Bottom: %s" % [background_rect.offset_left, background_rect.offset_top, background_rect.offset_right, background_rect.offset_bottom])
		print("CosmicBackground _ready: BackgroundRect LayoutMode: ", background_rect.layout_mode)
		
		# Add shader material debug info
		if background_rect.material is ShaderMaterial:
			var mat: ShaderMaterial = background_rect.material
			print("CosmicBackground _ready: ShaderMaterial Info:")
			print("  - Has Shader: ", mat.shader != null)
			print("  - Shader Parameters:")
			print("    * background_color: ", mat.get_shader_parameter("background_color"))
			print("    * foreground_color: ", mat.get_shader_parameter("foreground_color"))
			print("    * pulse_intensity: ", mat.get_shader_parameter("pulse_intensity"))
			print("    * pulse_speed: ", mat.get_shader_parameter("pulse_speed"))
		else:
			printerr("CosmicBackground _ready: BackgroundRect material is not a ShaderMaterial!")

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
			print("CosmicBackground _ready: Applied fallback colors - BG: ", fallback_bg, " FG: ", fallback_fg)

func _process(_delta):
	if is_instance_valid(background_rect) and background_rect.material is ShaderMaterial:
		var mat: ShaderMaterial = background_rect.material
		if mat.shader:
			var current_bg = mat.get_shader_parameter("background_color")
			var current_fg = mat.get_shader_parameter("foreground_color")
			if current_bg != null and current_fg != null:
				# Uncomment for continuous color monitoring (might be noisy)
				# print("CosmicBackground current colors - BG: ", current_bg, " FG: ", current_fg)
				pass

func _on_palette_changed(palette_colors: Dictionary) -> void:
	print("CosmicBackground _on_palette_changed: Received colors: ", palette_colors)
	if not is_instance_valid(background_rect) or not background_rect.material is ShaderMaterial:
		printerr("CosmicBackground: BackgroundRect material is not a ShaderMaterial, cannot apply palette.")
		return

	var mat: ShaderMaterial = background_rect.material
	var bg_color = palette_colors.get("background", Color(0.02, 0.01, 0.04, 1.0))
	var fg_color = palette_colors.get("main", Color(0.93, 0.87, 0.8, 1.0))
	
	mat.set_shader_parameter("background_color", bg_color)
	mat.set_shader_parameter("foreground_color", fg_color)
	
	if mat:
		print("CosmicBackground _on_palette_changed: Applied colors:")
		print("  * background_color: ", mat.get_shader_parameter("background_color"))
		print("  * foreground_color: ", mat.get_shader_parameter("foreground_color"))
		print("  * pulse_intensity: ", mat.get_shader_parameter("pulse_intensity"))
		print("  * pulse_speed: ", mat.get_shader_parameter("pulse_speed"))

func _exit_tree():
	if PaletteManager and PaletteManager.is_connected("active_palette_updated", Callable(self, "_on_palette_changed")):
		PaletteManager.active_palette_updated.disconnect(_on_palette_changed) 
