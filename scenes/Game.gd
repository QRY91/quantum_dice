# res://scripts/Game.gd
# TABS FOR INDENTATION
extends Node2D

# --- Game Moment-to-Moment State Enum ---
enum GameRollState { # Renamed from GameState to avoid confusion with GamePhase
	MENU,
	INITIALIZING_GAME,
	INITIALIZING_ROUND,
	PLAYING,
	ROLLING,
	RESULT_REVEAL,
	FANFARE_ANIMATION,
	GLYPH_TO_HISTORY,
	# PROCESSING_ROLL, # Distributed
	LOOT_SELECTION,
	# ROUND_SUMMARY, # Handled by _end_round() now
	GAME_OVER
}
var current_game_roll_state: GameRollState = GameRollState.MENU

# --- Game Progression Phase Enum (NEW) ---
enum GamePhase {
	PRE_BOSS,                 # Initial rounds before first boss
	FIRST_BOSS_ENCOUNTER,
	MID_GAME_CYCLE,           # The 3 normal rounds in the mid-game
	MID_GAME_BOSS_ENCOUNTER
}
var current_game_phase: GamePhase = GamePhase.PRE_BOSS

# --- Success Tier Enum ---
enum SuccessTier { NONE, MINOR, MEDIUM, MAJOR, JACKPOT }
var current_success_tier: SuccessTier = SuccessTier.NONE

var enable_debug_rolls: bool = false

# --- Player's DICE & Roll History ---
var current_player_dice: Array[GlyphData] = []
var roll_history: Array[GlyphData] = [] # Logical history for current round
var last_rolled_glyph: GlyphData = null

# --- Scoring & Progression (Modified/New) ---
var current_round_number: int = 0 # RENAMED from current_level
var player_current_rolls_this_round: int = 0 # NEW (explicit tracking)
var max_rolls_for_current_round: int = 0 # Will be set by new logic
var target_score: int = 0 # Was current_target_score
var current_round_score: int = 0 # Was player_current_score_this_round

var total_accumulated_score: int = 0 # For high score
var high_score: int = 0
const HIGH_SCORE_FILE_PATH: String = "user://quantum_dice_highscore.dat"

# --- Progression Flags (NEW) ---
var is_first_15_roll_round_reached: bool = false
var is_first_boss_defeated: bool = false
var is_cornerstone_slot_3_active: bool = false
var mid_game_cycle_round_counter: int = 0 # Counts 0, 1, 2

# --- Configurable Game Parameters ---
const STARTING_ROLLS_BASE: int = 7 # Base for round 1, will be overridden by progression logic
const BASE_TARGET_SCORE: int = 15
const TARGET_SCORE_PER_ROUND_INCREASE: int = 7 # Renamed from PER_LEVEL
# ROLLS_INCREASE_EVERY_X_LEVELS is replaced by explicit progression logic
const MAX_ROLLS_CAP: int = 15 # Still relevant

const FIRST_BOSS_SCORE_MULTIPLIER: float = 1.25
const MID_GAME_BOSS_SCORE_MULTIPLIER: float = 1.35 # Example
const CORNERSTONE_SLOT_3_BONUS: int = 10

const DESIGN_BLOCK_SIZE: int = 80
const ROLL_BUTTON_GLYPH_SIZE: Vector2 = Vector2(160, 160)
const HISTORY_SLOT_GLYPH_SIZE: Vector2 = Vector2(80, 80)

# --- Synergy Tracking ---
var synergies_fired_this_round: Dictionary = {}

# --- Rune Phrases and Boons ---
# (RUNE_PHRASES, active_boons, boon effect vars remain the same for now)
var RUNE_PHRASES: Dictionary = {
	"SUN_POWER": { "id": "sun_power", "display_name": "Sun's Radiance", "runes_required": ["rune_sowilo", "rune_fehu"], "boon_description": "All 'dice' type glyphs score +2 points for the rest of the run."},
	"WATER_FLOW": { "id": "water_flow", "display_name": "Water's Flow", "runes_required": ["rune_laguz", "rune_ansuz"], "boon_description": "Gain +1 max roll per round for the rest of the run (up to a new cap)."}
}
var active_boons: Dictionary = {}
var run_score_multiplier_boon: float = 1.0
var extra_points_per_dice_glyph_boon: int = 0
var extra_max_rolls_boon: int = 0 # Note: This boon might interact with the new roll progression

# --- Animation Control ---
var animating_glyph_node: TextureRect = null
var reveal_on_button_timer: Timer
const REVEAL_DURATION: float = 0.75

# --- CORE UI Node References ---
@onready var roll_button: TextureButton = $UICanvas/MainGameUI/AnimatedRollButton
@onready var ui_canvas: CanvasLayer = $UICanvas

# --- Scene Preloads & Instances ---
var main_menu_scene: PackedScene = preload("res://scenes/ui/MainMenu.tscn")
@onready var main_menu_instance: Control
var loot_screen_scene: PackedScene = preload("res://scenes/ui/LootScreen.tscn")
@onready var loot_screen_instance: Control
var hud_scene: PackedScene = preload("res://scenes/ui/HUD.tscn")
@onready var hud_instance: Control # Game.gd needs to call functions on this
var game_over_screen_scene: PackedScene = preload("res://scenes/ui/GameOverScreen.tscn")
@onready var game_over_instance: Control

@onready var roll_animation_timer: Timer = $RollAnimationTimer # For ROLLING state duration

# --- Audio ---
@onready var sfx_player: AudioStreamPlayer = $SFXPlayer
# (Sound effect variables remain)
var sfx_synergy_pop: AudioStream = preload("res://assets/sfx/synergy_success.ogg")
var sfx_loot_appears: AudioStream = preload("res://assets/sfx/loot_appears.ogg")
var sfx_glyph_added: AudioStream = preload("res://assets/sfx/glyph_added.ogg")


# --- Auto-Roll and Speed Control ---
@onready var playback_speed_button: TextureButton
var auto_roll_enabled: bool = false
@onready var auto_roll_delay_timer: Timer
@onready var auto_roll_button: TextureButton


func _ready():
	_load_high_score()

	reveal_on_button_timer = Timer.new()
	reveal_on_button_timer.one_shot = true
	reveal_on_button_timer.wait_time = REVEAL_DURATION
	reveal_on_button_timer.timeout.connect(Callable(self, "_on_reveal_on_button_timer_timeout"))
	add_child(reveal_on_button_timer)
	
	auto_roll_delay_timer = Timer.new()
	auto_roll_delay_timer.name = "AutoRollDelayTimer"
	auto_roll_delay_timer.wait_time = 0.25
	auto_roll_delay_timer.one_shot = true
	auto_roll_delay_timer.timeout.connect(Callable(self, "_on_auto_roll_delay_timer_timeout"))
	add_child(auto_roll_delay_timer)

	# HUD Setup
	if hud_scene:
		hud_instance = hud_scene.instantiate()
		if is_instance_valid(ui_canvas): ui_canvas.add_child(hud_instance)
		else: add_child(hud_instance); printerr("UICanvas not found for HUD.")
		
		if hud_instance.has_signal("inventory_toggled"):
			hud_instance.inventory_toggled.connect(Callable(self, "_on_hud_inventory_toggled"))
		if hud_instance.has_signal("fanfare_animation_finished"):
			hud_instance.fanfare_animation_finished.connect(Callable(self, "_on_hud_fanfare_animation_finished"))
		else: printerr("WARNING: HUD.gd needs 'fanfare_animation_finished' signal.")
		hud_instance.visible = false
		
		# Playback Speed Button Connection
		playback_speed_button = hud_instance.get_node_or_null("PlaybackSpeedButton")
		if is_instance_valid(playback_speed_button):
			if playback_speed_button.has_signal("speed_changed"):
				playback_speed_button.speed_changed.connect(Callable(self, "_on_playback_speed_changed"))
				print("Game: Connected to PlaybackSpeedButton's speed_changed signal.")
				if playback_speed_button.has_method("get_current_speed"): Engine.time_scale = playback_speed_button.get_current_speed()
				else: Engine.time_scale = 1.0
			else: printerr("Game: PlaybackSpeedButton NO 'speed_changed' signal.")
		else: printerr("Game: PlaybackSpeedButton node NOT FOUND in HUD.")

		# Auto-Roll Button Connection
		auto_roll_button = hud_instance.get_node_or_null("AutoRollButton") # Ensure this name matches HUD.tscn
		if is_instance_valid(auto_roll_button):
			if auto_roll_button.has_signal("auto_roll_toggled"):
				auto_roll_button.auto_roll_toggled.connect(Callable(self, "_on_auto_roll_toggled"))
				print("Game: Connected to AutoRollButton's auto_roll_toggled signal.")
				if auto_roll_button.has_method("get_current_state"): auto_roll_enabled = auto_roll_button.get_current_state()
			else: printerr("Game: AutoRollButton NO 'auto_roll_toggled' signal.")
		else: printerr("Game: AutoRollButton node NOT FOUND in HUD.")
			
	else:
		printerr("ERROR: HUD.tscn not preloaded!")

	# Main Menu, Loot Screen, Game Over Screen Instantiation (as before)
	if main_menu_scene:
		main_menu_instance = main_menu_scene.instantiate()
		if is_instance_valid(ui_canvas): ui_canvas.add_child(main_menu_instance)
		else: add_child(main_menu_instance)
		if main_menu_instance.has_signal("start_game_pressed"): main_menu_instance.start_game_pressed.connect(Callable(self, "_on_main_menu_start_game"))
	if loot_screen_scene:
		loot_screen_instance = loot_screen_scene.instantiate()
		if is_instance_valid(ui_canvas): ui_canvas.add_child(loot_screen_instance)
		else: add_child(loot_screen_instance)
		if loot_screen_instance.has_signal("loot_selected"): loot_screen_instance.loot_selected.connect(Callable(self, "_on_loot_selected"))
		if loot_screen_instance.has_signal("skip_loot_pressed"): loot_screen_instance.skip_loot_pressed.connect(Callable(self, "_on_loot_screen_closed"))
		loot_screen_instance.hide()
	if game_over_screen_scene:
		game_over_instance = game_over_screen_scene.instantiate()
		if is_instance_valid(ui_canvas): ui_canvas.add_child(game_over_instance)
		else: add_child(game_over_instance)
		if game_over_instance.has_signal("retry_pressed"): game_over_instance.retry_pressed.connect(Callable(self, "_on_game_over_retry_pressed"))
		if game_over_instance.has_signal("main_menu_pressed"): game_over_instance.main_menu_pressed.connect(Callable(self, "_on_game_over_main_menu_pressed"))
		game_over_instance.hide()

	if is_instance_valid(roll_button): roll_button.pressed.connect(Callable(self, "_on_roll_button_pressed"))
	else: printerr("ERROR: RollButton not valid.")
	if is_instance_valid(roll_animation_timer): roll_animation_timer.timeout.connect(Callable(self, "_on_roll_animation_timer_timeout"))
	else: printerr("ERROR: RollAnimationTimer not found.")
	if not is_instance_valid(sfx_player): printerr("ERROR: SFXPlayer node not found!")
		
	current_game_roll_state = GameRollState.MENU
	print("Game scene _ready complete. Initial game roll state set to MENU.")


func _process(delta):
	match current_game_roll_state:
		GameRollState.MENU:
			var main_game_ui_node = get_node_or_null("UICanvas/MainGameUI")
			if is_instance_valid(main_game_ui_node): main_game_ui_node.visible = false
			if is_instance_valid(hud_instance): hud_instance.visible = false
			if is_instance_valid(main_menu_instance): main_menu_instance.show_menu()

		GameRollState.INITIALIZING_GAME:
			_initialize_new_game_session_and_run() # Renamed to reflect it starts the run
			# Transitions to INITIALIZING_ROUND internally

		GameRollState.INITIALIZING_ROUND:
			# This state now primarily waits for _initialize_current_round_setup to finish
			# and then transitions to PLAYING. The setup itself is called by INITIALIZING_GAME
			# or after loot selection.
			# If _initialize_current_round_setup was async, we'd await here.
			# For now, assume it's synchronous.
			# _initialize_current_round_setup() is called, then state becomes PLAYING
			pass # Logic moved to ensure setup completes before PLAYING

		GameRollState.PLAYING:
			var main_game_ui_node = get_node_or_null("UICanvas/MainGameUI")
			if is_instance_valid(main_game_ui_node) and not main_game_ui_node.visible:
				main_game_ui_node.visible = true
			if is_instance_valid(hud_instance) and not hud_instance.visible:
				hud_instance.visible = true
			_update_hud_static_elements() # Renamed from _update_hud_elements
			
			if is_instance_valid(roll_button):
				roll_button.disabled = (player_current_rolls_this_round >= max_rolls_for_current_round) # Check against explicit count

			_try_start_auto_roll()

		GameRollState.ROLLING:
			if is_instance_valid(roll_button): roll_button.disabled = true
			pass

		GameRollState.RESULT_REVEAL:
			pass

		GameRollState.FANFARE_ANIMATION:
			pass

		GameRollState.GLYPH_TO_HISTORY:
			pass
			
		GameRollState.LOOT_SELECTION:
			# Game waits for signals from loot_screen_instance
			pass 
				
		GameRollState.GAME_OVER:
			if is_instance_valid(hud_instance): hud_instance.visible = false
			if total_accumulated_score > high_score:
				high_score = total_accumulated_score
				_save_high_score()
			if is_instance_valid(game_over_instance) and not game_over_instance.visible:
				game_over_instance.show_screen(total_accumulated_score, current_round_number) # Use current_round_number
			pass


# --- Progression Backbone Functions ---

func _initialize_new_game_session_and_run():
	print("Initializing new game session and run...")
	current_round_number = 0 
	total_accumulated_score = 0
	current_player_dice.clear()
	_reset_boons_and_effects()

	is_first_15_roll_round_reached = false
	is_first_boss_defeated = false
	is_cornerstone_slot_3_active = false
	if is_instance_valid(hud_instance) and hud_instance.has_method("update_cornerstone_display"):
		hud_instance.update_cornerstone_display(3, false)
	mid_game_cycle_round_counter = 0 # Reset to 0, will become 1 for the first mid-game round
	current_game_phase = GamePhase.PRE_BOSS

	auto_roll_enabled = false
	if is_instance_valid(auto_roll_button) and auto_roll_button.has_method("set_auto_roll_state"):
		auto_roll_button.set_auto_roll_state(false)
	if is_instance_valid(auto_roll_delay_timer): auto_roll_delay_timer.stop()
	
	if GlyphDB and not GlyphDB.starting_dice_configuration.is_empty():
		current_player_dice = GlyphDB.starting_dice_configuration.duplicate(true)
	else:
		printerr("Game Error: GlyphDB not ready or starting_dice_configuration is empty!")

	if is_instance_valid(hud_instance): hud_instance.reset_full_game_visuals()
	
	_start_new_round()

func _start_new_round():
	current_round_number += 1
	print("--- Starting New Round: %d ---" % current_round_number)

	player_current_rolls_this_round = 0
	current_round_score = 0
	roll_history.clear()
	synergies_fired_this_round.clear()
	last_rolled_glyph = null

	if current_round_number == 1: max_rolls_for_current_round = 7
	elif current_round_number == 2: max_rolls_for_current_round = 10
	elif current_round_number == 3: max_rolls_for_current_round = 12
	else: max_rolls_for_current_round = 15
	max_rolls_for_current_round = min(max_rolls_for_current_round + extra_max_rolls_boon, MAX_ROLLS_CAP + extra_max_rolls_boon)

	target_score = BASE_TARGET_SCORE + (current_round_number - 1) * TARGET_SCORE_PER_ROUND_INCREASE
	var is_this_round_a_boss_encounter: bool = false # Flag for this specific round setup

	# Determine current_game_phase and if this round is a boss encounter
	if not is_first_boss_defeated:
		if is_first_15_roll_round_reached: # Check if the condition to trigger the first boss is met
			current_game_phase = GamePhase.FIRST_BOSS_ENCOUNTER
			is_this_round_a_boss_encounter = true
		else:
			current_game_phase = GamePhase.PRE_BOSS
	else: # First boss has been defeated, proceed to mid-game logic
		# mid_game_cycle_round_counter was incremented by _process_round_win_logic or after loot
		# No, it should be incremented here when starting a new round in mid-game
		if current_game_phase != GamePhase.MID_GAME_BOSS_ENCOUNTER: # If previous wasn't a boss
			mid_game_cycle_round_counter += 1
			
		if mid_game_cycle_round_counter > 3: # Should be >=3 to trigger boss, then reset
			mid_game_cycle_round_counter = 1 # Start new cycle at 1 after a boss

		if mid_game_cycle_round_counter == 3: # This is the 3rd normal round, so NEXT is boss if this is won.
											# OR, if cycle counter is 3, THIS IS THE BOSS ROUND.
			current_game_phase = GamePhase.MID_GAME_BOSS_ENCOUNTER
			is_this_round_a_boss_encounter = true
			# mid_game_cycle_round_counter will be reset to 0 by _process_round_win_logic if boss is "defeated"
			# or when starting the next round after this boss.
		else:
			current_game_phase = GamePhase.MID_GAME_CYCLE
			PlayerNotificationSystem.display_message("Round %d of 3 before next Boss." % mid_game_cycle_round_counter)


	# Apply boss modifiers and notifications
	var boss_indicator_message: String = ""
	var show_boss_indicator_flag: bool = false

	if is_this_round_a_boss_encounter:
		if current_game_phase == GamePhase.FIRST_BOSS_ENCOUNTER:
			target_score = int(float(target_score) * FIRST_BOSS_SCORE_MULTIPLIER)
			PlayerNotificationSystem.display_message("BOSS ENCOUNTER ROUND! (First)")
		elif current_game_phase == GamePhase.MID_GAME_BOSS_ENCOUNTER:
			target_score = int(float(target_score) * MID_GAME_BOSS_SCORE_MULTIPLIER)
			PlayerNotificationSystem.display_message("BOSS ENCOUNTER ROUND (Mid-Game)!")
	else: # Not a boss round, check if NEXT is a boss for indicator
		if current_game_phase == GamePhase.PRE_BOSS:
			if max_rolls_for_current_round == 15 and not is_first_15_roll_round_reached:
				# This current 15-roll round, if won, makes next round the boss
				show_boss_indicator_flag = true
				boss_indicator_message = "Win this 15-roll round to face the First Boss!"
		elif current_game_phase == GamePhase.MID_GAME_CYCLE:
			if mid_game_cycle_round_counter == 2: # This is the 2nd of 3 normal rounds
				show_boss_indicator_flag = true
				boss_indicator_message = "Next Round: Mid-Game Boss!"
	
	if is_instance_valid(hud_instance) and hud_instance.has_method("show_boss_incoming_indicator"):
		hud_instance.show_boss_incoming_indicator(show_boss_indicator_flag, boss_indicator_message)

	print("Round %d initialized. Target: %d. Max Rolls: %d. Game Phase: %s. Mid-Game Cycle: %d" % [current_round_number, target_score, max_rolls_for_current_round, GamePhase.keys()[current_game_phase], mid_game_cycle_round_counter if is_first_boss_defeated else 0])

	if is_instance_valid(hud_instance): 
		hud_instance.reset_round_visuals()
		hud_instance.update_dice_inventory_display(current_player_dice)
	
	current_game_roll_state = GameRollState.PLAYING
	_update_hud_static_elements()

func _process_roll_outcome(score_from_roll: int, score_from_synergy: int): # Called by fanfare logic
	# Score is already added to current_round_score by _calculate_score_and_synergies
	player_current_rolls_this_round += 1
	print("Game: Roll %d/%d processed." % [player_current_rolls_this_round, max_rolls_for_current_round])

	# Check for round end conditions (will be called by _finalize_roll_logic_and_proceed)
	# if player_current_rolls_this_round >= max_rolls_for_current_round or current_round_score >= target_score:
	#    _end_round() # _finalize_roll_logic_and_proceed handles this transition

func _end_round():
	print("Game: Ending Round %d. Score: %d, Target: %d, Rolls Used: %d" % [current_round_number, current_round_score, target_score, player_current_rolls_this_round])
	
	if is_instance_valid(auto_roll_delay_timer): auto_roll_delay_timer.stop() # Stop auto-roll if round ends

	if current_round_score >= target_score: # WIN
		PlayerNotificationSystem.display_message("Round %d Cleared!" % current_round_number)
		_process_round_win_logic() # Handle boss flags, cornerstone
		
		current_game_roll_state = GameRollState.LOOT_SELECTION
		_prepare_and_show_loot_screen()
		# play_sound(sfx_round_win)
	else: # LOSS
		PlayerNotificationSystem.display_message("Round %d Failed." % current_round_number)
		current_game_roll_state = GameRollState.GAME_OVER
		# play_sound(sfx_game_over)

func _process_round_win_logic():
	print("Game: Processing win logic for round ", current_round_number)
	
	var previous_phase = current_game_phase # Store before potential change

	if max_rolls_for_current_round == 15 and not is_first_15_roll_round_reached:
		is_first_15_roll_round_reached = true
		PlayerNotificationSystem.display_message("First 15-roll round completed!")
		print("Game: is_first_15_roll_round_reached set to true.")
		# Next round setup will correctly identify it as FIRST_BOSS_ENCOUNTER if not defeated

	if previous_phase == GamePhase.FIRST_BOSS_ENCOUNTER:
		var boss_condition_met = false
		# Check if player_current_rolls_this_round was exactly max_rolls_for_current_round (i.e. used all rolls)
		# And the round was won (implicit, as we are in _process_round_win_logic)
		if player_current_rolls_this_round == max_rolls_for_current_round and max_rolls_for_current_round == MAX_ROLLS_CAP: # Ensure it was a full 15-roll boss round
			if not roll_history.is_empty(): # Should not be empty if rolls were made
				var final_glyph_in_history = roll_history.back()
				if is_instance_valid(final_glyph_in_history) and final_glyph_in_history.value > 4:
					boss_condition_met = true
					print("Game: First Boss Condition MET! (Final glyph value > 4 on 15th roll)")
				else:
					print("Game: First Boss Condition FAILED (Final glyph value <= 4 or invalid). Final glyph: ", final_glyph_in_history)
			else:
				print("Game: First Boss Condition FAILED (Roll history empty despite using all rolls - logical error).")
		else:
			print("Game: First Boss Condition FAILED (Round ended before using all %d rolls, or not a 15-roll round). Rolls made: %d" % [max_rolls_for_current_round, player_current_rolls_this_round])
			
		if boss_condition_met:
			is_first_boss_defeated = true
			is_cornerstone_slot_3_active = true
			PlayerNotificationSystem.display_message("FIRST BOSS DEFEATED! Cornerstone Slot 3 Activated!")
			print("Game: is_first_boss_defeated & is_cornerstone_slot_3_active set to true.")
			if is_instance_valid(hud_instance) and hud_instance.has_method("update_cornerstone_display"):
				hud_instance.update_cornerstone_display(3, true)
			current_game_phase = GamePhase.MID_GAME_CYCLE # Transition phase
			mid_game_cycle_round_counter = 0 # Reset for the cycle that STARTS next round
		else:
			PlayerNotificationSystem.display_message("Boss challenge condition missed, but round cleared!")
			# current_game_phase remains FIRST_BOSS_ENCOUNTER, will re-trigger in _start_new_round

	elif previous_phase == GamePhase.MID_GAME_BOSS_ENCOUNTER:
		PlayerNotificationSystem.display_message("Mid-Game Boss Defeated! (Placeholder)")
		print("Game: Mid-Game Boss defeated.")
		current_game_phase = GamePhase.MID_GAME_CYCLE # Transition phase
		mid_game_cycle_round_counter = 0 # Reset for the cycle that STARTS next round

	# If it was a normal PRE_BOSS or MID_GAME_CYCLE round that was won,
	# current_game_phase is handled by _start_new_round based on flags.

func _update_hud_static_elements(): # Renamed from _update_hud_elements
	if not is_instance_valid(hud_instance): return
	hud_instance.update_rolls_display(max_rolls_for_current_round - player_current_rolls_this_round, max_rolls_for_current_round)
	hud_instance.update_score_target_display(current_round_score, target_score)
	hud_instance.update_level_display(current_round_number) # Use current_round_number
	# hud_instance.update_last_rolled_glyph_display(last_rolled_glyph) # Handled by fanfare

# --- Roll Sequence (largely same, but calls _process_roll_outcome and _finalize_roll_logic_and_proceed) ---

func _on_roll_button_pressed():
	if current_game_roll_state == GameRollState.PLAYING and (max_rolls_for_current_round - player_current_rolls_this_round) > 0 : # Check explicit count
		print("Roll button pressed. State: ROLLING")
		current_game_roll_state = GameRollState.ROLLING
		if is_instance_valid(roll_button): roll_button.disabled = true
		if is_instance_valid(hud_instance) and hud_instance.has_method("start_roll_button_animation"):
			hud_instance.start_roll_button_animation()
		var on_button_glyph_display = roll_button.get_node_or_null("RolledGlyphOnButtonDisplay")
		if is_instance_valid(on_button_glyph_display): on_button_glyph_display.visible = false
		roll_animation_timer.start()
	else:
		print("Cannot roll. State:%s, Rolls left:%d" % [GameRollState.keys()[current_game_roll_state], (max_rolls_for_current_round - player_current_rolls_this_round)])

func _on_roll_animation_timer_timeout():
	if current_game_roll_state == GameRollState.ROLLING:
		_perform_roll()
		if not is_instance_valid(last_rolled_glyph):
			printerr("Perform roll resulted in invalid glyph. Aborting roll sequence.")
			current_game_roll_state = GameRollState.PLAYING
			if is_instance_valid(roll_button): roll_button.disabled = not (player_current_rolls_this_round >= max_rolls_for_current_round)
			return

		# IMPORTANT: Logical history is updated here for synergy checks for the *current* roll
		# roll_history.append(last_rolled_glyph) # Moved to _finalize_roll_logic_and_proceed
		# print("Game: last_rolled_glyph '", last_rolled_glyph.display_name, "' added to roll_history. History size: ", roll_history.size())
		# No, for synergy checks, it should be added before _calculate_score_and_synergies.
		# Let's add it in _start_glyph_fanfare_animation right before _calculate_score_and_synergies,
		# or ensure _calculate_score_and_synergies uses a temp history including it.
		# For now, _evaluate_synergies_and_boons uses current roll_history which is from *previous* rolls.
		# This needs careful review based on desired synergy timing.
		# PLAN: _finalize_roll_logic_and_proceed will add to the *permanent* roll_history.
		# _evaluate_synergies_and_boons will use a temporary history for the current check:
		# var temp_history = roll_history.duplicate(); temp_history.append(last_rolled_glyph)

		if is_instance_valid(hud_instance) and hud_instance.has_method("stop_roll_button_animation_show_result"):
			hud_instance.stop_roll_button_animation_show_result(last_rolled_glyph) 
		var on_button_glyph_display = roll_button.get_node_or_null("RolledGlyphOnButtonDisplay")
		if is_instance_valid(on_button_glyph_display):
			if is_instance_valid(last_rolled_glyph) and is_instance_valid(last_rolled_glyph.texture):
				on_button_glyph_display.texture = last_rolled_glyph.texture
				on_button_glyph_display.visible = true
			else: on_button_glyph_display.visible = false
		current_game_roll_state = GameRollState.RESULT_REVEAL
		reveal_on_button_timer.start()
	else:
		print("RollAnimationTimer timeout, but not in ROLLING state.")

func _perform_roll():
	if current_player_dice.is_empty(): printerr("CRITICAL: Player dice is empty!"); return
	var rolled_glyph_index = randi() % current_player_dice.size()
	last_rolled_glyph = current_player_dice[rolled_glyph_index]
	if not is_instance_valid(last_rolled_glyph): printerr("CRITICAL: last_rolled_glyph invalid post-roll!")

func _on_reveal_on_button_timer_timeout():
	if current_game_roll_state == GameRollState.RESULT_REVEAL:
		current_game_roll_state = GameRollState.FANFARE_ANIMATION
		_start_glyph_fanfare_animation()
	else: print("RevealOnButtonTimer timeout, but not in RESULT_REVEAL state.")

func _start_glyph_fanfare_animation():
	if not is_instance_valid(last_rolled_glyph):
		_finalize_roll_logic_and_proceed(); return
	if is_instance_valid(animating_glyph_node): animating_glyph_node.queue_free()
	
	animating_glyph_node = TextureRect.new()
	animating_glyph_node.texture = last_rolled_glyph.texture
	animating_glyph_node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	animating_glyph_node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	animating_glyph_node.custom_minimum_size = ROLL_BUTTON_GLYPH_SIZE 
	animating_glyph_node.size = ROLL_BUTTON_GLYPH_SIZE

	var on_button_glyph_display = roll_button.get_node_or_null("RolledGlyphOnButtonDisplay")
	if is_instance_valid(on_button_glyph_display):
		animating_glyph_node.global_position = on_button_glyph_display.global_position - (animating_glyph_node.size / 2.0) + (on_button_glyph_display.size / 2.0)
		on_button_glyph_display.visible = false
	else: animating_glyph_node.global_position = roll_button.global_position
	if is_instance_valid(ui_canvas): ui_canvas.add_child(animating_glyph_node)
	else: add_child(animating_glyph_node)

	var screen_center = get_viewport_rect().size / 2.0
	var tween_to_center = create_tween()
	tween_to_center.tween_property(animating_glyph_node, "global_position", screen_center - (animating_glyph_node.size / 2.0), 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	
	# IMPORTANT: For synergy check, use a temporary history that includes the current last_rolled_glyph
	var temp_history_for_synergy_check = roll_history.duplicate(true) # Deep copy if GlyphData are objects
	temp_history_for_synergy_check.append(last_rolled_glyph)
	
	var score_data = _calculate_score_and_synergies(temp_history_for_synergy_check) # Pass temp history

	if is_instance_valid(hud_instance) and hud_instance.has_method("play_score_fanfare"):
		hud_instance.play_score_fanfare(score_data.points_from_roll, score_data.points_from_synergy, current_round_score, score_data.synergy_messages, current_success_tier)
	else:
		call_deferred("_on_hud_fanfare_animation_finished")


func _calculate_score_and_synergies(p_history_for_check: Array[GlyphData]) -> Dictionary: # Takes history for check
	var points_from_roll: int = 0
	var points_from_synergy: int = 0
	var synergy_messages: Array[String] = []
	current_success_tier = SuccessTier.NONE

	if not is_instance_valid(last_rolled_glyph):
		return {"points_from_roll": 0, "points_from_synergy": 0, "synergy_messages": []}

	points_from_roll = last_rolled_glyph.value
	if last_rolled_glyph.type == "dice" and active_boons.has("sun_power"):
		points_from_roll += extra_points_per_dice_glyph_boon
	
	# V. Cornerstone Slot 3 Placeholder Effect
	# current_visual_history_index in HUD is 0-indexed for the *next* slot.
	# So, if roll_history (logical) has N items, the current glyph is for slot N-1.
	var current_logical_slot_index = p_history_for_check.size() - 1 # 0-indexed
	if is_cornerstone_slot_3_active and current_logical_slot_index == 2: # Slot 3 is index 2
		points_from_roll += CORNERSTONE_SLOT_3_BONUS # Add to roll points or make separate
		PlayerNotificationSystem.display_message("Cornerstone Slot 3 Bonus: +%d Score!" % CORNERSTONE_SLOT_3_BONUS)
		print("Game: Cornerstone Slot 3 bonus applied.")

	current_round_score += points_from_roll # Apply base/boon/cornerstone points from roll
	# total_accumulated_score is updated after synergy points too

	var synergy_result = _evaluate_synergies_and_boons(p_history_for_check) # Use passed history
	points_from_synergy = synergy_result.bonus_score
	synergy_messages = synergy_result.messages
	
	if points_from_synergy > 0:
		current_round_score += points_from_synergy
	
	total_accumulated_score += points_from_roll + points_from_synergy # Update total run score

	var total_this_roll = points_from_roll + points_from_synergy
	if total_this_roll >= 25: current_success_tier = SuccessTier.JACKPOT
	elif total_this_roll >= 15: current_success_tier = SuccessTier.MAJOR
	elif total_this_roll >= 8: current_success_tier = SuccessTier.MEDIUM
	elif total_this_roll > 0: current_success_tier = SuccessTier.MINOR
	
	# Call _process_roll_outcome here to increment player_current_rolls_this_round
	_process_roll_outcome(points_from_roll, points_from_synergy) # Pass scores for potential logging

	return {
		"points_from_roll": points_from_roll, 
		"points_from_synergy": points_from_synergy, 
		"synergy_messages": synergy_messages
	}

func _evaluate_synergies_and_boons(p_history_for_check: Array[GlyphData]) -> Dictionary:
	var total_synergy_bonus: int = 0
	var messages: Array[String] = []
	if p_history_for_check.is_empty(): return {"bonus_score": 0, "messages": []}

	# --- Synergies use p_history_for_check ---
	# Numeric Double
	if not synergies_fired_this_round.has("numeric_double"):
		var dice_values_seen: Dictionary = {}
		for roll_data in p_history_for_check:
			if roll_data.type == "dice":
				dice_values_seen[roll_data.value] = dice_values_seen.get(roll_data.value, 0) + 1
				if dice_values_seen[roll_data.value] >= 2:
					total_synergy_bonus += 5; synergies_fired_this_round["numeric_double"] = true; messages.append("NUMERIC DOUBLE! +5"); break
	# Roman Gathering
	if not synergies_fired_this_round.has("roman_gathering"):
		var roman_glyph_count: int = 0
		for roll_data in p_history_for_check:
			if roll_data.type == "roman": roman_glyph_count += 1
		if roman_glyph_count >= 2:
			total_synergy_bonus += 10; synergies_fired_this_round["roman_gathering"] = true; messages.append("ROMAN GATHERING! +10")
	# Card Pair
	if not synergies_fired_this_round.has("card_pair"):
		var card_values_seen: Dictionary = {}
		for roll_data in p_history_for_check:
			if roll_data.type == "card":
				card_values_seen[roll_data.value] = card_values_seen.get(roll_data.value, 0) + 1
				if card_values_seen[roll_data.value] >= 2:
					total_synergy_bonus += 8; synergies_fired_this_round["card_pair"] = true; messages.append("CARD PAIR! +8"); break
	# Simple Flush
	if not synergies_fired_this_round.has("simple_flush"):
		var suit_counts: Dictionary = {"hearts":0,"diamonds":0,"clubs":0,"spades":0}
		for roll_data in p_history_for_check:
			if roll_data.type == "card" and is_instance_valid(roll_data) and roll_data.suit != "":
				if suit_counts.has(roll_data.suit): suit_counts[roll_data.suit] += 1
		for suit_name in suit_counts:
			if suit_counts[suit_name] >= 3:
				total_synergy_bonus += 15; synergies_fired_this_round["simple_flush"] = true; messages.append("FLUSH (%s)! +15" % suit_name.capitalize()); break

	# --- Rune Phrase Boons (use p_history_for_check) ---
	var current_runes_in_history_ids: Array[String] = []
	for roll_data in p_history_for_check:
		if roll_data.type == "rune" and is_instance_valid(roll_data) and roll_data.id != "":
			current_runes_in_history_ids.append(roll_data.id)
	if not current_runes_in_history_ids.is_empty():
		for phrase_key in RUNE_PHRASES:
			var phrase_data = RUNE_PHRASES[phrase_key]
			var phrase_id = phrase_data.id
			if not active_boons.has(phrase_id):
				var all_required_runes_found = true
				for required_rune_id in phrase_data.runes_required:
					if not required_rune_id in current_runes_in_history_ids: all_required_runes_found = false; break
				if all_required_runes_found:
					active_boons[phrase_id] = true; messages.append("BOON: %s! (%s)" % [phrase_data.display_name, phrase_data.boon_description]); _apply_boon_effect(phrase_id)
	return {"bonus_score": total_synergy_bonus, "messages": messages}

func _on_hud_fanfare_animation_finished():
	if current_game_roll_state == GameRollState.FANFARE_ANIMATION:
		current_game_roll_state = GameRollState.GLYPH_TO_HISTORY
		_start_glyph_to_history_animation()
	else: print("HUD fanfare finished, but not in FANFARE_ANIMATION state.")

func _start_glyph_to_history_animation(): # Largely unchanged, uses HISTORY_SLOT_GLYPH_SIZE
	if not is_instance_valid(animating_glyph_node) or not is_instance_valid(last_rolled_glyph):
		if is_instance_valid(animating_glyph_node): animating_glyph_node.queue_free(); animating_glyph_node = null
		_finalize_roll_logic_and_proceed(); return
	var target_slot_center_pos: Vector2
	if is_instance_valid(hud_instance) and hud_instance.has_method("get_next_history_slot_global_position"):
		target_slot_center_pos = hud_instance.get_next_history_slot_global_position()
	else: target_slot_center_pos = Vector2(100, 100) 
	var tween_to_history = create_tween()
	tween_to_history.finished.connect(Callable(self, "_on_glyph_to_history_animation_finished"))
	tween_to_history.set_parallel(true) 
	var target_visual_pos = target_slot_center_pos - (HISTORY_SLOT_GLYPH_SIZE / 2.0)
	tween_to_history.tween_property(animating_glyph_node, "global_position", target_visual_pos, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween_to_history.tween_property(animating_glyph_node, "custom_minimum_size", HISTORY_SLOT_GLYPH_SIZE, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween_to_history.tween_property(animating_glyph_node, "size", HISTORY_SLOT_GLYPH_SIZE, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _on_glyph_to_history_animation_finished():
	if is_instance_valid(animating_glyph_node):
		animating_glyph_node.queue_free(); animating_glyph_node = null
	if is_instance_valid(hud_instance) and hud_instance.has_method("add_glyph_to_visual_history"):
		hud_instance.add_glyph_to_visual_history(last_rolled_glyph) # HUD updates its visual track
	_finalize_roll_logic_and_proceed()

func _finalize_roll_logic_and_proceed():
	if is_instance_valid(last_rolled_glyph):
		roll_history.append(last_rolled_glyph) # Add to permanent logical history for the round
		print("Game: '%s' added to final roll_history. Size: %d" % [last_rolled_glyph.display_name, roll_history.size()])
	else: printerr("Finalize roll: last_rolled_glyph was invalid.")

	# player_current_rolls_this_round was already incremented in _process_roll_outcome (called by _calculate_score_and_synergies)
	print("Roll fully finalized. Rolls used this round: %d/%d. Round Score: %d" % [player_current_rolls_this_round, max_rolls_for_current_round, current_round_score])
	
	last_rolled_glyph = null # Clear for next roll
	_update_hud_static_elements() # Update HUD with latest numbers

	# Check round end conditions
	if player_current_rolls_this_round >= max_rolls_for_current_round or current_round_score >= target_score:
		_end_round()
	else: # Round continues
		current_game_roll_state = GameRollState.PLAYING
		if is_instance_valid(roll_button): roll_button.disabled = false
		_try_start_auto_roll()


# --- Other Callbacks & Helpers (largely unchanged, but review paths/names) ---
func add_glyph_to_player_dice(glyph_data: GlyphData):
	if glyph_data and glyph_data is GlyphData:
		current_player_dice.append(glyph_data)
		if is_instance_valid(hud_instance):
			hud_instance.update_dice_inventory_display(current_player_dice)
	else: printerr("Attempted to add invalid glyph data.")

func _on_main_menu_start_game():
	if is_instance_valid(main_menu_instance): main_menu_instance.hide_menu()
	current_game_roll_state = GameRollState.INITIALIZING_GAME # Will call _initialize_new_game_session_and_run

func _prepare_and_show_loot_screen():
	if not is_instance_valid(loot_screen_instance): _start_new_round(); return # Skip loot if no screen
	var loot_options = GlyphDB.get_random_loot_options(3)
	if not loot_options.is_empty():
		loot_screen_instance.display_loot_options(loot_options)
		play_sound(sfx_loot_appears)
	else: # No loot options, proceed to next round
		PlayerNotificationSystem.display_message("No loot options available this time.")
		_start_new_round()


# Let's adjust the state transitions for loot/skip:
func _on_loot_selected(chosen_glyph: GlyphData):
	if is_instance_valid(loot_screen_instance): loot_screen_instance.hide()
	add_glyph_to_player_dice(chosen_glyph)
	total_accumulated_score += 50 
	play_sound(sfx_glyph_added)
	# _start_new_round() # Directly calling this might be too soon if states are changing
	current_game_roll_state = GameRollState.INITIALIZING_ROUND # Set state
	# _process will then call _start_new_round when it hits this state.
	# Actually, _initialize_new_game_session_and_run calls _start_new_round.
	# After loot, we just need to trigger the setup for the next round.
	call_deferred("_start_new_round") # Deferring is safer

func _on_loot_screen_closed():
	if is_instance_valid(loot_screen_instance): loot_screen_instance.hide()
	PlayerNotificationSystem.display_message("Loot skipped.")
	# _start_new_round()
	call_deferred("_start_new_round")

func _on_hud_inventory_toggled(is_inventory_visible: bool):
	if is_inventory_visible and is_instance_valid(hud_instance):
		hud_instance.update_dice_inventory_display(current_player_dice)

func _on_game_over_retry_pressed():
	if is_instance_valid(game_over_instance): game_over_instance.hide_screen()
	current_game_roll_state = GameRollState.INITIALIZING_GAME

func _on_game_over_main_menu_pressed():
	if is_instance_valid(game_over_instance): game_over_instance.hide_screen()
	current_game_roll_state = GameRollState.MENU

func _load_high_score():
	if FileAccess.file_exists(HIGH_SCORE_FILE_PATH):
		var file = FileAccess.open(HIGH_SCORE_FILE_PATH, FileAccess.READ)
		if is_instance_valid(file): high_score = file.get_as_text().to_int(); file.close()
	else: print("No high score file found.")

func _save_high_score():
	var file = FileAccess.open(HIGH_SCORE_FILE_PATH, FileAccess.WRITE)
	if is_instance_valid(file): file.store_string(str(high_score)); file.close()
	else: printerr("Failed to open high score file for writing.")

func _apply_boon_effect(boon_id: String):
	if boon_id == "sun_power": extra_points_per_dice_glyph_boon = 2
	elif boon_id == "water_flow":
		extra_max_rolls_boon += 1
		_update_hud_static_elements() # Max rolls might have changed
	print("Boon '%s' applied." % boon_id)

func _reset_boons_and_effects():
	active_boons.clear(); run_score_multiplier_boon = 1.0
	extra_points_per_dice_glyph_boon = 0; extra_max_rolls_boon = 0
	print("All boons and run-specific effects reset.")

func play_sound(sound_resource: AudioStream, volume: int = 0):
	if not is_instance_valid(sfx_player) or not is_instance_valid(sound_resource): return
	sfx_player.stream = sound_resource; sfx_player.volume_db = volume; sfx_player.play()
	
func _on_playback_speed_changed(new_speed_multiplier: float):
	Engine.time_scale = new_speed_multiplier
	print("Game: Engine.time_scale changed to ", new_speed_multiplier)

func _on_auto_roll_toggled(is_enabled: bool):
	auto_roll_enabled = is_enabled
	print("Game: _on_auto_roll_toggled. auto_roll_enabled set to: ", auto_roll_enabled, ". Current GameRollState: ", GameRollState.keys()[current_game_roll_state])
	if auto_roll_enabled:
		print("Game: Auto-roll is now ON, calling _try_start_auto_roll().")
		_try_start_auto_roll()
	else:
		if is_instance_valid(auto_roll_delay_timer) and not auto_roll_delay_timer.is_stopped():
			auto_roll_delay_timer.stop(); print("Game: Auto-roll disabled, pending delay timer stopped.")

func _try_start_auto_roll():
	# No "CALLED" print here, as it's too frequent from _process
	
	var can_auto_roll: bool = true
	var reason: String = "Initial: Conditions met."

	if not auto_roll_enabled: can_auto_roll = false; reason = "Auto-roll not enabled."
	elif current_game_roll_state != GameRollState.PLAYING: can_auto_roll = false; reason = "Not in PLAYING state. Current state: " + GameRollState.keys()[current_game_roll_state]
	elif (max_rolls_for_current_round - player_current_rolls_this_round) <= 0 : can_auto_roll = false; reason = "No rolls left."
	elif not is_instance_valid(roll_button): can_auto_roll = false; reason = "Roll button instance is not valid."
	elif roll_button.disabled: can_auto_roll = false; reason = "Roll button is disabled."
	elif not is_instance_valid(auto_roll_delay_timer): can_auto_roll = false; reason = "Auto-roll delay timer instance not valid."
	elif not auto_roll_delay_timer.is_stopped(): can_auto_roll = false; reason = "Auto-roll delay timer is already running."
		
	if can_auto_roll:
		# Removed the OS.get_stack() part from the print
		print("Game: _try_start_auto_roll: All conditions MET, starting delay timer.") 
		auto_roll_delay_timer.start()
	else:
		# Only print this if the timer IS stopped, meaning some other condition failed,
		# and we are in a state where we might expect it to start.
		if is_instance_valid(auto_roll_delay_timer) and auto_roll_delay_timer.is_stopped() and \
		   auto_roll_enabled and current_game_roll_state == GameRollState.PLAYING and \
		   (max_rolls_for_current_round - player_current_rolls_this_round) > 0 and not roll_button.disabled:
			print("Game: _try_start_auto_roll: Conditions NOT met (and timer stopped, but should be able to roll). Reason: ", reason)
		# else:
			# Silently ignore if timer is already running or other conditions like not being in PLAYING state
			# This reduces log spam for the "timer already running" case from _process.
			pass

func _on_auto_roll_delay_timer_timeout():
	print("Game: Auto-roll delay timer timeout.")
	var can_perform_auto_roll: bool = true; var reason: String = "Conditions met for performing roll."
	if not auto_roll_enabled: can_perform_auto_roll = false; reason = "Auto-roll not enabled at timeout."
	elif current_game_roll_state != GameRollState.PLAYING: can_perform_auto_roll = false; reason = "Not in PLAYING state at timeout. Current state: " + GameRollState.keys()[current_game_roll_state]
	elif (max_rolls_for_current_round - player_current_rolls_this_round) <= 0: can_perform_auto_roll = false; reason = "No rolls left at timeout." # Check explicit count
	elif not is_instance_valid(roll_button): can_perform_auto_roll = false; reason = "Roll button instance not valid at timeout."
	elif roll_button.disabled: can_perform_auto_roll = false; reason = "Roll button is disabled at timeout."
	if can_perform_auto_roll:
		print("Game: Performing auto-roll via _on_roll_button_pressed().")
		_on_roll_button_pressed()
	else:
		print("Game: Auto-roll conditions NOT met on timer timeout. Reason: ", reason)
		if auto_roll_enabled and current_game_roll_state == GameRollState.PLAYING and (max_rolls_for_current_round - player_current_rolls_this_round) > 0:
			_try_start_auto_roll() # Re-queue

# Debug roll - needs update if used
func _unhandled_input(event: InputEvent):
	if not enable_debug_rolls or not current_game_roll_state == GameRollState.PLAYING: return
	# ... (debug roll logic would need to adapt to new state machine) ...
	pass
