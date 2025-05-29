extends Node2D

@onready var score_label: Label = $ScoreLabel
@onready var h_slider: HSlider = $HSlider

var current_score: float = 0.0
var max_score: float = 100.0

# Assuming PaletteManager is an autoload singleton
@onready var palette_manager = get_node("/root/PaletteManager")

func _ready() -> void:
	# Connect to PaletteManager's signal
	if palette_manager:
		palette_manager.active_palette_updated.connect(_on_palette_changed)
		# Apply initial palette colors
		_on_palette_changed(palette_manager.get_current_palette_colors())
	else:
		printerr("ScoreDisplayDemo: PaletteManager not found. Make sure it's an autoload.")

	update_score_display()
	# Connect the slider's value_changed signal to a new method
	h_slider.value_changed.connect(_on_slider_value_changed)


func _process(delta: float) -> void:
	# Pass the time uniform to the shader for animations
	if score_label.material and score_label.material.shader:
		score_label.material.set_shader_parameter("time", Time.get_ticks_msec() / 1000.0)

	# Keyboard controls for testing
	if Input.is_action_just_pressed("ui_accept"): # Spacebar
		current_score = min(current_score + 10, max_score)
		h_slider.value = current_score # Update slider
		update_score_display()
	elif Input.is_action_just_pressed("ui_refresh"): # R key (you might need to define this in Input Map)
		current_score = 0
		h_slider.value = current_score # Update slider
		update_score_display()

func update_score_display() -> void:
	var score_ratio: float = 0.0
	if max_score > 0:
		score_ratio = current_score / max_score
	
	score_label.text = "Score: %d / Max: %d (%.2f)" % [current_score, max_score, score_ratio]
	
	# Update shader parameter
	if score_label.material and score_label.material.shader:
		score_label.material.set_shader_parameter("score_ratio", score_ratio)


func _on_slider_value_changed(value: float) -> void:
	current_score = value
	update_score_display()

func _on_palette_changed(palette_colors: Dictionary) -> void:
	if not score_label.material or not score_label.material.shader:
		print("ScoreDisplayDemo: Label material or shader not found, cannot apply palette colors.")
		return

	var main_color = palette_colors.get("main", Color.WHITE)
	var accent_color = palette_colors.get("accent", Color.RED)
	# var background_color = palette_colors.get("background", Color.BLACK) # Not used directly in this shader

	score_label.material.set_shader_parameter("tier_base_color", main_color)
	
	# For Bronze, let's use a slightly desaturated main_color or a mix
	var bronze_color = main_color.lerp(Color(0.5,0.5,0.5,1.0), 0.3) # Lerp towards gray
	score_label.material.set_shader_parameter("tier_bronze_color", bronze_color)

	# For Silver, let's use the main_color directly, or a slightly lighter version
	var silver_color = main_color.lightened(0.1)
	score_label.material.set_shader_parameter("tier_silver_color", silver_color)

	score_label.material.set_shader_parameter("tier_gold_color", accent_color)

	# For Platinum, let's use a lighter, possibly desaturated version of the accent color
	var platinum_color = accent_color.lightened(0.2).lerp(Color.WHITE, 0.3)
	score_label.material.set_shader_parameter("tier_platinum_color", platinum_color)
	
	print("ScoreDisplayDemo: Updated shader colors from palette.")

# Define a "ui_refresh" input action in Project > Project Settings > Input Map
# Add a new action named "ui_refresh" and assign the "R" key to it. 
