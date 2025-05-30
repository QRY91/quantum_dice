extends Node

## Handles procedural generation of ambient soundscapes

# Minimal audio settings
const CORRECT_BUFFER_LENGTH: float = 0.05  # 50ms buffer, a more reasonable size
const SAMPLE_RATE: int = 16000   # Increased sample rate
# const FREQUENCY: float = 55.0     # Fixed frequency - Will be replaced by base_frequency
# const AMPLITUDE: float = 0.3      # Fixed amplitude - Will be replaced by amplitude

@export var base_frequency: float = 220.0 # A4 note, should be audible
@export var modulation_depth: float = 0.0 # Not used in _fill_buffer yet
@export var modulation_rate: float = 0.0  # Not used in _fill_buffer yet
@export var amplitude: float = 0.25 # This will act as the sustain level

# ADSR Envelope parameters
@export var attack_time: float = 2.0 # seconds
@export var decay_time: float = 1.0 # seconds (to sustain_level)
@export var sustain_level: float = 0.7 # proportion of full amplitude (0 to 1)
@export var release_time: float = 5.0 # seconds

# Noise parameters (initially for compatibility with AmbientSoundPanel)
@export var noise_cutoff_frequency: float = 1000.0
@export var noise_resonance: float = 0.7
@export var noise_amplitude: float = 0.1

# Pulse parameters (initially for compatibility with AmbientSoundPanel)
@export var pulse_frequency: float = 220.0
@export var pulse_width: float = 0.5
@export var pulse_interval_min: float = 2.0
@export var pulse_interval_max: float = 5.0
@export var pulse_amplitude: float = 0.2

# Audio player
var audio_player: AudioStreamPlayer
var phase: float = 0.0 # For the main oscillator

# ADSR Envelope state
enum EnvelopeState { IDLE, ATTACK, DECAY, SUSTAIN, RELEASE }
var current_envelope_state: EnvelopeState = EnvelopeState.IDLE
var envelope_value: float = 0.0 # Current envelope multiplier (0 to 1)
var time_in_current_state: float = 0.0

var _initialized: bool = false
var _fill_buffer_call_count: int = 0 # For debug printing

func _init():
	print("ProceduralAudioGenerator: _init called")

func _ready():
	print("ProceduralAudioGenerator: _ready called")
	_setup_audio_player()

func _setup_audio_player() -> bool:
	if _initialized:
		return true
		
	print("ProceduralAudioGenerator: Setting up audio player...")
	
	audio_player = AudioStreamPlayer.new()
	var ambient_bus_name = "Ambient"
	var ambient_bus_index = AudioServer.get_bus_index(ambient_bus_name)
	if ambient_bus_index != -1:
		audio_player.bus = ambient_bus_name
	else:
		printerr("ProceduralAudioGenerator: Could not find 'Ambient' audio bus. Playing on Master.")
		audio_player.bus = "Master"
	
	add_child(audio_player)
	
	var stream = AudioStreamGenerator.new()
	stream.mix_rate = SAMPLE_RATE
	stream.buffer_length = CORRECT_BUFFER_LENGTH # Use the corrected float value
	
	if not stream:
		printerr("ProceduralAudioGenerator: Failed to create AudioStreamGenerator")
		return false
		
	audio_player.stream = stream
	audio_player.finished.connect(_on_player_finished)
	
	_initialized = true
	print("ProceduralAudioGenerator: Setup complete. Sample Rate: ", SAMPLE_RATE, ", Buffer Length (s): ", CORRECT_BUFFER_LENGTH)
	return true

func _start_ambient_generation():
	if not _initialized:
		if not _setup_audio_player():
			printerr("ProceduralAudioGenerator: Setup failed, cannot start generation.")
			return
	
	print("ProceduralAudioGenerator: Attempting to start ambient generation... Phase reset. Triggering ATTACK.")
	phase = 0.0
	_fill_buffer_call_count = 0 # Reset debug counter
	
	current_envelope_state = EnvelopeState.ATTACK
	time_in_current_state = 0.0
	# envelope_value is already 0 if it was IDLE or RELEASED, or will ramp from current value
	
	if audio_player and audio_player.stream:
		# Stop it first to ensure a clean start if it was already playing or in a weird state
		if audio_player.playing:
			# If it was already playing and we're "restarting", we might want a quick fade out/in
			# For now, just stop and restart, ADSR will kick in.
			audio_player.stop()
			print("ProceduralAudioGenerator: Stopped player before restarting.")

		audio_player.play() # Call play directly
		print("ProceduralAudioGenerator: audio_player.play() called. Player is now playing: ", audio_player.playing)
		set_process(true) # Ensure _process is running for envelope updates
	else:
		printerr("ProceduralAudioGenerator: audio_player or stream not valid for starting.")

func _stop_ambient_generation():
	print("ProceduralAudioGenerator: Stop requested. Triggering RELEASE.")
	if current_envelope_state != EnvelopeState.IDLE:
		current_envelope_state = EnvelopeState.RELEASE
		time_in_current_state = 0.0
	# Don't stop audio_player immediately; let the release phase play out.
	# The _process function will stop it when envelope is near zero.

func _process(delta: float):
	# Update envelope state and value
	time_in_current_state += delta
	
	match current_envelope_state:
		EnvelopeState.ATTACK:
			if attack_time > 0.001: # Avoid division by zero
				envelope_value = lerp(0.0, 1.0, min(time_in_current_state / attack_time, 1.0))
			else:
				envelope_value = 1.0 # Instant attack
			if time_in_current_state >= attack_time:
				current_envelope_state = EnvelopeState.DECAY
				time_in_current_state = 0.0
				print("ProceduralAudioGenerator: Envelope -> DECAY")
		
		EnvelopeState.DECAY:
			if decay_time > 0.001: # Avoid division by zero
				# Lerp from 1.0 down to sustain_level
				envelope_value = lerp(1.0, sustain_level, min(time_in_current_state / decay_time, 1.0))
			else:
				envelope_value = sustain_level # Instant decay
			if time_in_current_state >= decay_time:
				current_envelope_state = EnvelopeState.SUSTAIN
				time_in_current_state = 0.0 # Not strictly needed for sustain but good practice
				envelope_value = sustain_level # Ensure it lands exactly on sustain
				print("ProceduralAudioGenerator: Envelope -> SUSTAIN")

		EnvelopeState.SUSTAIN:
			envelope_value = sustain_level
			# Stays in sustain until _stop_ambient_generation is called
			
		EnvelopeState.RELEASE:
			# Need to capture the envelope value at the start of release
			# For simplicity now, assume it releases from current envelope_value or sustain_level if SUSTAIN was the previous state
			# A better way would be to store envelope_value_at_release_start
			var release_start_value = sustain_level # Simplified: assumes it was in sustain or full if attack was interrupted
			if time_in_current_state < release_time and release_time > 0.001: # Avoid division by zero
				envelope_value = lerp(release_start_value, 0.0, min(time_in_current_state / release_time, 1.0))
			else:
				envelope_value = 0.0 # Instant release or time expired
			
			if envelope_value < 0.001: # Effectively zero
				envelope_value = 0.0
				current_envelope_state = EnvelopeState.IDLE
				time_in_current_state = 0.0
				if audio_player and audio_player.playing:
					audio_player.stop()
					print("ProceduralAudioGenerator: Envelope -> IDLE. Player stopped.")
				set_process(false) # Can stop processing if idle
				
		EnvelopeState.IDLE:
			envelope_value = 0.0
			if audio_player and audio_player.playing: # Should already be stopped
				audio_player.stop()
			set_process(false)

	if not _initialized or not is_instance_valid(audio_player) or not audio_player.playing:
		if current_envelope_state != EnvelopeState.IDLE and current_envelope_state != EnvelopeState.RELEASE:
			# If we are supposed to be playing but player isn't, go to IDLE
			# current_envelope_state = EnvelopeState.IDLE # This might be too aggressive
			# set_process(false)
			pass # Envelope logic will eventually set it to IDLE if release finishes
		return
		
	var playback = audio_player.get_stream_playback()
	if playback:
		# Check if we can push a certain amount of buffer, e.g., half of it, to keep it flowing.
		# The number of frames needed depends on the mix_rate and buffer_length.
		var frames_to_push_ideal = int(CORRECT_BUFFER_LENGTH * SAMPLE_RATE * 0.5) # e.g., half the buffer
		# Push if we have less than a full ideal buffer available, but only if we can push what we intend to.
		if playback.get_frames_available() < frames_to_push_ideal and playback.can_push_buffer(frames_to_push_ideal):
			_fill_buffer(playback)
		elif playback.get_frames_available() > frames_to_push_ideal * 2: # Aggressively fill if we have a lot of space
			_fill_buffer(playback)
	else:
		if _fill_buffer_call_count < 5: # Avoid log spam
			printerr("ProceduralAudioGenerator: _process - playback object is null even though player.playing is true.")

func _fill_buffer(playback: AudioStreamGeneratorPlayback):
	if not playback:
		printerr("ProceduralAudioGenerator: _fill_buffer called with null playback object!")
		return

	# For debugging, print only a few times
	if _fill_buffer_call_count < 5:
		print("ProceduralAudioGenerator: _fill_buffer called (", _fill_buffer_call_count + 1, "). Frames available: ", playback.get_frames_available(), ", Can push: ", playback.can_push_buffer(1)) # Check for pushing at least 1 frame
	_fill_buffer_call_count += 1

	var frames_to_fill = playback.get_frames_available()
	if frames_to_fill == 0:
		# If no frames are asked for (or buffer is full), don't do work.
		# This can happen if the game stutters or if the audio buffer is kept full by previous calls.
		return

	var current_amplitude = amplitude * envelope_value # Modulate by master amplitude and current envelope

	for i in range(frames_to_fill):
		# Changed from square wave to sine wave
		var sample_value = sin(phase * TAU) * current_amplitude
		playback.push_frame(Vector2(sample_value, sample_value)) # Stereo frame
		phase = fmod(phase + (base_frequency / SAMPLE_RATE), 1.0)

func _on_player_finished():
	if audio_player and _initialized:
		audio_player.play()

# Simplified parameter interface - does nothing for now
func set_parameter(_parameter: String, _value: float):
	match _parameter:
		"frequency": # This is base_frequency for the drone
			base_frequency = _value
			print("ProceduralAudioGenerator: Set base_frequency to ", base_frequency)
		"modulation_depth":
			modulation_depth = _value
		"modulation_rate":
			modulation_rate = _value
		"amplitude": # This is the master amplitude, also acts as sustain target for envelope
			amplitude = clamp(_value, 0.0, 1.0)
			sustain_level = clamp(_value, 0.0, 1.0) # Tie sustain_level to this for simplicity for now
			print("ProceduralAudioGenerator: Set amplitude (and sustain_level) to ", amplitude)
		"attack_time":
			attack_time = max(0.01, _value) # Ensure minimum attack time
			print("ProceduralAudioGenerator: Set attack_time to ", attack_time)
		"release_time":
			release_time = max(0.01, _value) # Ensure minimum release time
			print("ProceduralAudioGenerator: Set release_time to ", release_time)
		# Noise parameters
		"cutoff_frequency": # Note: Name collision if not careful. Assuming this is for noise.
			noise_cutoff_frequency = _value
		"resonance":
			noise_resonance = _value
		# "amplitude": # Already used for drone. AmbientSoundPanel uses "noise_amp_slider"
						# In AmbientSoundPanel _on_noise_amp_changed calls AudioManager.set_ambient_parameter("noise", "amplitude", value)
						# So, AudioManager will call proc_audio_gen.set_parameter("amplitude", value)
						# This will currently overwrite the drone's amplitude. This needs a fix in AudioManager or here.
						# For now, let's assume AudioManager needs to be smarter or we need distinct param names.
						# Quick fix: let's add a specific name for noise amplitude here.
		"noise_amplitude": # Adding a distinct parameter name
			noise_amplitude = _value
		# Pulse parameters
		"pulse_frequency": # Assuming this parameter name from common use, verify with panel if issue
			pulse_frequency = _value
		"width":
			pulse_width = _value
		"interval_min":
			pulse_interval_min = _value
		"interval_max":
			pulse_interval_max = _value
		# "amplitude": # Same issue as with noise.
		"pulse_amplitude": # Adding a distinct parameter name
			pulse_amplitude = _value
		_:
			printerr("ProceduralAudioGenerator: Unknown parameter '", _parameter, "' with value '", _value, "'")

func _exit_tree():
	if audio_player:
		if audio_player.playing:
			audio_player.stop()
		audio_player.queue_free()
	_initialized = false # Mark as uninitialized
	current_envelope_state = EnvelopeState.IDLE
	set_process(false) 
