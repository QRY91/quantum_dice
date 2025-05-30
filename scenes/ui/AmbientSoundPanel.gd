extends PanelContainer

signal back_pressed

# Get references to all sliders
@onready var freq_slider = %FreqSlider
@onready var mod_depth_slider = %ModDepthSlider
@onready var mod_rate_slider = %ModRateSlider
@onready var drone_amp_slider = %DroneAmpSlider
@onready var attack_time_slider = %AttackTimeSlider
@onready var release_time_slider = %ReleaseTimeSlider

@onready var cutoff_slider = %CutoffSlider
@onready var resonance_slider = %ResonanceSlider
@onready var noise_amp_slider = %NoiseAmpSlider

@onready var pulse_freq_slider = %PulseFreqSlider
@onready var width_slider = %WidthSlider
@onready var interval_min_slider = %IntervalMinSlider
@onready var interval_max_slider = %IntervalMaxSlider
@onready var pulse_amp_slider = %PulseAmpSlider

# Get references to value labels
@onready var freq_value = %FreqValue
@onready var mod_depth_value = %ModDepthValue
@onready var mod_rate_value = %ModRateValue
@onready var drone_amp_value = %DroneAmpValue
@onready var attack_time_value = %AttackTimeValue
@onready var release_time_value = %ReleaseTimeValue

@onready var cutoff_value = %CutoffValue
@onready var resonance_value = %ResonanceValue
@onready var noise_amp_value = %NoiseAmpValue

@onready var pulse_freq_value = %PulseFreqValue
@onready var width_value = %WidthValue
@onready var interval_min_value = %IntervalMinValue
@onready var interval_max_value = %IntervalMaxValue
@onready var pulse_amp_value = %PulseAmpValue

# Get references to preset buttons
@onready var cosmic_button = %CosmicButton
@onready var mystical_button = %MysticalButton
@onready var quantum_button = %QuantumButton

@onready var randomize_button = $MarginContainer/VBoxContainer/ButtonsContainer/RandomizeButton
@onready var toggle_button = %ToggleButton
@onready var back_button = %BackButton

var is_playing: bool = true

# Preset definitions
const PRESETS = {
	"cosmic": {
		"drone": {"frequency": 40.0, "modulation_depth": 0.15, "modulation_rate": 0.05, "amplitude": 0.4, "attack_time": 3.0, "release_time": 5.0},
		"noise": {"cutoff_frequency": 800.0, "resonance": 0.8, "amplitude": 0.2},
		"pulse": {"frequency": 160.0, "width": 0.3, "interval_min": 3.0, "interval_max": 8.0, "amplitude": 0.15}
	},
	"mystical": {
		"drone": {"frequency": 70.0, "modulation_depth": 0.2, "modulation_rate": 0.15, "amplitude": 0.35, "attack_time": 2.5, "release_time": 4.0},
		"noise": {"cutoff_frequency": 2000.0, "resonance": 0.6, "amplitude": 0.1},
		"pulse": {"frequency": 280.0, "width": 0.7, "interval_min": 1.5, "interval_max": 4.0, "amplitude": 0.25}
	},
	"quantum": {
		"drone": {"frequency": 55.0, "modulation_depth": 0.1, "modulation_rate": 0.2, "amplitude": 0.3, "attack_time": 2.0, "release_time": 3.0},
		"noise": {"cutoff_frequency": 1500.0, "resonance": 0.7, "amplitude": 0.15},
		"pulse": {"frequency": 220.0, "width": 0.5, "interval_min": 2.0, "interval_max": 5.0, "amplitude": 0.2}
	}
}

func _ready():
	# Wait one frame to ensure all nodes are ready
	await get_tree().process_frame
	
	if not _verify_node_references():
		printerr("AmbientSoundPanel: Some required nodes are missing!")
		return
	
	# Connect all slider value changed signals
	freq_slider.value_changed.connect(_on_drone_freq_changed)
	mod_depth_slider.value_changed.connect(_on_mod_depth_changed)
	mod_rate_slider.value_changed.connect(_on_mod_rate_changed)
	drone_amp_slider.value_changed.connect(_on_drone_amp_changed)
	attack_time_slider.value_changed.connect(_on_attack_time_changed)
	release_time_slider.value_changed.connect(_on_release_time_changed)
	
	cutoff_slider.value_changed.connect(_on_cutoff_changed)
	resonance_slider.value_changed.connect(_on_resonance_changed)
	noise_amp_slider.value_changed.connect(_on_noise_amp_changed)
	
	pulse_freq_slider.value_changed.connect(_on_pulse_freq_changed)
	width_slider.value_changed.connect(_on_width_changed)
	interval_min_slider.value_changed.connect(_on_interval_min_changed)
	interval_max_slider.value_changed.connect(_on_interval_max_changed)
	pulse_amp_slider.value_changed.connect(_on_pulse_amp_changed)
	
	# Connect preset buttons
	cosmic_button.pressed.connect(func(): _load_preset("cosmic"))
	mystical_button.pressed.connect(func(): _load_preset("mystical"))
	quantum_button.pressed.connect(func(): _load_preset("quantum"))
	
	# Connect other buttons
	randomize_button.pressed.connect(_on_randomize_pressed)
	if is_instance_valid(toggle_button):
		toggle_button.toggled.connect(_on_toggle_pressed)
	back_button.pressed.connect(_on_back_pressed)
	
	# Initialize values
	_update_all_parameters()
	
	# Start ambient sound when panel is shown
	AudioManager.start_ambient_soundscape()
	if is_instance_valid(toggle_button):
		toggle_button.button_pressed = false
		toggle_button.text = "Stop"
	is_playing = true

func _verify_node_references() -> bool:
	# Verify all node references exist
	var nodes_to_check = {
		"freq_slider": freq_slider,
		"mod_depth_slider": mod_depth_slider,
		"mod_rate_slider": mod_rate_slider,
		"drone_amp_slider": drone_amp_slider,
		"attack_time_slider": attack_time_slider,
		"release_time_slider": release_time_slider,
		"cutoff_slider": cutoff_slider,
		"resonance_slider": resonance_slider,
		"noise_amp_slider": noise_amp_slider,
		"pulse_freq_slider": pulse_freq_slider,
		"width_slider": width_slider,
		"interval_min_slider": interval_min_slider,
		"interval_max_slider": interval_max_slider,
		"pulse_amp_slider": pulse_amp_slider,
		"freq_value": freq_value,
		"mod_depth_value": mod_depth_value,
		"mod_rate_value": mod_rate_value,
		"drone_amp_value": drone_amp_value,
		"attack_time_value": attack_time_value,
		"release_time_value": release_time_value,
		"cutoff_value": cutoff_value,
		"resonance_value": resonance_value,
		"noise_amp_value": noise_amp_value,
		"pulse_freq_value": pulse_freq_value,
		"width_value": width_value,
		"interval_min_value": interval_min_value,
		"interval_max_value": interval_max_value,
		"pulse_amp_value": pulse_amp_value,
		"cosmic_button": cosmic_button,
		"mystical_button": mystical_button,
		"quantum_button": quantum_button,
		"randomize_button": randomize_button,
		"toggle_button": toggle_button,
		"back_button": back_button
	}
	
	var all_valid = true
	for node_name in nodes_to_check:
		if not is_instance_valid(nodes_to_check[node_name]):
			printerr("AmbientSoundPanel: Node '", node_name, "' is missing!")
			all_valid = false
	
	return all_valid

func _update_value_label(label: Label, text: String):
	if is_instance_valid(label):
		label.text = text

func _update_all_parameters():
	# Update all parameters to match slider values
	_on_drone_freq_changed(freq_slider.value)
	_on_mod_depth_changed(mod_depth_slider.value)
	_on_mod_rate_changed(mod_rate_slider.value)
	_on_drone_amp_changed(drone_amp_slider.value)
	_on_attack_time_changed(attack_time_slider.value)
	_on_release_time_changed(release_time_slider.value)
	
	_on_cutoff_changed(cutoff_slider.value)
	_on_resonance_changed(resonance_slider.value)
	_on_noise_amp_changed(noise_amp_slider.value)
	
	_on_pulse_freq_changed(pulse_freq_slider.value)
	_on_width_changed(width_slider.value)
	_on_interval_min_changed(interval_min_slider.value)
	_on_interval_max_changed(interval_max_slider.value)
	_on_pulse_amp_changed(pulse_amp_slider.value)

# Drone parameter change handlers
func _on_drone_freq_changed(value: float):
	AudioManager.set_ambient_parameter("drone", "frequency", value)
	_update_value_label(freq_value, "%.1f Hz" % value)

func _on_mod_depth_changed(value: float):
	AudioManager.set_ambient_parameter("drone", "modulation_depth", value)
	_update_value_label(mod_depth_value, "%.2f" % value)

func _on_mod_rate_changed(value: float):
	AudioManager.set_ambient_parameter("drone", "modulation_rate", value)
	_update_value_label(mod_rate_value, "%.2f Hz" % value)

func _on_drone_amp_changed(value: float):
	AudioManager.set_ambient_parameter("drone", "amplitude", value)
	_update_value_label(drone_amp_value, "%.2f" % value)

# New handlers for attack and release time
func _on_attack_time_changed(value: float):
	AudioManager.set_ambient_parameter("drone", "attack_time", value)
	_update_value_label(attack_time_value, "%.2fs" % value)

func _on_release_time_changed(value: float):
	AudioManager.set_ambient_parameter("drone", "release_time", value)
	_update_value_label(release_time_value, "%.2fs" % value)

# Noise parameter change handlers
func _on_cutoff_changed(value: float):
	AudioManager.set_ambient_parameter("noise", "cutoff_frequency", value)
	_update_value_label(cutoff_value, "%.0f Hz" % value)

func _on_resonance_changed(value: float):
	AudioManager.set_ambient_parameter("noise", "resonance", value)
	_update_value_label(resonance_value, "%.2f" % value)

func _on_noise_amp_changed(value: float):
	AudioManager.set_ambient_parameter("noise", "amplitude", value)
	_update_value_label(noise_amp_value, "%.2f" % value)

# Pulse parameter change handlers
func _on_pulse_freq_changed(value: float):
	AudioManager.set_ambient_parameter("pulse", "frequency", value)
	_update_value_label(pulse_freq_value, "%.1f Hz" % value)

func _on_width_changed(value: float):
	AudioManager.set_ambient_parameter("pulse", "width", value)
	_update_value_label(width_value, "%.2f" % value)

func _on_interval_min_changed(value: float):
	AudioManager.set_ambient_parameter("pulse", "interval_min", value)
	_update_value_label(interval_min_value, "%.1fs" % value)
	# Ensure max interval is always greater than min
	if is_instance_valid(interval_max_slider) and interval_max_slider.value < value:
		interval_max_slider.value = value + 0.5

func _on_interval_max_changed(value: float):
	AudioManager.set_ambient_parameter("pulse", "interval_max", value)
	_update_value_label(interval_max_value, "%.1fs" % value)
	# Ensure min interval is always less than max
	if is_instance_valid(interval_min_slider) and interval_min_slider.value > value:
		interval_min_slider.value = value - 0.5

func _on_pulse_amp_changed(value: float):
	AudioManager.set_ambient_parameter("pulse", "amplitude", value)
	_update_value_label(pulse_amp_value, "%.2f" % value)

func _on_randomize_pressed():
	AudioManager.randomize_ambient_parameters()
	# Update sliders to match new random values
	_update_sliders_from_parameters()

func _on_toggle_pressed(button_pressed: bool):
	is_playing = !button_pressed
	if is_playing:
		AudioManager.start_ambient_soundscape()
		if is_instance_valid(toggle_button):
			toggle_button.text = "Stop"
	else:
		AudioManager.stop_ambient_soundscape()
		if is_instance_valid(toggle_button):
			toggle_button.text = "Start"

func _on_back_pressed():
	# Stop audio before hiding panel
	AudioManager.stop_ambient_soundscape()
	is_playing = false
	hide()
	emit_signal("back_pressed")

func _load_preset(preset_name: String):
	if not PRESETS.has(preset_name):
		return
		
	var preset = PRESETS[preset_name]
	
	# Set all parameters from the preset
	for type in preset:
		for param in preset[type]:
			AudioManager.set_ambient_parameter(type, param, preset[type][param])
	
	# Update sliders to match
	_update_sliders_from_parameters()

func _update_sliders_from_parameters():
	# Get current parameters from AudioManager
	var params = AudioManager.get_synthesis_parameters()
	if params.is_empty():
		return
		
	# Update drone parameters
	freq_slider.value = params.drone.frequency
	mod_depth_slider.value = params.drone.modulation_depth
	mod_rate_slider.value = params.drone.modulation_rate
	drone_amp_slider.value = params.drone.amplitude
	
	# Check if attack_time and release_time exist in params before assigning
	if params.drone.has("attack_time"):
		attack_time_slider.value = params.drone.attack_time
	else:
		# Fallback if not in params (e.g. older ProceduralAudioGenerator version or before AudioManager fetches it)
		attack_time_slider.value = 2.0 # Default value from ProceduralAudioGenerator
	
	if params.drone.has("release_time"):
		release_time_slider.value = params.drone.release_time
	else:
		# Fallback
		release_time_slider.value = 5.0 # Default value from ProceduralAudioGenerator
	
	# Update noise parameters
	cutoff_slider.value = params.noise.cutoff_frequency
	resonance_slider.value = params.noise.resonance
	noise_amp_slider.value = params.noise.amplitude
	
	# Update pulse parameters
	pulse_freq_slider.value = params.pulse.frequency
	width_slider.value = params.pulse.width
	interval_min_slider.value = params.pulse.interval_min
	interval_max_slider.value = params.pulse.interval_max
	pulse_amp_slider.value = params.pulse.amplitude

func _exit_tree():
	# Ensure audio is stopped when panel is removed
	AudioManager.stop_ambient_soundscape()

func _notification(what: int):
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		if visible:
			# Panel became visible
			if is_playing:
				AudioManager.start_ambient_soundscape()
				if is_instance_valid(toggle_button):
					toggle_button.text = "Stop"
		else:
			# Panel became invisible
			AudioManager.stop_ambient_soundscape()
			if is_instance_valid(toggle_button):
				toggle_button.text = "Start"
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		# Ensure audio is stopped when window is closed
		AudioManager.stop_ambient_soundscape()
	elif what == NOTIFICATION_PREDELETE:
		# Ensure audio is stopped when panel is deleted
		AudioManager.stop_ambient_soundscape() 
