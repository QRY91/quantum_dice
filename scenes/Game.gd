# res://scripts/Game.gd
class_name Game # Keep this for RollAnimationController to access Game.ROLL_BUTTON_GLYPH_SIZE
extends Node2D

# --- Game Moment-to-Moment State Enum ---
enum GameRollState {
	MENU,
	INITIALIZING_GAME,
	INITIALIZING_ROUND,
	PLAYING,
	AWAITING_ANIMATION_COMPLETION,
	LOOT_SELECTION,
	GAME_OVER
}
var current_game_roll_state: GameRollState = GameRollState.MENU

# --- Game Progression Phase Enum ---
enum GamePhase {
	PRE_BOSS,
	FIRST_BOSS_ENCOUNTER,
	MID_GAME_CYCLE,
	MID_GAME_BOSS_ENCOUNTER
}
# This variable will be synced with ProgressionManager's state
var current_game_phase_local: GamePhase = GamePhase.PRE_BOSS


# --- Success Tier Enum ---
enum SuccessTier { NONE, MINOR, MEDIUM, MAJOR, JACKPOT }
var current_success_tier: SuccessTier = SuccessTier.NONE

var enable_debug_rolls: bool = false

# --- Player's DICE & Roll History ---
var roll_history: Array[GlyphData] = []
var last_rolled_glyph: GlyphData = null

# --- Round Parameters (Set by ProgressionManager) ---
var current_round_number_local: int = 0 # Synced from ProgressionManager
var player_current_rolls_this_round: int = 0
var max_rolls_for_current_round: int = 0
var target_score_for_current_round: int = 0 # Renamed from target_score

# --- Configurable Game Parameters (Some moved to ProgressionManager) ---
const CORNERSTONE_SLOT_3_BONUS: int = 10 # Kept here for direct application
const DESIGN_BLOCK_SIZE: int = 80
const ROLL_BUTTON_GLYPH_SIZE: Vector2 = Vector2(160, 160)
const HISTORY_SLOT_GLYPH_SIZE: Vector2 = Vector2(80, 80)

# --- Synergy Tracking & Boons (Kept in Game.gd for now, could be next refactor) ---
var synergies_fired_this_round: Dictionary = {}
var run_score_multiplier_boon: float = 1.0 # Example, if Game.gd used this directly
var extra_points_per_dice_glyph_boon: int = 0 # Game.gd uses this in _calculate_score_and_synergies
var extra_max_rolls_boon: int = 0       # Game.gd uses this in _start_new_round_setup
var active_boons: Dictionary = {} # Game.gd's list of *which* boons are active (IDs)
								# This is set by _evaluate_synergies_and_boons
								# based on BoonManager's activation.


# --- Animation Control ---
@onready var roll_animation_controller: Node

# --- CORE UI Node References ---
@onready var roll_button: TextureButton = $UICanvas/MainGameUI/AnimatedRollButton
@onready var ui_canvas: CanvasLayer = $UICanvas

# HUD instance is still needed directly by Game.gd for gameplay UI updates
var hud_scene: PackedScene = preload("res://scenes/ui/HUD.tscn")
@onready var hud_instance: Control 

@onready var roll_animation_timer: Timer = $RollAnimationTimer

# --- Audio ---
@onready var sfx_player: AudioStreamPlayer = $SFXPlayer
var sfx_synergy_pop: AudioStream = preload("res://assets/sfx/synergy_success.ogg")
var sfx_loot_appears: AudioStream = preload("res://assets/sfx/loot_appears.ogg")
var sfx_glyph_added: AudioStream = preload("res://assets/sfx/glyph_added.ogg")

# --- Auto-Roll and Speed Control ---
@onready var playback_speed_button: TextureButton
var auto_roll_enabled: bool = false
@onready var auto_roll_delay_timer: Timer
@onready var auto_roll_button: TextureButton


func _ready():
# Get reference to the RollAnimationController node
	roll_animation_controller = get_node_or_null("RollAnimationController")
	if not is_instance_valid(roll_animation_controller):
		printerr("CRITICAL: RollAnimationController node not found in Game.tscn!")
	else:
		print("Game: RollAnimationController node found.")
		# Connect to its signals
		if roll_animation_controller.has_signal("logical_roll_requested"):
			roll_animation_controller.logical_roll_requested.connect(Callable(self, "_on_rac_logical_roll_requested"))
		else: printerr("ERROR: RollAnimationController missing 'logical_roll_requested' signal.")
		
		if roll_animation_controller.has_signal("fanfare_start_requested"):
			roll_animation_controller.fanfare_start_requested.connect(Callable(self, "_on_rac_fanfare_start_requested"))
		else: printerr("ERROR: RollAnimationController missing 'fanfare_start_requested' signal.")

		if roll_animation_controller.has_signal("move_to_history_requested"):
			roll_animation_controller.move_to_history_requested.connect(Callable(self, "_on_rac_move_to_history_requested"))
		else: printerr("ERROR: RollAnimationController missing 'move_to_history_requested' signal.")

		if roll_animation_controller.has_signal("full_animation_sequence_complete"):
			roll_animation_controller.full_animation_sequence_complete.connect(Callable(self, "_on_rac_full_animation_sequence_complete"))
		else: printerr("ERROR: RollAnimationController missing 'full_animation_sequence_complete' signal.")

		# Setup references for the controller
		if roll_animation_controller.has_method("setup_references"):
			roll_animation_controller.setup_references(roll_button, ui_canvas, hud_instance)
	
	auto_roll_delay_timer = Timer.new(); auto_roll_delay_timer.name = "AutoRollDelayTimer"
	auto_roll_delay_timer.wait_time = 0.25; auto_roll_delay_timer.one_shot = true
	auto_roll_delay_timer.timeout.connect(Callable(self, "_on_auto_roll_delay_timer_timeout")); add_child(auto_roll_delay_timer)

# Set UI Parent for SceneUIManager
	if is_instance_valid(ui_canvas):
		SceneUIManager.set_ui_parent_node(ui_canvas)
	else:
		printerr("Game: CRITICAL - ui_canvas node not found, cannot set parent for SceneUIManager!")
		SceneUIManager.set_ui_parent_node(self) # Fallback, less ideal

	# HUD Setup
	if hud_scene:
		hud_instance = hud_scene.instantiate()
		if is_instance_valid(ui_canvas): ui_canvas.add_child(hud_instance)
		else: add_child(hud_instance); printerr("UICanvas not found for HUD.")
		if hud_instance.has_signal("inventory_toggled"): hud_instance.inventory_toggled.connect(Callable(self, "_on_hud_inventory_toggled"))
		if hud_instance.has_signal("fanfare_animation_finished"): hud_instance.fanfare_animation_finished.connect(Callable(self, "_on_hud_fanfare_animation_finished"))
		else: printerr("WARNING: HUD.gd needs 'fanfare_animation_finished' signal.")
		hud_instance.visible = false
		
		playback_speed_button = hud_instance.get_node_or_null("PlaybackSpeedButton")
		if is_instance_valid(playback_speed_button) and playback_speed_button.has_signal("speed_changed"):
			playback_speed_button.speed_changed.connect(Callable(self, "_on_playback_speed_changed"))
			if playback_speed_button.has_method("get_current_speed"): Engine.time_scale = playback_speed_button.get_current_speed()
			else: Engine.time_scale = 1.0
		auto_roll_button = hud_instance.get_node_or_null("AutoRollButton")
		if is_instance_valid(auto_roll_button) and auto_roll_button.has_signal("auto_roll_toggled"):
			auto_roll_button.auto_roll_toggled.connect(Callable(self, "_on_auto_roll_toggled"))
			if auto_roll_button.has_method("get_current_state"): auto_roll_enabled = auto_roll_button.get_current_state()
	else: printerr("ERROR: HUD.tscn not preloaded!")
	
		# Connect to SceneUIManager signals
	SceneUIManager.main_menu_start_game_pressed.connect(Callable(self, "_on_main_menu_start_game"))
	SceneUIManager.loot_screen_loot_selected.connect(Callable(self, "_on_loot_selected"))
	SceneUIManager.loot_screen_skipped.connect(Callable(self, "_on_loot_screen_closed"))
	SceneUIManager.game_over_retry_pressed.connect(Callable(self, "_on_game_over_retry_pressed"))
	SceneUIManager.game_over_main_menu_pressed.connect(Callable(self, "_on_game_over_main_menu_pressed"))
	
	var ui_canvas_node = get_node_or_null("UICanvas") # Get UICanvas once
	if not is_instance_valid(ui_canvas_node): printerr("CRITICAL: UICanvas node not found in Game scene!")



	if is_instance_valid(roll_button): roll_button.pressed.connect(Callable(self, "_on_roll_button_pressed"))
	
	
# Connect to ProgressionManager signals
	if ProgressionManager.has_signal("game_phase_changed"): ProgressionManager.game_phase_changed.connect(Callable(self, "_on_progression_game_phase_changed"))
	if ProgressionManager.has_signal("cornerstone_slot_unlocked"): ProgressionManager.cornerstone_slot_unlocked.connect(Callable(self, "_on_progression_cornerstone_unlocked"))
	if ProgressionManager.has_signal("boss_indicator_update"): ProgressionManager.boss_indicator_update.connect(Callable(self, "_on_progression_boss_indicator_update"))

	current_game_roll_state = GameRollState.MENU
	# Directly call SceneUIManager if it's an Autoload.
	# It's guaranteed to exist if the Autoload setup was successful.
	SceneUIManager.show_main_menu() # Initial state
	print("Game: Requested SceneUIManager to show main menu.") # Add for confirmation


func _process(delta):
	match current_game_roll_state:
		GameRollState.MENU:
			var main_game_ui_node = get_node_or_null("UICanvas/MainGameUI")
			if is_instance_valid(main_game_ui_node): main_game_ui_node.visible = false
			if is_instance_valid(hud_instance): hud_instance.visible = false
		GameRollState.INITIALIZING_GAME:
			_initialize_new_game_run_setup() 
		GameRollState.INITIALIZING_ROUND:
			pass # _start_new_round_setup handles transition to PLAYING
		GameRollState.PLAYING:
			var main_game_ui_node = get_node_or_null("UICanvas/MainGameUI")
			if is_instance_valid(main_game_ui_node) and not main_game_ui_node.visible: main_game_ui_node.visible = true
			if is_instance_valid(hud_instance) and not hud_instance.visible: hud_instance.visible = true
			if is_instance_valid(roll_button): roll_button.disabled = (player_current_rolls_this_round >= max_rolls_for_current_round)
			_update_hud_static_elements()
			_try_start_auto_roll()
			pass
		GameRollState.AWAITING_ANIMATION_COMPLETION:
			# Game logic is paused, waiting for RollAnimationController to emit 'full_animation_sequence_complete'
			if is_instance_valid(roll_button): roll_button.disabled = true # Ensure button stays disabled
			pass

		GameRollState.LOOT_SELECTION: pass
		GameRollState.GAME_OVER:
			if is_instance_valid(hud_instance): hud_instance.visible = false
			# SceneUIManager will show the game over screen
			# ScoreManager handles high score saving.
			SceneUIManager.show_game_over_screen(ScoreManager.get_total_accumulated_score(), current_round_number_local)
			current_game_roll_state = GameRollState.MENU # Or a specific GAME_OVER_DISPLAYING state
			# To prevent it from immediately trying to show main menu if _process loops fast:
			# Change to a new state like GameRollState.GAME_OVER_SCREEN_ACTIVE
			# And have game_over_instance signals transition out of that.
			# For now, this might flicker if game over screen doesn't block _process.
			# Let's assume GameOverScreen signals will drive next state change.
			# To prevent re-showing, we can make show_game_over_screen idempotent or Game.gd check.
			# For simplicity, let Game.gd just set a flag or rely on GameOverScreen signals.
			# The call to show_game_over_screen is now in _end_round if loss.
			pass # Wait for game over screen signals
	pass
# --- Progression Backbone Integration ---
func _initialize_new_game_run_setup():
	print("Game: Initializing new game run setup...")
	ProgressionManager.initialize_new_run()
	ScoreManager.reset_for_new_run()
	BoonManager.reset_for_new_run()
	PlayerDiceManager.reset_for_new_run()
	
	_reset_boons_and_effects()
	
	auto_roll_enabled = false
	if is_instance_valid(auto_roll_button) and auto_roll_button.has_method("set_auto_roll_state"): auto_roll_button.set_auto_roll_state(false)
	if is_instance_valid(auto_roll_delay_timer): auto_roll_delay_timer.stop()
	
	if is_instance_valid(hud_instance):
		if hud_instance.has_method("reset_full_game_visuals"): hud_instance.reset_full_game_visuals()
		# Update dice inventory display after PlayerDiceManager has initialized
		if hud_instance.has_method("update_dice_inventory_display"):
			hud_instance.update_dice_inventory_display(PlayerDiceManager.get_current_dice())
			
	current_game_roll_state = GameRollState.INITIALIZING_ROUND
	call_deferred("_start_new_round_setup")

func _start_new_round_setup():
	var round_config = ProgressionManager.get_next_round_setup()
	current_round_number_local = round_config.round_number
	max_rolls_for_current_round = round_config.max_rolls
	target_score_for_current_round = round_config.target_score
	current_game_phase_local = round_config.current_phase_for_round
	extra_max_rolls_boon = BoonManager.get_extra_max_rolls()
	max_rolls_for_current_round = min(max_rolls_for_current_round + extra_max_rolls_boon, ProgressionManager.MAX_ROLLS_CAP_PM + extra_max_rolls_boon)

	ScoreManager.reset_for_new_round()
	player_current_rolls_this_round = 0
	roll_history.clear(); synergies_fired_this_round.clear(); last_rolled_glyph = null
	print("Game: Round %d setup. Target:%d, MaxRolls:%d, Phase:%s" % [current_round_number_local, target_score_for_current_round, max_rolls_for_current_round, ProgressionManager.GamePhase.keys()[current_game_phase_local]])
	if is_instance_valid(hud_instance): 
		if hud_instance.has_method("reset_round_visuals"): hud_instance.reset_round_visuals()
		if hud_instance.has_method("activate_track_slots"): hud_instance.activate_track_slots(max_rolls_for_current_round)
		# Update dice inventory if it wasn't updated in _initialize_new_game_run_setup or if dice could change between rounds
		if hud_instance.has_method("update_dice_inventory_display"):
			hud_instance.update_dice_inventory_display(PlayerDiceManager.get_current_dice())
	current_game_roll_state = GameRollState.PLAYING
	_update_hud_static_elements()

func _end_round():
	var sm_round_score = ScoreManager.get_current_round_score()
	print("Game: Ending Round %d. Score: %d, Target: %d, Rolls Used: %d" % [current_round_number_local, sm_round_score, target_score_for_current_round, player_current_rolls_this_round])
	if is_instance_valid(auto_roll_delay_timer): auto_roll_delay_timer.stop()
	if sm_round_score >= target_score_for_current_round: # WIN
		PlayerNotificationSystem.display_message("Round %d Cleared!" % current_round_number_local)
		ProgressionManager.process_round_win(current_round_number_local, max_rolls_for_current_round, player_current_rolls_this_round, roll_history)
		current_game_roll_state = GameRollState.LOOT_SELECTION
		_prepare_and_show_loot_screen()
	else: # LOSS
		PlayerNotificationSystem.display_message("Round %d Failed." % current_round_number_local)
		SceneUIManager.show_game_over_screen(ScoreManager.get_total_accumulated_score(), current_round_number_local)
		current_game_roll_state = GameRollState.GAME_OVER # Stay in GAME_OVER, wait for its signals

# --- Signal Handlers for ProgressionManager ---
func _on_progression_game_phase_changed(new_phase_enum_value: int):
	current_game_phase_local = new_phase_enum_value
	print("Game: Received game_phase_changed. New local phase: ", ProgressionManager.GamePhase.keys()[current_game_phase_local])

func _on_progression_cornerstone_unlocked(slot_index_zero_based: int, is_unlocked: bool):
	print("Game: Received cornerstone_slot_unlocked for slot_idx %d, unlocked: %s" % [slot_index_zero_based, str(is_unlocked)])
	if is_instance_valid(hud_instance) and hud_instance.has_method("update_cornerstone_display"):
		hud_instance.update_cornerstone_display(slot_index_zero_based, is_unlocked)

func _on_progression_boss_indicator_update(show: bool, message: String):
	if is_instance_valid(hud_instance) and hud_instance.has_method("show_boss_incoming_indicator"):
		hud_instance.show_boss_incoming_indicator(show, message)

func _update_hud_static_elements():
	if not is_instance_valid(hud_instance): return
	var rolls_available = max_rolls_for_current_round - player_current_rolls_this_round
	hud_instance.update_rolls_display(rolls_available, max_rolls_for_current_round)
	hud_instance.update_score_target_display(ScoreManager.get_current_round_score(), target_score_for_current_round)
	hud_instance.update_level_display(current_round_number_local)

# --- Roll Processing Logic ---
func _perform_roll(): # Selects the glyph
	print("Game: _perform_roll() CALLED.")
	last_rolled_glyph = PlayerDiceManager.get_random_glyph_from_dice() # Get from manager

	if not is_instance_valid(last_rolled_glyph):
		printerr("CRITICAL ERROR in _perform_roll: PlayerDiceManager returned invalid glyph!")
		# This implies PlayerDiceManager.current_player_dice was empty or had invalid entries
	else:
		print("Game: _perform_roll() - Rolled: ", last_rolled_glyph.display_name)

func _calculate_score_and_synergies(p_history_for_check: Array[GlyphData]) -> Dictionary:
	var points_from_roll: int = 0
	var points_from_synergy: int = 0
	var synergy_messages: Array[String] = [] # For non-boon synergy messages
	current_success_tier = SuccessTier.NONE

	if not is_instance_valid(last_rolled_glyph):
		return {"points_from_roll":0, "points_from_synergy":0, "synergy_messages":[]}
	
	points_from_roll = last_rolled_glyph.value
	# Query BoonManager for dice glyph bonus
	if last_rolled_glyph.type == "dice":
		points_from_roll += extra_points_per_dice_glyph_boon
	
	var current_logical_slot_index = p_history_for_check.size() - 1
	if ProgressionManager.is_cornerstone_effect_active(2) and current_logical_slot_index == 2:
		points_from_roll += CORNERSTONE_SLOT_3_BONUS 
		PlayerNotificationSystem.display_message("Cornerstone Slot 3 Bonus: +%d Score!" % CORNERSTONE_SLOT_3_BONUS)

	ScoreManager.add_to_round_score(points_from_roll)

	# _evaluate_synergies_and_boons will now also handle boon activation messages
	var eval_result = _evaluate_synergies_and_boons(p_history_for_check)
	points_from_synergy = eval_result.bonus_score
	synergy_messages = eval_result.messages # This now includes boon activation messages too
	
	if points_from_synergy > 0: 
		ScoreManager.add_to_round_score(points_from_synergy) # Boons might grant score directly or through effects
	
	ScoreManager.add_to_total_score(points_from_roll + points_from_synergy)

	var total_this_roll = points_from_roll + points_from_synergy
	# ... (determine current_success_tier) ...
	
	player_current_rolls_this_round += 1
	# ... (print roll processed) ...
	return {"points_from_roll":points_from_roll, "points_from_synergy":points_from_synergy, "synergy_messages":synergy_messages}

func _evaluate_synergies_and_boons(p_history_for_check: Array[GlyphData]) -> Dictionary:
	var total_synergy_bonus: int = 0
	var messages: Array[String] = [] # This will collect all messages (synergies + boons)
	
	if p_history_for_check.is_empty(): return {"bonus_score": 0, "messages": []}

	# --- Standard Synergies (as before, using p_history_for_check) ---
	if not synergies_fired_this_round.has("numeric_double"):
		# ... (numeric double logic) ...
		# if triggered: messages.append("NUMERIC DOUBLE! +5")
		pass # Keep your existing synergy logic here, appending to 'messages'
	# ... (other standard synergies: roman gathering, card pair, simple flush) ...
	# Example for one:
	if not synergies_fired_this_round.has("numeric_double"):
		var d_seen:Dictionary={}; for r in p_history_for_check: if r.type=="dice": d_seen[r.value]=d_seen.get(r.value,0)+1; if d_seen[r.value]>=2: total_synergy_bonus+=5;synergies_fired_this_round["numeric_double"]=true;messages.append("NUMERIC DOUBLE! +5");break


	# --- Check for Rune Phrase Boons via BoonManager ---
	var current_runes_in_history_ids: Array[String]=[]
	for roll_data in p_history_for_check:
		if roll_data.type == "rune" and is_instance_valid(roll_data) and roll_data.id != "":
			current_runes_in_history_ids.append(roll_data.id)
	
	var newly_activated_boons_info: Array[Dictionary] = BoonManager.check_and_activate_rune_phrases(current_runes_in_history_ids)
	for boon_info in newly_activated_boons_info:
		messages.append("BOON: %s! (%s)" % [boon_info.name, boon_info.description])
		active_boons[boon_info.name] = true # Update Game.gd's local list of active boon IDs
		_apply_boon_effect(boon_info.name) # Call Game.gd's function to update its cached effect values
	return {"bonus_score": total_synergy_bonus, "messages": messages}

# --- HUD fanfare finished signal handler ---
func _on_hud_fanfare_animation_finished(): # This is connected to HUD's signal
	print("Game: HUD reported fanfare animation finished.")
	if current_game_roll_state == GameRollState.AWAITING_ANIMATION_COMPLETION: # Check if we are waiting for this
		if is_instance_valid(roll_animation_controller) and roll_animation_controller.has_method("hud_fanfare_has_completed"):
			roll_animation_controller.hud_fanfare_has_completed() # Tell controller to proceed
	else:
		print("Game: HUD fanfare finished, but GameRollState is not AWAITING_ANIMATION_COMPLETION. State: ", GameRollState.keys()[current_game_roll_state])

func _finalize_roll_logic_and_proceed():
	if is_instance_valid(last_rolled_glyph): roll_history.append(last_rolled_glyph)
	var sm_round_score = ScoreManager.get_current_round_score() # Get for print and check
	print("Game: Roll finalized. Rolls used: %d/%d. Round Score: %d" % [player_current_rolls_this_round, max_rolls_for_current_round, sm_round_score])
	last_rolled_glyph = null; _update_hud_static_elements()
	if player_current_rolls_this_round >= max_rolls_for_current_round or sm_round_score >= target_score_for_current_round:
		_end_round()
	else:
		current_game_roll_state = GameRollState.PLAYING
		if is_instance_valid(roll_button): roll_button.disabled = false
		_try_start_auto_roll()


# --- UI Panel Callbacks (now from SceneUIManager signals) ---
func _on_main_menu_start_game(): # Was connected to main_menu_instance directly
	# SceneUIManager already hides main_menu if its internal handler does so.
	# Game.gd focuses on game state change.
	print("Game: Start game triggered by SceneUIManager.")
	current_game_roll_state = GameRollState.INITIALIZING_GAME

func _prepare_and_show_loot_screen(): # Called after winning a round
	# if not is_instance_valid(loot_screen_instance): # SceneUIManager handles instance
	var loot_options = GlyphDB.get_random_loot_options(3) # Still get options here
	if not loot_options.is_empty():
		SceneUIManager.show_loot_screen(loot_options)
		play_sound(sfx_loot_appears)
	else:
		PlayerNotificationSystem.display_message("No loot options available this time.")
		call_deferred("_start_new_round_setup") # Skip to next round


func _on_loot_selected(chosen_glyph: GlyphData): # Was connected to loot_screen_instance
	# SceneUIManager already hides loot_screen.
	print("Game: Loot selected (via SceneUIManager): ", chosen_glyph.display_name)
	PlayerDiceManager.add_glyph_to_dice(chosen_glyph)
	ScoreManager.add_to_total_score(50)
	play_sound(sfx_glyph_added)
	call_deferred("_start_new_round_setup")

func _on_loot_screen_closed(): # Was connected to loot_screen_instance
	# SceneUIManager already hides loot_screen.
	print("Game: Loot screen closed/skipped (via SceneUIManager).")
	PlayerNotificationSystem.display_message("Loot skipped.")
	call_deferred("_start_new_round_setup")

func _on_game_over_retry_pressed(): # Was connected to game_over_instance
	# SceneUIManager already hides game_over_screen.
	print("Game: Retry pressed (via SceneUIManager).")
	current_game_roll_state = GameRollState.INITIALIZING_GAME

func _on_game_over_main_menu_pressed(): # Was connected to game_over_instance
	# SceneUIManager already hides game_over_screen.
	print("Game: Main Menu from GameOver pressed (via SceneUIManager).")
	current_game_roll_state = GameRollState.MENU
	SceneUIManager.show_main_menu() # Explicitly show main menu
	
func _on_hud_inventory_toggled(is_inventory_visible: bool): # HUD needs dice info
	if is_inventory_visible and is_instance_valid(hud_instance):
		if hud_instance.has_method("update_dice_inventory_display"):
			hud_instance.update_dice_inventory_display(PlayerDiceManager.get_current_dice())

func play_sound(sound_resource: AudioStream, volume: int = 0):
	if sfx_player and sound_resource: sfx_player.stream=sound_resource;sfx_player.volume_db=volume;sfx_player.play()
	
func _on_playback_speed_changed(new_speed_multiplier: float):
	print("Game: _on_playback_speed_changed RECEIVED. New speed: ", new_speed_multiplier)
	Engine.time_scale = new_speed_multiplier
	print("Game: Engine.time_scale SET TO: ", Engine.time_scale)

func _on_auto_roll_toggled(is_enabled: bool):
	auto_roll_enabled = is_enabled
	print("Game: _on_auto_roll_toggled. auto_roll_enabled set to: ", auto_roll_enabled, ". Current GameRollState: ", GameRollState.keys()[current_game_roll_state])
	if auto_roll_enabled: _try_start_auto_roll()
	elif is_instance_valid(auto_roll_delay_timer) and not auto_roll_delay_timer.is_stopped(): auto_roll_delay_timer.stop()

func _try_start_auto_roll():
	var can_roll=true; var reason=""
	if not auto_roll_enabled: can_roll=false;reason="disabled"
	elif current_game_roll_state!=GameRollState.PLAYING: can_roll=false;reason="not PLAYING state"
	elif (max_rolls_for_current_round-player_current_rolls_this_round)<=0: can_roll=false;reason="no rolls left"
	elif not is_instance_valid(roll_button) or roll_button.disabled: can_roll=false;reason="roll button issue"
	elif not is_instance_valid(auto_roll_delay_timer) or not auto_roll_delay_timer.is_stopped(): can_roll=false;reason="timer issue"
	if can_roll: print("Game: Auto-roll: Conditions MET, starting timer."); auto_roll_delay_timer.start()
	elif auto_roll_enabled and current_game_roll_state==GameRollState.PLAYING and (max_rolls_for_current_round-player_current_rolls_this_round)>0 and (not is_instance_valid(roll_button) or not roll_button.disabled):
		if reason!="timer issue": print("Game: Auto-roll: Conditions NOT MET (but should roll). Reason: ", reason)

func _on_auto_roll_delay_timer_timeout():
	var can_perform=true; var reason=""
	if not auto_roll_enabled: can_perform=false;reason="disabled at timeout"
	elif current_game_roll_state!=GameRollState.PLAYING: can_perform=false;reason="not PLAYING at timeout"
	elif (max_rolls_for_current_round-player_current_rolls_this_round)<=0: can_perform=false;reason="no rolls at timeout"
	elif not is_instance_valid(roll_button) or roll_button.disabled: can_perform=false;reason="roll button issue at timeout"
	if can_perform: print("Game: Auto-roll: Performing roll."); _on_roll_button_pressed()
	else:
		print("Game: Auto-roll: Conditions NOT MET on timeout. Reason: ", reason)
		if auto_roll_enabled and current_game_roll_state==GameRollState.PLAYING and (max_rolls_for_current_round-player_current_rolls_this_round)>0:
			_try_start_auto_roll()

# --- Roll Button Pressed - Now delegates to RollAnimationController ---
func _on_roll_button_pressed():
	if current_game_roll_state == GameRollState.PLAYING and (max_rolls_for_current_round - player_current_rolls_this_round) > 0 :
		print("Game: Roll button pressed. Telling RollAnimationController to start.")
		current_game_roll_state = GameRollState.AWAITING_ANIMATION_COMPLETION # Game waits
		if is_instance_valid(roll_button): roll_button.disabled = true
		
		if is_instance_valid(roll_animation_controller) and roll_animation_controller.has_method("start_full_roll_sequence"):
			roll_animation_controller.start_full_roll_sequence()
		else:
			printerr("Game: RollAnimationController not valid or missing start_full_roll_sequence method! Cannot start roll animation.")
			# Fallback:
			current_game_roll_state = GameRollState.PLAYING 
			if is_instance_valid(roll_button): roll_button.disabled = (player_current_rolls_this_round >= max_rolls_for_current_round)
	else:
		print("Game: Cannot roll. State:%s, Rolls available:%d" % [GameRollState.keys()[current_game_roll_state], (max_rolls_for_current_round - player_current_rolls_this_round)])

# --- Callbacks for RollAnimationController Signals ---
func _on_rac_logical_roll_requested():
	print("Game: RollAnimationController requested logical roll.")
	_perform_roll() # Game.gd still performs the logical roll
	if is_instance_valid(roll_animation_controller) and roll_animation_controller.has_method("set_logical_roll_result"):
		roll_animation_controller.set_logical_roll_result(last_rolled_glyph) # Send result back to controller
	else:
		printerr("Game: Cannot send logical roll result back to RollAnimationController.")

func _on_rac_fanfare_start_requested(p_rolled_glyph: GlyphData, p_temp_anim_glyph_node: TextureRect):
	# p_rolled_glyph and p_temp_anim_glyph_node are provided by controller, but Game.gd
	# uses its own last_rolled_glyph and will create score_data based on that.
	# The p_temp_anim_glyph_node is mostly for RAC's internal use if it were drawing it.
	print("Game: RollAnimationController requested fanfare start.")
	
	# Ensure last_rolled_glyph is set (should be by _on_rac_logical_roll_requested)
	if not is_instance_valid(last_rolled_glyph):
		printerr("Game: last_rolled_glyph is not valid when fanfare requested!")
		# Potentially tell controller to abort or skip fanfare
		if is_instance_valid(roll_animation_controller) and roll_animation_controller.has_method("hud_fanfare_has_completed"): # Tell it to skip
			roll_animation_controller.hud_fanfare_has_completed()
		return

	var temp_history_for_synergy_check = roll_history.duplicate(true)
	temp_history_for_synergy_check.append(last_rolled_glyph) # Use Game.gd's last_rolled_glyph
	
	var score_data = _calculate_score_and_synergies(temp_history_for_synergy_check)

	if is_instance_valid(hud_instance) and hud_instance.has_method("play_score_fanfare"):
		# HUD will emit 'fanfare_animation_finished', which Game.gd catches
		hud_instance.play_score_fanfare(
			score_data.points_from_roll, 
			score_data.points_from_synergy, 
			ScoreManager.get_current_round_score(), 
			score_data.synergy_messages, 
			current_success_tier
		)
	else: # No HUD fanfare, so tell controller fanfare is "done" immediately
		print("Game: HUD cannot play score fanfare. Telling RollAnimationController it's complete.")
		if is_instance_valid(roll_animation_controller) and roll_animation_controller.has_method("hud_fanfare_has_completed"):
			roll_animation_controller.hud_fanfare_has_completed()


func _on_rac_move_to_history_requested(p_animating_glyph_node: TextureRect, p_final_glyph: GlyphData):
	print("Game: RollAnimationController requested move to history.")
	# p_animating_glyph_node is the node controller wants us to tween.
	# p_final_glyph is the glyph that should end up in the history.
	
	if not is_instance_valid(p_animating_glyph_node) or not is_instance_valid(p_final_glyph):
		printerr("Game: Invalid node or glyph data for move_to_history_requested.")
		if is_instance_valid(roll_animation_controller) and roll_animation_controller.has_method("animation_move_to_history_finished"):
			roll_animation_controller.animation_move_to_history_finished() # Tell it to clean up
		return

	var target_slot_center_pos: Vector2
	if is_instance_valid(hud_instance) and hud_instance.has_method("get_next_history_slot_global_position"):
		target_slot_center_pos = hud_instance.get_next_history_slot_global_position()
	else: 
		printerr("Game: HUD cannot provide history slot position for move_to_history.")
		target_slot_center_pos = Vector2(100, 100) # Fallback

	var tween_to_history = create_tween()
	tween_to_history.finished.connect(Callable(self, "_on_internal_move_to_history_tween_finished")) # Connect to an internal handler

	tween_to_history.set_parallel(true) 
	var target_visual_pos = target_slot_center_pos - (HISTORY_SLOT_GLYPH_SIZE / 2.0)
	tween_to_history.tween_property(p_animating_glyph_node, "global_position", target_visual_pos, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween_to_history.tween_property(p_animating_glyph_node, "custom_minimum_size", HISTORY_SLOT_GLYPH_SIZE, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween_to_history.tween_property(p_animating_glyph_node, "size", HISTORY_SLOT_GLYPH_SIZE, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func _on_internal_move_to_history_tween_finished():
	print("Game: Internal tween for move_to_history finished.")
	if is_instance_valid(roll_animation_controller) and roll_animation_controller.has_method("animation_move_to_history_finished"):
		roll_animation_controller.animation_move_to_history_finished()
	# The controller will then emit full_animation_sequence_complete


func _on_rac_full_animation_sequence_complete(final_glyph_data: GlyphData):
	print("Game: RollAnimationController reported full_animation_sequence_complete. Final glyph: ", final_glyph_data.display_name if final_glyph_data else "N/A")
	
	if not is_instance_valid(final_glyph_data):
		printerr("Game: Animation sequence completed with invalid final glyph data. Problems may occur.")
		# Decide how to handle this error - e.g., force round end, or try to recover
	
	# last_rolled_glyph should have been set by _on_rac_logical_roll_requested
	# and should match final_glyph_data. For safety, we can use final_glyph_data here.
	# Though _finalize_roll_logic_and_proceed uses Game.gd's 'last_rolled_glyph'.
	# Ensure consistency:
	if is_instance_valid(final_glyph_data):
		last_rolled_glyph = final_glyph_data # Ensure Game.gd's copy is the one from the anim sequence
	
	if is_instance_valid(hud_instance) and hud_instance.has_method("add_glyph_to_visual_history"):
		hud_instance.add_glyph_to_visual_history(last_rolled_glyph) # Update HUD's visual track
	
	_finalize_roll_logic_and_proceed() # This updates logical history, checks for round end

func _reset_boons_and_effects(): # This belongs in Game.gd
	print("Game: Resetting local active_boons list and cached boon effect variables.")
	active_boons.clear() # Game.gd's list of active boon IDs for the current run
	# Reset Game.gd's cached values for boon effects
	extra_points_per_dice_glyph_boon = 0
	extra_max_rolls_boon = 0
	# run_score_multiplier_boon = 1.0 # If Game.gd had this for direct use

func _apply_boon_effect(boon_id: String): # Called by _evaluate_synergies_and_boons
	print("Game: Applying/caching effect for boon_id: ", boon_id)
	# This function now updates Game.gd's local convenience/cache variables
	# by querying the authoritative source in BoonManager.
	# This is called AFTER BoonManager has already activated the boon and updated its own state.
	if boon_id == "sun_power":
		extra_points_per_dice_glyph_boon = BoonManager.get_extra_points_for_dice_glyph()
		print("Game: Updated local extra_points_per_dice_glyph_boon to: ", extra_points_per_dice_glyph_boon)
	elif boon_id == "water_flow":
		# Get the CUMULATIVE extra rolls from BoonManager
		var current_bm_extra_rolls = BoonManager.get_extra_max_rolls()
		if current_bm_extra_rolls != extra_max_rolls_boon: # Only update if changed
			extra_max_rolls_boon = current_bm_extra_rolls
			print("Game: Updated local extra_max_rolls_boon to: ", extra_max_rolls_boon)
			_update_hud_static_elements() # Max rolls might have changed for HUD display
	# No need to call _update_hud_static_elements for sun_power as it affects score calculation time.

