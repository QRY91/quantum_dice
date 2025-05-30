# res://scripts/autoloads/AudioManager.gd
extends Node

signal music_volume_changed(volume_percent: float)
signal sfx_volume_changed(volume_percent: float)
signal ambient_state_changed(is_playing: bool)

const SAVE_FILE_PATH: String = "user://audio_settings.save"

const MUSIC_BUS_NAME = "Music"
const SFX_BUS_NAME = "SFX"
const AMBIENT_BUS_NAME = "Ambient"

var ProceduralAudioGeneratorScript = preload("res://scripts/autoloads/ProceduralAudioGenerator.gd")
var proc_audio_gen: Node

var music_bus_index: int
var sfx_bus_index: int
var ambient_bus_index: int

var music_volume: float = 1.0  # 0.0 to 1.0
var sfx_volume: float = 1.0    # 0.0 to 1.0
var music_enabled: bool = true
var sfx_enabled: bool = true

func _ready():
	print("AudioManager: Initializing audio system...")
	_ensure_audio_buses_exist()
	
	# Get audio bus indices
	music_bus_index = AudioServer.get_bus_index(MUSIC_BUS_NAME)
	sfx_bus_index = AudioServer.get_bus_index(SFX_BUS_NAME)
	ambient_bus_index = AudioServer.get_bus_index(AMBIENT_BUS_NAME)
	
	print("AudioManager: Bus indices - Music: ", music_bus_index, ", SFX: ", sfx_bus_index, ", Ambient: ", ambient_bus_index)
	
	# Initialize procedural audio generator
	if ProceduralAudioGeneratorScript:
		proc_audio_gen = Node.new()
		proc_audio_gen.set_script(ProceduralAudioGeneratorScript)
		add_child(proc_audio_gen)
		print("AudioManager: ProceduralAudioGenerator initialized")
	else:
		printerr("AudioManager: Failed to load ProceduralAudioGenerator script!")
	
	load_settings()

func _ensure_audio_buses_exist():
	# First, check how many buses we have
	var bus_count = AudioServer.bus_count
	print("AudioManager: Current bus count: ", bus_count)
	
	# Create Music bus if it doesn't exist
	if AudioServer.get_bus_index(MUSIC_BUS_NAME) == -1:
		AudioServer.add_bus()
		var new_idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(new_idx, MUSIC_BUS_NAME)
		AudioServer.set_bus_send(new_idx, "Master")
		print("AudioManager: Created Music bus at index ", new_idx)
	
	# Create SFX bus if it doesn't exist
	if AudioServer.get_bus_index(SFX_BUS_NAME) == -1:
		AudioServer.add_bus()
		var new_idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(new_idx, SFX_BUS_NAME)
		AudioServer.set_bus_send(new_idx, "Master")
		print("AudioManager: Created SFX bus at index ", new_idx)
	
	# Create Ambient bus if it doesn't exist
	if AudioServer.get_bus_index(AMBIENT_BUS_NAME) == -1:
		AudioServer.add_bus()
		var new_idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(new_idx, AMBIENT_BUS_NAME)
		AudioServer.set_bus_send(new_idx, "Master")
		print("AudioManager: Created Ambient bus at index ", new_idx)

func set_music_volume(percent: float):
	music_volume = clamp(percent, 0.0, 1.0)
	if music_enabled:
		AudioServer.set_bus_volume_db(music_bus_index, linear_to_db(music_volume))
	emit_signal("music_volume_changed", music_volume)
	save_settings()

func set_sfx_volume(percent: float):
	sfx_volume = clamp(percent, 0.0, 1.0)
	if sfx_enabled:
		AudioServer.set_bus_volume_db(sfx_bus_index, linear_to_db(sfx_volume))
	emit_signal("sfx_volume_changed", sfx_volume)
	save_settings()

func toggle_music(enabled: bool):
	music_enabled = enabled
	AudioServer.set_bus_mute(music_bus_index, !music_enabled)
	if music_enabled:
		AudioServer.set_bus_volume_db(music_bus_index, linear_to_db(music_volume))
	save_settings()

func toggle_sfx(enabled: bool):
	sfx_enabled = enabled
	AudioServer.set_bus_mute(sfx_bus_index, !sfx_enabled)
	if sfx_enabled:
		AudioServer.set_bus_volume_db(sfx_bus_index, linear_to_db(sfx_volume))
	save_settings()

func save_settings():
	var config = ConfigFile.new()
	config.set_value("audio", "music_volume", music_volume)
	config.set_value("audio", "sfx_volume", sfx_volume)
	config.set_value("audio", "music_enabled", music_enabled)
	config.set_value("audio", "sfx_enabled", sfx_enabled)
	
	var err = config.save(SAVE_FILE_PATH)
	if err != OK:
		printerr("AudioManager: Failed to save audio settings!")

func load_settings():
	var config = ConfigFile.new()
	var err = config.load(SAVE_FILE_PATH)
	
	if err == OK:
		music_volume = config.get_value("audio", "music_volume", 1.0)
		sfx_volume = config.get_value("audio", "sfx_volume", 1.0)
		music_enabled = config.get_value("audio", "music_enabled", true)
		sfx_enabled = config.get_value("audio", "sfx_enabled", true)
		
		# Apply loaded settings
		set_music_volume(music_volume)
		set_sfx_volume(sfx_volume)
		toggle_music(music_enabled)
		toggle_sfx(sfx_enabled)
	else:
		print("AudioManager: No saved settings found, using defaults.") 

func start_ambient_soundscape():
	if is_instance_valid(proc_audio_gen):
		proc_audio_gen._start_ambient_generation()
		emit_signal("ambient_state_changed", true)
	else:
		printerr("AudioManager: Cannot start ambient soundscape - generator not valid!")

func stop_ambient_soundscape():
	if is_instance_valid(proc_audio_gen):
		proc_audio_gen._stop_ambient_generation()
		emit_signal("ambient_state_changed", false)
	else:
		printerr("AudioManager: Cannot stop ambient soundscape - generator not valid!")

func randomize_ambient_parameters():
	if is_instance_valid(proc_audio_gen):
		proc_audio_gen.set_parameter("frequency", randf_range(40.0, 80.0))
		proc_audio_gen.set_parameter("modulation_depth", randf_range(0.05, 0.2))
		proc_audio_gen.set_parameter("modulation_rate", randf_range(0.1, 0.5))
		proc_audio_gen.set_parameter("amplitude", randf_range(0.2, 0.4))
	else:
		printerr("AudioManager: Cannot randomize parameters - generator not valid!")

func set_ambient_parameter(type: String, parameter: String, value: float):
	if is_instance_valid(proc_audio_gen):
		# Adjust parameter name for amplitude based on type for ProceduralAudioGenerator
		var final_parameter_name = parameter
		if parameter == "amplitude":
			if type == "noise":
				final_parameter_name = "noise_amplitude"
			elif type == "pulse":
				final_parameter_name = "pulse_amplitude"
			# For "drone", it remains "amplitude"
			
		proc_audio_gen.set_parameter(final_parameter_name, value)
	else:
		printerr("AudioManager: Cannot set parameter - generator not valid!")

func get_synthesis_parameters() -> Dictionary:
	if is_instance_valid(proc_audio_gen):
		return {
			"drone": {
				"frequency": proc_audio_gen.base_frequency,
				"modulation_depth": proc_audio_gen.modulation_depth,
				"modulation_rate": proc_audio_gen.modulation_rate,
				"amplitude": proc_audio_gen.amplitude
			},
			"noise": {
				"cutoff_frequency": proc_audio_gen.noise_cutoff_frequency,
				"resonance": proc_audio_gen.noise_resonance,
				"amplitude": proc_audio_gen.noise_amplitude
			},
			"pulse": {
				"frequency": proc_audio_gen.pulse_frequency,
				"width": proc_audio_gen.pulse_width,
				"interval_min": proc_audio_gen.pulse_interval_min,
				"interval_max": proc_audio_gen.pulse_interval_max,
				"amplitude": proc_audio_gen.pulse_amplitude
			}
		}
	return {}
