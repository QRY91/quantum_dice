# res://scripts/Game.gd
# TABS FOR INDENTATION
extends Node2D

# --- Game State Enum ---
enum GameState {
	MENU,
	INITIALIZING_GAME,
	INITIALIZING_ROUND,
	PLAYING, # Was IDLE, represents waiting for player input
	ROLLING, # Main dice roll visual animation is playing
	RESULT_REVEAL, # Rolled glyph shown on button, brief hover/bob
	FANFARE_ANIMATION, # Glyph moves to center, score/synergy effects play
	GLYPH_TO_HISTORY, # Glyph moves from center to history slot
	PROCESSING_ROLL, # Kept for now, but its logic will be distributed
	LOOT_SELECTION,
	ROUND_SUMMARY,
	GAME_OVER
}
var current_game_state: GameState = GameState.MENU

# --- Success Tier Enum ---
enum SuccessTier { NONE, MINOR, MEDIUM, MAJOR, JACKPOT }
var current_success_tier: SuccessTier = SuccessTier.NONE

var enable_debug_rolls: bool = false

# --- Player's DICE & Roll History (LOGIC ONLY) ---
var current_player_dice: Array[GlyphData] = []
var roll_history: Array[GlyphData] = []
var last_rolled_glyph: GlyphData = null

# --- Scoring & Progression ---
var current_round_score: int = 0
var target_score: int = 0
var rolls_left: int = 0
var current_level: int = 1
var total_accumulated_score: int = 0
var high_score: int = 0
const HIGH_SCORE_FILE_PATH: String = "user://quantum_dice_highscore.dat"

# --- Configurable Game Parameters ---
const STARTING_ROLLS: int = 6
const BASE_TARGET_SCORE: int = 15
const TARGET_SCORE_PER_LEVEL_INCREASE: int = 7
const ROLLS_INCREASE_EVERY_X_LEVELS: int = 2
const MAX_ROLLS_CAP: int = 15
const DESIGN_BLOCK_SIZE: int = 80
const ROLL_BUTTON_GLYPH_SIZE: Vector2 = Vector2(160, 160) # 2x2 design blocks
const HISTORY_SLOT_GLYPH_SIZE: Vector2 = Vector2(80, 80) # 1x1 design block

# --- Synergy Tracking ---
var synergies_fired_this_round: Dictionary = {}

# --- Rune Phrases and Boons ---
var RUNE_PHRASES: Dictionary = {
	"SUN_POWER": {
		"id": "sun_power",
		"display_name": "Sun's Radiance",
		"runes_required": ["rune_sowilo", "rune_fehu"],
		"boon_description": "All 'dice' type glyphs score +2 points for the rest of the run."
	},
	"WATER_FLOW": {
		"id": "water_flow",
		"display_name": "Water's Flow",
		"runes_required": ["rune_laguz", "rune_ansuz"],
		"boon_description": "Gain +1 max roll per round for the rest of the run (up to a new cap)."
	}
}
var active_boons: Dictionary = {}
var run_score_multiplier_boon: float = 1.0
var extra_points_per_dice_glyph_boon: int = 0
var extra_max_rolls_boon: int = 0

# --- Animation Control ---
var animating_glyph_node: TextureRect = null # For the glyph flying animation
var reveal_on_button_timer: Timer # Timer for RESULT_REVEAL phase
const REVEAL_DURATION: float = 0.75 # How long glyph stays on button bobbing

# --- CORE UI Node References ---
@onready var roll_button: TextureButton = $UICanvas/MainGameUI/AnimatedRollButton
@onready var ui_canvas: CanvasLayer = $UICanvas # Assuming UICanvas is a CanvasLayer for global UI elements

# --- Scene Preloads & Instances ---
var main_menu_scene: PackedScene = preload("res://scenes/ui/MainMenu.tscn")
@onready var main_menu_instance: Control

var loot_screen_scene: PackedScene = preload("res://scenes/ui/LootScreen.tscn")
@onready var loot_screen_instance: Control

var hud_scene: PackedScene = preload("res://scenes/ui/HUD.tscn")
@onready var hud_instance: Control

@onready var roll_animation_timer: Timer = $RollAnimationTimer # For ROLLING state duration

# --- Audio ---
@onready var sfx_player: AudioStreamPlayer = $SFXPlayer
var sfx_synergy_pop: AudioStream = preload("res://assets/sfx/synergy_success.ogg")
var sfx_loot_appears: AudioStream = preload("res://assets/sfx/loot_appears.ogg")
var sfx_glyph_added: AudioStream = preload("res://assets/sfx/glyph_added.ogg")

var game_over_screen_scene: PackedScene = preload("res://scenes/ui/GameOverScreen.tscn")
@onready var game_over_instance: Control
@onready var playback_speed_button: TextureButton 

func _ready():
	_load_high_score()

	# Reveal on button timer setup
	reveal_on_button_timer = Timer.new()
	reveal_on_button_timer.one_shot = true
	reveal_on_button_timer.wait_time = REVEAL_DURATION
	reveal_on_button_timer.timeout.connect(Callable(self, "_on_reveal_on_button_timer_timeout"))
	add_child(reveal_on_button_timer)

	# HUD Setup
	if hud_scene:
		hud_instance = hud_scene.instantiate()
		if is_instance_valid(ui_canvas): ui_canvas.add_child(hud_instance)
		else: add_child(hud_instance); printerr("UICanvas not found for HUD.")
		if hud_instance.has_signal("inventory_toggled"):
			hud_instance.inventory_toggled.connect(Callable(self, "_on_hud_inventory_toggled"))
		# Connect new signal from HUD for fanfare completion
		if hud_instance.has_signal("fanfare_animation_finished"):
			hud_instance.fanfare_animation_finished.connect(Callable(self, "_on_hud_fanfare_animation_finished"))
		else:
			printerr("WARNING: HUD.gd needs to define and emit 'fanfare_animation_finished' signal.")
		hud_instance.visible = false
	else:
		printerr("ERROR: HUD.tscn not preloaded!")

	# Main Menu Setup
	if main_menu_scene:
		main_menu_instance = main_menu_scene.instantiate()
		if is_instance_valid(ui_canvas): ui_canvas.add_child(main_menu_instance)
		else: add_child(main_menu_instance)
		if main_menu_instance.has_signal("start_game_pressed"):
			main_menu_instance.start_game_pressed.connect(Callable(self, "_on_main_menu_start_game"))
	else:
		printerr("ERROR: MainMenu.tscn not preloaded!")

	# Loot Screen Setup
	if loot_screen_scene:
		loot_screen_instance = loot_screen_scene.instantiate()
		if is_instance_valid(ui_canvas): ui_canvas.add_child(loot_screen_instance)
		else: add_child(loot_screen_instance)
		# Connect signals as before
		if loot_screen_instance.has_signal("loot_selected"):
			loot_screen_instance.loot_selected.connect(Callable(self, "_on_loot_selected"))
		if loot_screen_instance.has_signal("skip_loot_pressed"): # Assuming this signal exists
			loot_screen_instance.skip_loot_pressed.connect(Callable(self, "_on_loot_screen_closed"))
		loot_screen_instance.hide()
	else:
		printerr("ERROR: LootScreen.tscn not preloaded!")
	
	# Game Over Screen Setup
	if game_over_screen_scene:
		game_over_instance = game_over_screen_scene.instantiate()
		if is_instance_valid(ui_canvas): ui_canvas.add_child(game_over_instance)
		else: add_child(game_over_instance)
		if game_over_instance.has_signal("retry_pressed"):
			game_over_instance.retry_pressed.connect(Callable(self, "_on_game_over_retry_pressed"))
		if game_over_instance.has_signal("main_menu_pressed"):
			game_over_instance.main_menu_pressed.connect(Callable(self, "_on_game_over_main_menu_pressed"))
		game_over_instance.hide()
	else:
		printerr("ERROR: GameOverScreen.tscn not preloaded!")

	# Roll Button Signal
	if is_instance_valid(roll_button):
		roll_button.pressed.connect(Callable(self, "_on_roll_button_pressed"))
	else:
		printerr("ERROR: RollButton not valid.")
	
	# Roll Animation Timer Signal
	if is_instance_valid(roll_animation_timer):
		roll_animation_timer.timeout.connect(Callable(self, "_on_roll_animation_timer_timeout"))
	else:
		printerr("ERROR: RollAnimationTimer not found.")
		
	if not is_instance_valid(sfx_player):
		printerr("ERROR: SFXPlayer node not found!")
	# Assuming PlaybackSpeedButton is a child of HUD instance
	if is_instance_valid(hud_instance):
		playback_speed_button = hud_instance.get_node_or_null("PlaybackSpeedButton") # Use the node name you give it in HUD.tscn
		if is_instance_valid(playback_speed_button) and playback_speed_button.has_signal("speed_changed"):
			playback_speed_button.speed_changed.connect(Callable(self, "_on_playback_speed_changed"))
			print("Game: Connected to PlaybackSpeedButton's speed_changed signal.")
			# Initialize Engine.time_scale based on button's default, if button script has a getter
			if playback_speed_button.has_method("get_current_speed"):
					Engine.time_scale = playback_speed_button.get_current_speed()
					print("Game: Initial Engine.time_scale set to ", Engine.time_scale)
			else: # Default to 1.0 if button doesn't provide initial
					Engine.time_scale = 1.0 
		elif not is_instance_valid(playback_speed_button):
			printerr("Game: PlaybackSpeedButton node not found in HUD instance.")
		else: # Button found, but no signal
			printerr("Game: PlaybackSpeedButton node found, but it does NOT have 'speed_changed' signal.")
	current_game_state = GameState.MENU
	print("Game scene _ready complete. Initial game state set to MENU.")


func _process(delta):
	match current_game_state:
		GameState.MENU:
			# ... (show main menu, hide game UI/HUD) ...
			var main_game_ui_node = get_node_or_null("UICanvas/MainGameUI")
			if is_instance_valid(main_game_ui_node): main_game_ui_node.visible = false
			if is_instance_valid(hud_instance): hud_instance.visible = false
			if is_instance_valid(main_menu_instance): main_menu_instance.show_menu()

		GameState.INITIALIZING_GAME:
			_initialize_new_game_session()
			if is_instance_valid(hud_instance): hud_instance.reset_round_visuals() # Full reset for new game
			current_game_state = GameState.INITIALIZING_ROUND

		GameState.INITIALIZING_ROUND:
			_initialize_current_round_setup()
			if is_instance_valid(hud_instance): 
				hud_instance.reset_round_visuals() # Reset for new round (e.g. history track)
				# Update displays based on new round setup
				var effective_max_rolls = _get_effective_max_rolls_for_round()
				hud_instance.update_rolls_display(rolls_left, effective_max_rolls)
				hud_instance.update_score_target_display(current_round_score, target_score)
				hud_instance.update_level_display(current_level)
				hud_instance.update_dice_inventory_display(current_player_dice) # Ensure inventory is up-to-date
				hud_instance.update_last_rolled_glyph_display(null) # Clear last rolled from previous round
				# hud_instance.clear_visual_roll_history() # HUD should handle this in its reset_round_visuals
			current_game_state = GameState.PLAYING

		GameState.PLAYING:
			var main_game_ui_node = get_node_or_null("UICanvas/MainGameUI")
			if is_instance_valid(main_game_ui_node) and not main_game_ui_node.visible:
				main_game_ui_node.visible = true
			if is_instance_valid(hud_instance) and not hud_instance.visible:
				hud_instance.visible = true
			_update_hud_elements() # Keep static HUD elements correct
			if is_instance_valid(roll_button):
				roll_button.disabled = (rolls_left <= 0)

		GameState.ROLLING:
			# Roll button animation (e.g. AnimatedSprite2D) should be playing.
			# Game.gd waits for roll_animation_timer.
			if is_instance_valid(roll_button): roll_button.disabled = true
			# HUD specific: hud_instance.play_roll_button_animation() or similar
			pass

		GameState.RESULT_REVEAL:
			# Glyph is visible on the button, bobbing. Waiting for reveal_on_button_timer.
			# Bobbing tween for RolledGlyphOnButtonDisplay could be started here if not handled by HUD
			pass

		GameState.FANFARE_ANIMATION:
			# Animating glyph is moving to center. Score effects are playing.
			# Waiting for HUD's 'fanfare_animation_finished' signal.
			pass

		GameState.GLYPH_TO_HISTORY:
			# Animating glyph is moving from center to history slot.
			# Waiting for tween to finish.
			pass
			
		# GameState.PROCESSING_ROLL: # This state's logic is now distributed
			# _process_the_finished_roll_outcome() 
			# if rolls_left <= 0 and current_game_state != GameState.ROUND_SUMMARY : # Check to prevent double transition
				# current_game_state = GameState.ROUND_SUMMARY
			# elif current_game_state != GameState.PLAYING and current_game_state != GameState.ROUND_SUMMARY: # Check
				# current_game_state = GameState.PLAYING
				
		GameState.LOOT_SELECTION:
			# ... (as before) ...
			pass

		GameState.ROUND_SUMMARY:
			if current_round_score >= target_score:
				current_game_state = GameState.LOOT_SELECTION
				_prepare_and_show_loot_screen()
			else:
				current_game_state = GameState.GAME_OVER

		GameState.GAME_OVER:
			if is_instance_valid(hud_instance): hud_instance.visible = false
			if total_accumulated_score > high_score:
				high_score = total_accumulated_score
				_save_high_score()
			if is_instance_valid(game_over_instance) and not game_over_instance.visible:
				game_over_instance.show_screen(total_accumulated_score, current_level)
			pass


# --- Core Gameplay Functions ---

func _initialize_new_game_session():
	print("Initializing new game session...")
	current_level = 1
	total_accumulated_score = 0
	current_player_dice.clear()
	_reset_boons_and_effects()
	if GlyphDB and not GlyphDB.starting_dice_configuration.is_empty():
		current_player_dice = GlyphDB.starting_dice_configuration.duplicate(true)
	else:
		printerr("Game Error: GlyphDB not ready or starting_dice_configuration is empty!")
	# HUD update for inventory will happen in INITIALIZING_ROUND

func _get_effective_max_rolls_for_round() -> int:
	var calculated_rolls = STARTING_ROLLS + int((current_level - 1) / ROLLS_INCREASE_EVERY_X_LEVELS) + extra_max_rolls_boon
	return min(calculated_rolls, MAX_ROLLS_CAP + extra_max_rolls_boon) # Boon can exceed original cap slightly

func _initialize_current_round_setup():
	print("Initializing round setup for level: ", current_level)
	current_round_score = 0
	target_score = BASE_TARGET_SCORE + (current_level - 1) * TARGET_SCORE_PER_LEVEL_INCREASE
	rolls_left = _get_effective_max_rolls_for_round()
	
	roll_history.clear()
	synergies_fired_this_round.clear()
	last_rolled_glyph = null
	# HUD updates are handled in INITIALIZING_ROUND state in _process

func _update_hud_elements(): # For static elements or non-animated updates
	if not is_instance_valid(hud_instance): return
	var effective_max_rolls = _get_effective_max_rolls_for_round()
	hud_instance.update_rolls_display(rolls_left, effective_max_rolls)
	hud_instance.update_score_target_display(current_round_score, target_score) # Score updates here are static
	hud_instance.update_level_display(current_level)
	# hud_instance.update_last_rolled_glyph_display(last_rolled_glyph) # This is now handled by on-button display and fanfare

# --- Roll Sequence ---

func _on_roll_button_pressed():
	if current_game_state == GameState.PLAYING and rolls_left > 0:
		print("Roll button pressed. State: ROLLING")
		# play_sound(sfx_roll_start)
		current_game_state = GameState.ROLLING
		if is_instance_valid(roll_button): roll_button.disabled = true
		
		# Tell HUD to start its roll button animation (e.g., AnimatedSprite2D)
		if is_instance_valid(hud_instance) and hud_instance.has_method("start_roll_button_animation"):
			hud_instance.start_roll_button_animation()
		
		# Hide the static glyph on button if it was visible
		var on_button_glyph_display = roll_button.get_node_or_null("RolledGlyphOnButtonDisplay")
		if is_instance_valid(on_button_glyph_display):
			on_button_glyph_display.visible = false
			
		roll_animation_timer.start() # This timer dictates duration of ROLLING state
	else:
		print("Cannot roll. State:", GameState.keys()[current_game_state], "Rolls left:", rolls_left)

func _on_roll_animation_timer_timeout(): # End of ROLLING state
	if current_game_state == GameState.ROLLING:
		print("Roll animation timer timeout. Performing roll.")
		# play_sound(sfx_roll_land)
		
		_perform_roll() # Sets last_rolled_glyph

		if not is_instance_valid(last_rolled_glyph): # Critical check
			printerr("Perform roll resulted in invalid glyph. Aborting roll sequence.")
			current_game_state = GameState.PLAYING # Reset to a safe state
			if is_instance_valid(roll_button): roll_button.disabled = false
			# Potentially consume the roll or handle error more gracefully
			return

		roll_history.append(last_rolled_glyph) # Update history for synergy checks
		print("Game: last_rolled_glyph '", last_rolled_glyph.display_name, "' added to roll_history. History size: ", roll_history.size())


		# This call might be making HUD.last_roll_display (the "middle glyph") appear too early.
		# We'll modify HUD.gd's function to prevent this for now.
		if is_instance_valid(hud_instance) and hud_instance.has_method("stop_roll_button_animation_show_result"):
			hud_instance.stop_roll_button_animation_show_result(last_rolled_glyph) 
		
		# This is what shows the glyph ON THE ACTUAL ROLL BUTTON
		var on_button_glyph_display = roll_button.get_node_or_null("RolledGlyphOnButtonDisplay")
		if is_instance_valid(on_button_glyph_display): # Ensure the node exists
			if is_instance_valid(last_rolled_glyph) and is_instance_valid(last_rolled_glyph.texture):
				on_button_glyph_display.texture = last_rolled_glyph.texture
				on_button_glyph_display.visible = true
				print("Game: Displayed glyph on button: ", last_rolled_glyph.display_name)
			else:
				on_button_glyph_display.visible = false # Hide if glyph or texture invalid
				printerr("Game: Could not display glyph on button - glyph or texture invalid.")
		else:
			printerr("Game: RolledGlyphOnButtonDisplay node not found on roll_button.")

		current_game_state = GameState.RESULT_REVEAL
		print("Game: State changed to RESULT_REVEAL. Starting reveal_on_button_timer.")
		reveal_on_button_timer.start()
	else:
		print("RollAnimationTimer timeout, but not in ROLLING state. State: ", GameState.keys()[current_game_state])

func _perform_roll(): # Selects the glyph
	if current_player_dice.is_empty():
		printerr("CRITICAL: Player dice is empty!")
		# Potentially handle this error more gracefully, e.g., force a default glyph
		return

	var rolled_glyph_index = randi() % current_player_dice.size()
	last_rolled_glyph = current_player_dice[rolled_glyph_index]

	if not is_instance_valid(last_rolled_glyph):
		printerr("CRITICAL: last_rolled_glyph invalid post-roll! Index: ", rolled_glyph_index)

func _on_reveal_on_button_timer_timeout(): # End of RESULT_REVEAL state
	if current_game_state == GameState.RESULT_REVEAL:
		print("Reveal on button timer timeout. State: FANFARE_ANIMATION")
		current_game_state = GameState.FANFARE_ANIMATION
		_start_glyph_fanfare_animation()
	else:
		print("RevealOnButtonTimer timeout, but not in RESULT_REVEAL state. State: ", GameState.keys()[current_game_state])

func _start_glyph_fanfare_animation():
	if not is_instance_valid(last_rolled_glyph):
		printerr("Cannot start fanfare, last_rolled_glyph is invalid.")
		_finalize_roll_logic_and_proceed()
		return

	if is_instance_valid(animating_glyph_node):
		animating_glyph_node.queue_free()
	
	animating_glyph_node = TextureRect.new()
	animating_glyph_node.texture = last_rolled_glyph.texture
	animating_glyph_node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	animating_glyph_node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# Set initial size to match the glyph on the roll button
	animating_glyph_node.custom_minimum_size = ROLL_BUTTON_GLYPH_SIZE 
	animating_glyph_node.size = ROLL_BUTTON_GLYPH_SIZE # Explicitly set size as well

	var on_button_glyph_display = roll_button.get_node_or_null("RolledGlyphOnButtonDisplay")
	if is_instance_valid(on_button_glyph_display):
		# Start from the center of the on_button_glyph_display
		animating_glyph_node.global_position = on_button_glyph_display.global_position - (animating_glyph_node.size / 2.0) + (on_button_glyph_display.size / 2.0)
		on_button_glyph_display.visible = false
	else:
		animating_glyph_node.global_position = roll_button.global_position # Fallback

	if is_instance_valid(ui_canvas): ui_canvas.add_child(animating_glyph_node)
	else: add_child(animating_glyph_node)

	var screen_center = get_viewport_rect().size / 2.0
	var tween_to_center = create_tween()
	# Tween to screen center, adjusting for the animating_glyph_node's own size to center its pivot
	tween_to_center.tween_property(animating_glyph_node, "global_position", screen_center - (animating_glyph_node.size / 2.0), 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	
	# Optional: A slight scale pop effect while moving to center
	# tween_to_center.tween_property(animating_glyph_node, "scale", Vector2(1.1, 1.1), 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# tween_to_center.tween_property(animating_glyph_node, "scale", Vector2(1.0, 1.0), 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


	var score_data = _calculate_score_and_synergies()

	if is_instance_valid(hud_instance) and hud_instance.has_method("play_score_fanfare"):
		hud_instance.play_score_fanfare(score_data.points_from_roll, score_data.points_from_synergy, current_round_score, score_data.synergy_messages, current_success_tier)
	else:
		print("HUD cannot play score fanfare. Manually proceeding.")
		call_deferred("_on_hud_fanfare_animation_finished")

func _start_glyph_to_history_animation():
	if not is_instance_valid(animating_glyph_node) or not is_instance_valid(last_rolled_glyph):
		printerr("Cannot animate glyph to history, node or data invalid.")
		if is_instance_valid(animating_glyph_node): animating_glyph_node.queue_free(); animating_glyph_node = null
		_finalize_roll_logic_and_proceed()
		return

	var target_slot_center_pos: Vector2
	if is_instance_valid(hud_instance) and hud_instance.has_method("get_next_history_slot_global_position"):
		target_slot_center_pos = hud_instance.get_next_history_slot_global_position() # This should return the center
	else:
		printerr("HUD cannot provide history slot position. Using fallback.")
		target_slot_center_pos = Vector2(100, 100) 

	var tween_to_history = create_tween()
	tween_to_history.finished.connect(Callable(self, "_on_glyph_to_history_animation_finished"))

	# Parallel tweening for position and scale
	tween_to_history.set_parallel(true) 
	# Adjust target position to account for the new smaller size to keep it centered in the slot
	var target_visual_pos = target_slot_center_pos - (HISTORY_SLOT_GLYPH_SIZE / 2.0)
	tween_to_history.tween_property(animating_glyph_node, "global_position", target_visual_pos, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	# Tween custom_minimum_size for TextureRect to handle scaling with KEEP_ASPECT_CENTERED
	# Or, if stretch_mode = SCALE, then tween "scale" property.
	# Given stretch_mode = KEEP_ASPECT_CENTERED and expand_mode = IGNORE_SIZE,
	# tweening custom_minimum_size is the correct way to "resize" the visual area.
	tween_to_history.tween_property(animating_glyph_node, "custom_minimum_size", HISTORY_SLOT_GLYPH_SIZE, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# Also tween size property if custom_minimum_size doesn't force it immediately with IGNORE_SIZE
	tween_to_history.tween_property(animating_glyph_node, "size", HISTORY_SLOT_GLYPH_SIZE, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func _calculate_score_and_synergies() -> Dictionary:
	var points_from_roll: int = 0
	var points_from_synergy: int = 0
	var synergy_messages: Array[String] = [] # Changed to Array for multiple messages
	current_success_tier = SuccessTier.NONE # Reset for this roll

	if not is_instance_valid(last_rolled_glyph):
		printerr("Cannot calculate score, last_rolled_glyph is invalid.")
		return {"points_from_roll": 0, "points_from_synergy": 0, "synergy_messages": []}

	# Base score from glyph
	points_from_roll = last_rolled_glyph.value
	if last_rolled_glyph.type == "dice" and active_boons.has("sun_power"):
		points_from_roll += extra_points_per_dice_glyph_boon
		# Consider adding a small message for boon application if desired

	current_round_score += points_from_roll
	total_accumulated_score += points_from_roll

	# Synergies (this part is simplified from your _check_and_apply_synergies)
	# Your original _check_and_apply_synergies modifies current_round_score directly.
	# We need to adapt it to return the bonus and messages.
	var synergy_result = _evaluate_synergies_and_boons() # New helper
	points_from_synergy = synergy_result.bonus_score
	synergy_messages = synergy_result.messages
	
	if points_from_synergy > 0:
		current_round_score += points_from_synergy
		total_accumulated_score += points_from_synergy

	# Determine SuccessTier (example logic)
	var total_this_roll = points_from_roll + points_from_synergy
	if total_this_roll >= 25: current_success_tier = SuccessTier.JACKPOT
	elif total_this_roll >= 15: current_success_tier = SuccessTier.MAJOR
	elif total_this_roll >= 8: current_success_tier = SuccessTier.MEDIUM
	elif total_this_roll > 0: current_success_tier = SuccessTier.MINOR
	
	print("Roll Processed: '", last_rolled_glyph.display_name, "' -> Base:", points_from_roll, " Synergy:", points_from_synergy, " Tier:", SuccessTier.keys()[current_success_tier])
	return {
		"points_from_roll": points_from_roll, 
		"points_from_synergy": points_from_synergy, 
		"synergy_messages": synergy_messages
	}

func _evaluate_synergies_and_boons() -> Dictionary: # Refactored from _check_and_apply_synergies
	var total_synergy_bonus: int = 0
	var messages: Array[String] = [] # Use an array for multiple messages

	if roll_history.is_empty(): # Synergies depend on history, but roll_history isn't updated yet.
		# For the purpose of this function, we consider the current `last_rolled_glyph`
		# as if it's already part of the history for this check.
		# A temporary history could be formed:
		var temp_history = roll_history.duplicate()
		if is_instance_valid(last_rolled_glyph): temp_history.append(last_rolled_glyph)
		else: return {"bonus_score": 0, "messages": []} # Should not happen if last_rolled_glyph is valid
	else:
		# This means roll_history is updated *before* calling this. Let's adjust.
		# The logical roll_history.append(last_rolled_glyph) should happen *before* this.
		# Let's assume it will be. If not, the logic below needs temp_history.
		pass # Using current roll_history

	# --- Synergy 1: Numeric Double ---
	if not synergies_fired_this_round.has("numeric_double"):
		var dice_values_seen: Dictionary = {}
		for roll_data in roll_history: # Iterate over the true roll_history
			if roll_data.type == "dice":
				dice_values_seen[roll_data.value] = dice_values_seen.get(roll_data.value, 0) + 1
				if dice_values_seen[roll_data.value] >= 2:
					total_synergy_bonus += 5
					synergies_fired_this_round["numeric_double"] = true
					messages.append("NUMERIC DOUBLE! +5")
					# play_sound(sfx_synergy_pop) # Sounds handled by HUD or globally based on tier
					break
	# ... (Other synergies: Roman Gathering, Card Pair, Simple Flush - adapt similarly) ...
	# Example for Roman Gathering:
	if not synergies_fired_this_round.has("roman_gathering"):
		var roman_glyph_count: int = 0
		for roll_data in roll_history:
			if roll_data.type == "roman": roman_glyph_count += 1
		if roman_glyph_count >= 2:
			total_synergy_bonus += 10
			synergies_fired_this_round["roman_gathering"] = true
			messages.append("ROMAN GATHERING! +10")
	
	# Card Pair
	if not synergies_fired_this_round.has("card_pair"):
		var card_values_seen: Dictionary = {}
		for roll_data in roll_history:
			if roll_data.type == "card":
				card_values_seen[roll_data.value] = card_values_seen.get(roll_data.value, 0) + 1
				if card_values_seen[roll_data.value] >= 2:
					total_synergy_bonus += 8
					synergies_fired_this_round["card_pair"] = true
					messages.append("CARD PAIR! +8")
					break
	# Simple Flush
	if not synergies_fired_this_round.has("simple_flush"):
		var suit_counts: Dictionary = {"hearts": 0, "diamonds": 0, "clubs": 0, "spades": 0}
		for roll_data in roll_history:
			if roll_data.type == "card" and is_instance_valid(roll_data) and roll_data.suit != "":
				if suit_counts.has(roll_data.suit): suit_counts[roll_data.suit] += 1
		for suit_name in suit_counts:
			if suit_counts[suit_name] >= 3:
				total_synergy_bonus += 15
				synergies_fired_this_round["simple_flush"] = true
				messages.append("FLUSH (%s)! +15" % suit_name.capitalize())
				break

	# --- Check for Rune Phrase Boons ---
	var current_runes_in_history_ids: Array[String] = []
	for roll_data in roll_history:
		if roll_data.type == "rune" and is_instance_valid(roll_data) and roll_data.id != "":
			current_runes_in_history_ids.append(roll_data.id)

	if not current_runes_in_history_ids.is_empty():
		for phrase_key in RUNE_PHRASES:
			var phrase_data = RUNE_PHRASES[phrase_key]
			var phrase_id = phrase_data.id
			if not active_boons.has(phrase_id):
				var all_required_runes_found = true
				for required_rune_id in phrase_data.runes_required:
					if not required_rune_id in current_runes_in_history_ids:
						all_required_runes_found = false
						break
				if all_required_runes_found:
					active_boons[phrase_id] = true
					messages.append("BOON: %s! (%s)" % [phrase_data.display_name, phrase_data.boon_description])
					_apply_boon_effect(phrase_id) # Applies direct effects like extra_max_rolls

	return {"bonus_score": total_synergy_bonus, "messages": messages}


func _on_hud_fanfare_animation_finished(): # Called by signal from HUD
	if current_game_state == GameState.FANFARE_ANIMATION:
		print("HUD fanfare finished. State: GLYPH_TO_HISTORY")
		current_game_state = GameState.GLYPH_TO_HISTORY
		_start_glyph_to_history_animation()
	else:
		print("HUD fanfare finished, but not in FANFARE_ANIMATION state. State: ", GameState.keys()[current_game_state])

func _on_glyph_to_history_animation_finished():
	if is_instance_valid(animating_glyph_node):
		animating_glyph_node.queue_free()
		animating_glyph_node = null

	# Now, tell HUD to actually display the static glyph in its history track
	if is_instance_valid(hud_instance) and hud_instance.has_method("add_glyph_to_visual_history"):
		hud_instance.add_glyph_to_visual_history(last_rolled_glyph)
	
	_finalize_roll_logic_and_proceed()

func _finalize_roll_logic_and_proceed():
	# This is where logical updates that were deferred happen
	if is_instance_valid(last_rolled_glyph): # Ensure it's valid before adding
		roll_history.append(last_rolled_glyph) # IMPORTANT: THIS IS WHERE LOGICAL HISTORY IS UPDATED
	else:
		printerr("Finalize roll: last_rolled_glyph was invalid, not adding to history.")

	rolls_left -= 1
	print("Roll fully finalized. Rolls left: ", rolls_left)
	
	# Update static HUD elements once animations are done
	_update_hud_elements() 

	if rolls_left <= 0:
		current_game_state = GameState.ROUND_SUMMARY
	else:
		current_game_state = GameState.PLAYING # Back to idle/waiting for input
		if is_instance_valid(roll_button): roll_button.disabled = false # Re-enable roll button
	
	# Reset for next roll (if any)
	last_rolled_glyph = null # Clear it after it's fully processed and in history
	# current_success_tier is reset at the start of _calculate_score_and_synergies

# --- Original _process_the_finished_roll_outcome is now effectively dismantled ---
# func _process_the_finished_roll_outcome():
	# ... its logic is now in _perform_roll, _calculate_score_and_synergies, _finalize_roll_logic_and_proceed


# --- Other Callbacks & Helpers (mostly unchanged, review for context) ---

func add_glyph_to_player_dice(glyph_data: GlyphData):
	if glyph_data and glyph_data is GlyphData:
		current_player_dice.append(glyph_data)
		if is_instance_valid(hud_instance): # Update inventory display immediately
			hud_instance.update_dice_inventory_display(current_player_dice)
	else:
		printerr("Attempted to add invalid glyph data.")

func _on_main_menu_start_game():
	if is_instance_valid(main_menu_instance): main_menu_instance.hide_menu()
	current_game_state = GameState.INITIALIZING_GAME

func _prepare_and_show_loot_screen():
	if not is_instance_valid(loot_screen_instance):
		_on_loot_screen_closed() # Skip if no loot screen
		return
	var loot_options = GlyphDB.get_random_loot_options(3)
	if not loot_options.is_empty():
		loot_screen_instance.display_loot_options(loot_options)
		play_sound(sfx_loot_appears)
	else:
		_on_loot_screen_closed() # Skip if no options

func _on_loot_selected(chosen_glyph: GlyphData):
	if is_instance_valid(loot_screen_instance): loot_screen_instance.hide()
	add_glyph_to_player_dice(chosen_glyph)
	current_level += 1
	total_accumulated_score += 50 # Bonus for taking loot
	play_sound(sfx_glyph_added)
	call_deferred("set_game_state_deferred", GameState.INITIALIZING_ROUND)

func _on_loot_screen_closed(): # Called by skip or if no loot
	if is_instance_valid(loot_screen_instance): loot_screen_instance.hide()
	current_level += 1
	call_deferred("set_game_state_deferred", GameState.INITIALIZING_ROUND)

func set_game_state_deferred(new_state: GameState):
	current_game_state = new_state

func _on_hud_inventory_toggled(is_inventory_visible: bool):
	if is_inventory_visible and is_instance_valid(hud_instance):
		hud_instance.update_dice_inventory_display(current_player_dice)

func _on_game_over_retry_pressed():
	if is_instance_valid(game_over_instance): game_over_instance.hide_screen()
	current_game_state = GameState.INITIALIZING_GAME

func _on_game_over_main_menu_pressed():
	if is_instance_valid(game_over_instance): game_over_instance.hide_screen()
	current_game_state = GameState.MENU

func _load_high_score():
	if FileAccess.file_exists(HIGH_SCORE_FILE_PATH):
		var file = FileAccess.open(HIGH_SCORE_FILE_PATH, FileAccess.READ)
		if is_instance_valid(file): high_score = file.get_as_text().to_int(); file.close()
		else: printerr("Failed to open high score file for reading.")
	else: print("No high score file found.")

func _save_high_score():
	var file = FileAccess.open(HIGH_SCORE_FILE_PATH, FileAccess.WRITE)
	if is_instance_valid(file): file.store_string(str(high_score)); file.close()
	else: printerr("Failed to open high score file for writing.")

func _apply_boon_effect(boon_id: String):
	if boon_id == "sun_power":
		extra_points_per_dice_glyph_boon = 2
	elif boon_id == "water_flow":
		extra_max_rolls_boon += 1 # Increment, can stack if boon re-acquired (design choice)
		_update_hud_elements() # Max rolls changed, update HUD
	print("Boon '%s' applied." % boon_id)

func _reset_boons_and_effects():
	active_boons.clear()
	run_score_multiplier_boon = 1.0
	extra_points_per_dice_glyph_boon = 0
	extra_max_rolls_boon = 0
	print("All boons and run-specific effects reset.")

func play_sound(sound_resource: AudioStream, volume: int = 0):
	if not is_instance_valid(sfx_player) or not is_instance_valid(sound_resource): return
	sfx_player.stream = sound_resource
	sfx_player.volume_db = volume
	sfx_player.play()
	
# --- Debug Roll (modified to use the new sequence partially) ---
func _unhandled_input(event: InputEvent):
	if not enable_debug_rolls or not current_game_state == GameState.PLAYING: return
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		var forced_glyph_id: String = ""
		if event.keycode == KEY_1: forced_glyph_id = "rune_sowilo"
		elif event.keycode == KEY_2: forced_glyph_id = "rune_fehu"
		elif event.keycode == KEY_3: forced_glyph_id = "rune_laguz"
		# Add more keys for other runes or specific glyphs

		if forced_glyph_id != "":
			var glyph_to_force = GlyphDB.get_glyph_by_id(forced_glyph_id)
			if is_instance_valid(glyph_to_force):
				print("DEBUG: Forcing roll of: ", glyph_to_force.display_name)
				last_rolled_glyph = glyph_to_force # Pre-set the roll
				
				# Manually trigger parts of the sequence
				current_game_state = GameState.RESULT_REVEAL # Skip ROLLING animation
				
				# Show on button (simplified)
				var on_button_glyph_display = roll_button.get_node_or_null("RolledGlyphOnButtonDisplay")
				if is_instance_valid(on_button_glyph_display):
					on_button_glyph_display.texture = last_rolled_glyph.texture
					on_button_glyph_display.visible = true
				
				reveal_on_button_timer.start() # Start the reveal timer
				get_viewport().set_input_as_handled()
			else:
				printerr("DEBUG: Could not find glyph with ID: ", forced_glyph_id)

func _on_playback_speed_changed(new_speed_multiplier: float):
	Engine.time_scale = new_speed_multiplier
	print("Game: Engine.time_scale changed to ", new_speed_multiplier)
	
	# Optional: Adjust sound pitch (can sound weird)
	# var audio_players = get_tree().get_nodes_in_group("game_sfx_players") # If you group them
	# for player_node in audio_players:
	#    if player_node is AudioStreamPlayer:
	#        (player_node as AudioStreamPlayer).pitch_scale = new_speed_multiplier


# Make sure to add a getter in PlaybackSpeedButton.gd if you use it above:
# In PlaybackSpeedButton.gd:
# func get_current_speed() -> float:
#     return SPEED_OPTIONS[current_speed_index]
