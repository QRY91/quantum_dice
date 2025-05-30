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

@onready var back_button = %BackButton

var is_playing: bool = true

func _ready():
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
	
	back_button.pressed.connect(_on_back_pressed)
	
	# Initialize values
	_update_all_parameters()
	
	# Start ambient sound when panel is shown
	AudioManager.start_ambient_soundscape()
	is_playing = true

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
	if interval_max_slider.value < value:
		interval_max_slider.value = value + 0.5

func _on_interval_max_changed(value: float):
	AudioManager.set_ambient_parameter("pulse", "interval_max", value)
	_update_value_label(interval_max_value, "%.1fs" % value)
	# Ensure min interval is always less than max
	if interval_min_slider.value > value:
		interval_min_slider.value = value - 0.5

func _on_pulse_amp_changed(value: float):
	AudioManager.set_ambient_parameter("pulse", "amplitude", value)
	_update_value_label(pulse_amp_value, "%.2f" % value)

func _on_back_pressed():
	# Stop audio before hiding panel
	AudioManager.stop_ambient_soundscape()
	is_playing = false
	get_parent().hide()
	emit_signal("back_pressed")

func _notification(what: int):
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		if not visible:
			# Panel became invisible
			AudioManager.stop_ambient_soundscape()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		# Ensure audio is stopped when window is closed or panel is deleted
		AudioManager.stop_ambient_soundscape() 
