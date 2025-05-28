# res://scripts/palette/PalettizedItem.gd
# Attach this script to any CanvasItem node that uses a ShaderMaterial
# with the palette_swap.gdshader.
# Ensure the ShaderMaterial's "Source Placeholder" uniforms are correctly
# configured for the specific art asset used by this node.
# For example, for 1-bit white-on-transparent Kenney assets,
# Source Placeholder Main should be WHITE.

extends CanvasItem # Base class for 2D rendering and UI

# If true, the script will attempt to duplicate the material on _ready.
# Set to false if you are managing material instances externally or if multiple
# nodes are INTENDED to share the exact same material instance (less common for palette swapping).
@export var duplicate_material_on_ready: bool = true

# Optional: If you want to force a specific shader, you can export it.
# However, it's generally better to assign the ShaderMaterial in the editor.
# @export var palette_swap_shader: Shader # preload("res://palette_swap.gdshader")

var shader_material_instance: ShaderMaterial = null

func _ready():
	# Attempt to get the material. It must be a ShaderMaterial.
	if material is ShaderMaterial:
		if duplicate_material_on_ready:
			# Duplicate the material to ensure this node has its own instance
			# for individual uniform updates, preventing unintended sharing.
			shader_material_instance = material.duplicate() as ShaderMaterial
			material = shader_material_instance # Assign the duplicated material back to the node
			if not is_instance_valid(shader_material_instance):
				printerr("Node '%s': Failed to duplicate ShaderMaterial." % name)
				return # Cannot proceed without a valid material instance
		else:
			shader_material_instance = material as ShaderMaterial
			# print("Node '%s': Using existing ShaderMaterial instance (not duplicated)." % name)

		# Check if the shader is the correct one (optional, but good for debugging)
		# if is_instance_valid(palette_swap_shader) and shader_material_instance.shader != palette_swap_shader:
		# 	printerr("Node '%s': Material's shader is not the expected palette_swap_shader." % name)
		# elif not is_instance_valid(shader_material_instance.shader):
		# 	printerr("Node '%s': ShaderMaterial has no shader assigned." % name)

	elif material != null: # Material exists but is not a ShaderMaterial
		printerr("Node '%s': Has a material, but it's not a ShaderMaterial. Palette swapping will not work." % name)
		return
	else: # No material assigned
		printerr("Node '%s': Requires a ShaderMaterial for palette swapping. Please assign one in the editor." % name)
		# You could optionally try to create and assign one here if you have a strict setup:
		# var new_mat = ShaderMaterial.new()
		# new_mat.shader = load("res://shaders/palette_swap.gdshader") # Ensure path is correct
		# material = new_mat
		# shader_material_instance = new_mat
		# print("Node '%s': Created and assigned a new ShaderMaterial." % name)
		# IMPORTANT: If creating here, you MUST ensure the source_placeholder uniforms are
		# set correctly for this node's specific art asset immediately after this.
		return

	# Connect to the PaletteManager
	if PaletteManager:
		PaletteManager.active_palette_updated.connect(_on_palette_manager_update)
		# Apply the initial palette
		if is_instance_valid(shader_material_instance): # Ensure instance is valid before getting colors
			_on_palette_manager_update(PaletteManager.get_current_palette_colors())
	else:
		printerr("Node '%s': PaletteManager Autoload not found! Palette updates will not be received." % name)


func _on_palette_manager_update(palette_colors: Dictionary):
	if not is_instance_valid(shader_material_instance):
		# This can happen if _ready() failed to get/create a valid material
		# printerr("Node '%s': _on_palette_manager_update called, but shader_material_instance is not valid." % name)
		return

	if not palette_colors.has("background") or \
	   not palette_colors.has("main") or \
	   not palette_colors.has("accent"):
		printerr("Node '%s': Received invalid palette_colors dictionary: %s" % [name, str(palette_colors)])
		return

	# print("Node '%s': Updating shader with palette: BG:%s, Main:%s, Accent:%s" % [name, palette_colors.background, palette_colors.main, palette_colors.accent])
	shader_material_instance.set_shader_parameter("palette_background_color", palette_colors.background)
	shader_material_instance.set_shader_parameter("palette_main_color", palette_colors.main)
	shader_material_instance.set_shader_parameter("palette_accent_color", palette_colors.accent)


func _exit_tree():
	# Disconnect from signals if the node is removed from the tree to prevent errors
	if PaletteManager and PaletteManager.is_connected("active_palette_updated", Callable(self, "_on_palette_manager_update")):
		PaletteManager.active_palette_updated.disconnect(_on_palette_manager_update)
