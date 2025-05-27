# res://scripts/Game.gd
# TABS FOR INDENTATION
extends Node2D

# --- Game Moment-to-Moment State Enum ---
enum GameRollState {
	MENU,
	INITIALIZING_GAME, # Sets up a whole new run
	INITIALIZING_ROUND, # Sets up parameters for the current round
	PLAYING,
	ROLLING,
	RESULT_REVEAL,
	FANFARE_ANIMATION,
	GLYPH_TO_HISTORY,
	LOOT_SELECTION,
	GAME_OVER
}
var current_game_roll_state: GameRollState = GameRollState.MENU

# --- Game Progression Phase Enum (Still defined here for local use if needed, PM uses its own copy) ---
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
var current_player_dice: Array[GlyphData] = []
var roll_history: Array[GlyphData] = []
var last_rolled_glyph: GlyphData = null

# --- Scoring (Now simpler, actual values managed by ScoreManager or directly) ---
var current_round_score: int = 0
var total_accumulated_score: int = 0 # For high score display
var high_score: int = 0 # Loaded/Saved here for now
const HIGH_SCORE_FILE_PATH: String = "user://quantum_dice_highscore.dat"

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
var RUNE_PHRASES: Dictionary = {
	"SUN_POWER": { "id": "sun_power", "display_name": "Sun's Radiance", "runes_required": ["rune_sowilo", "rune_fehu"], "boon_description": "All 'dice' type glyphs score +2 points for the rest of the run."},
	"WATER_FLOW": { "id": "water_flow", "display_name": "Water's Flow", "runes_required": ["rune_laguz", "rune_ansuz"], "boon_description": "Gain +1 max roll per round for the rest of the run (up to a new cap)."}
}
var active_boons: Dictionary = {}
var run_score_multiplier_boon: float = 1.0
var extra_points_per_dice_glyph_boon: int = 0
var extra_max_rolls_boon: int = 0

# --- Animation Control ---
var animating_glyph_node: TextureRect = null
var reveal_on_button_timer: Timer
const REVEAL_DURATION: float = 0.75

# --- CORE UI Node References ---
@onready var roll_button: TextureButton = $UICanvas/MainGameUI/AnimatedRollButton
@onready var ui_canvas: CanvasLayer = $UICanvas

# --- Scene Preloads & Instances (Could move to a SceneTransitionManager) ---
var main_menu_scene: PackedScene = preload("res://scenes/ui/MainMenu.tscn")
@onready var main_menu_instance: Control
var loot_screen_scene: PackedScene = preload("res://scenes/ui/LootScreen.tscn")
@onready var loot_screen_instance: Control
var hud_scene: PackedScene = preload("res://scenes/ui/HUD.tscn")
@onready var hud_instance: Control
var game_over_screen_scene: PackedScene = preload("res://scenes/ui/GameOverScreen.tscn")
@onready var game_over_instance: Control

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
	_load_high_score() # Score related, could move to ScoreManager

	reveal_on_button_timer = Timer.new(); reveal_on_button_timer.one_shot = true
	reveal_on_button_timer.wait_time = REVEAL_DURATION
	reveal_on_button_timer.timeout.connect(Callable(self, "_on_reveal_on_button_timer_timeout")); add_child(reveal_on_button_timer)
	
	auto_roll_delay_timer = Timer.new(); auto_roll_delay_timer.name = "AutoRollDelayTimer"
	auto_roll_delay_timer.wait_time = 0.25; auto_roll_delay_timer.one_shot = true
	auto_roll_delay_timer.timeout.connect(Callable(self, "_on_auto_roll_delay_timer_timeout")); add_child(auto_roll_delay_timer)

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

	# Scene Instantiations (MainMenu, Loot, GameOver - as before)
	if main_menu_scene: main_menu_instance = main_menu_scene.instantiate(); get_node("/root/Game/UICanvas").add_child(main_menu_instance); main_menu_instance.start_game_pressed.connect(_on_main_menu_start_game) # Simplified
	if loot_screen_scene: loot_screen_instance = loot_screen_scene.instantiate(); get_node("/root/Game/UICanvas").add_child(loot_screen_instance); loot_screen_instance.loot_selected.connect(_on_loot_selected); loot_screen_instance.skip_loot_pressed.connect(_on_loot_screen_closed); loot_screen_instance.hide()
	if game_over_screen_scene: game_over_instance = game_over_screen_scene.instantiate(); get_node("/root/Game/UICanvas").add_child(game_over_instance); game_over_instance.retry_pressed.connect(_on_game_over_retry_pressed); game_over_instance.main_menu_pressed.connect(_on_game_over_main_menu_pressed); game_over_instance.hide()


	if is_instance_valid(roll_button): roll_button.pressed.connect(Callable(self, "_on_roll_button_pressed"))
	if is_instance_valid(roll_animation_timer): roll_animation_timer.timeout.connect(Callable(self, "_on_roll_animation_timer_timeout"))
	
	# Connect to ProgressionManager signals
	if ProgressionManager.has_signal("game_phase_changed"):
		ProgressionManager.game_phase_changed.connect(Callable(self, "_on_progression_game_phase_changed"))
	if ProgressionManager.has_signal("cornerstone_slot_unlocked"):
		ProgressionManager.cornerstone_slot_unlocked.connect(Callable(self, "_on_progression_cornerstone_unlocked"))
	if ProgressionManager.has_signal("boss_indicator_update"):
		ProgressionManager.boss_indicator_update.connect(Callable(self, "_on_progression_boss_indicator_update"))

	current_game_roll_state = GameRollState.MENU

func _process(delta):
	match current_game_roll_state:
		GameRollState.MENU: # Handled by MainMenu scene logic mostly
			var main_game_ui_node = get_node_or_null("UICanvas/MainGameUI")
			if is_instance_valid(main_game_ui_node): main_game_ui_node.visible = false
			if is_instance_valid(hud_instance): hud_instance.visible = false
			if is_instance_valid(main_menu_instance) and not main_menu_instance.visible: main_menu_instance.show()


		GameRollState.INITIALIZING_GAME:
			_initialize_new_game_run_setup() 
			# This now calls ProgressionManager and then _start_new_round_setup

		GameRollState.INITIALIZING_ROUND:
			# This state is entered, and _start_new_round_setup is called (often deferred)
			# _start_new_round_setup will transition to PLAYING
			pass

		GameRollState.PLAYING:
			var main_game_ui_node = get_node_or_null("UICanvas/MainGameUI")
			if is_instance_valid(main_game_ui_node) and not main_game_ui_node.visible: main_game_ui_node.visible = true
			if is_instance_valid(hud_instance) and not hud_instance.visible: hud_instance.visible = true
			_update_hud_static_elements()
			if is_instance_valid(roll_button): roll_button.disabled = (player_current_rolls_this_round >= max_rolls_for_current_round)
			_try_start_auto_roll() # Check if auto-roll should fire

		# ROLLING, RESULT_REVEAL, FANFARE_ANIMATION, GLYPH_TO_HISTORY: Animation states, pass
		GameRollState.ROLLING: if is_instance_valid(roll_button): roll_button.disabled = true; pass
		GameRollState.RESULT_REVEAL: pass
		GameRollState.FANFARE_ANIMATION: pass
		GameRollState.GLYPH_TO_HISTORY: pass
			
		GameRollState.LOOT_SELECTION: pass # Waits for loot screen signals
				
		GameRollState.GAME_OVER:
			if is_instance_valid(hud_instance): hud_instance.visible = false
			if total_accumulated_score > high_score: _save_high_score() # Simplified
			if is_instance_valid(game_over_instance) and not game_over_instance.visible:
				game_over_instance.show_screen(total_accumulated_score, current_round_number_local)
			pass

# --- Progression Backbone Integration ---
func _initialize_new_game_run_setup(): # Was _initialize_new_game_session_and_run
	print("Game: Initializing new game run setup...")
	ProgressionManager.initialize_new_run() # Reset progression state

	total_accumulated_score = 0 # Reset score here
	current_player_dice.clear()
	_reset_boons_and_effects() # Boons are run-specific

	auto_roll_enabled = false # Reset auto-roll for a new game
	if is_instance_valid(auto_roll_button) and auto_roll_button.has_method("set_auto_roll_state"):
		auto_roll_button.set_auto_roll_state(false)
	if is_instance_valid(auto_roll_delay_timer): auto_roll_delay_timer.stop()
	
	if GlyphDB and not GlyphDB.starting_dice_configuration.is_empty():
		current_player_dice = GlyphDB.starting_dice_configuration.duplicate(true)
	
	if is_instance_valid(hud_instance) and hud_instance.has_method("reset_full_game_visuals"):
		hud_instance.reset_full_game_visuals()
	
	current_game_roll_state = GameRollState.INITIALIZING_ROUND # Set state
	call_deferred("_start_new_round_setup") # Defer to ensure current frame finishes

func _start_new_round_setup(): # Was _start_new_round
	var round_config = ProgressionManager.get_next_round_setup()
	
	current_round_number_local = round_config.round_number
	max_rolls_for_current_round = round_config.max_rolls
	target_score_for_current_round = round_config.target_score
	current_game_phase_local = round_config.current_phase_for_round # Sync local phase
	
	# Apply boon for extra max rolls if active (ProgressionManager doesn't know about this boon directly)
	max_rolls_for_current_round = min(max_rolls_for_current_round + extra_max_rolls_boon, ProgressionManager.MAX_ROLLS_CAP_PM + extra_max_rolls_boon)

	player_current_rolls_this_round = 0
	current_round_score = 0 # Reset round score
	roll_history.clear()
	synergies_fired_this_round.clear()
	last_rolled_glyph = null

	print("Game: Round %d setup. Target:%d, MaxRolls:%d, Phase:%s" % [
		current_round_number_local, target_score_for_current_round, max_rolls_for_current_round,
		ProgressionManager.GamePhase.keys()[current_game_phase_local]
	])

	if is_instance_valid(hud_instance): 
		if hud_instance.has_method("reset_round_visuals"): hud_instance.reset_round_visuals()
		if hud_instance.has_method("activate_track_slots"): hud_instance.activate_track_slots(max_rolls_for_current_round)
		hud_instance.update_dice_inventory_display(current_player_dice)
	
	current_game_roll_state = GameRollState.PLAYING
	_update_hud_static_elements()


func _end_round():
	print("Game: Ending Round %d. Score: %d, Target: %d, Rolls Used: %d" % [current_round_number_local, current_round_score, target_score_for_current_round, player_current_rolls_this_round])
	if is_instance_valid(auto_roll_delay_timer): auto_roll_delay_timer.stop()

	if current_round_score >= target_score_for_current_round: # WIN
		PlayerNotificationSystem.display_message("Round %d Cleared!" % current_round_number_local)
		ProgressionManager.process_round_win(current_round_number_local, max_rolls_for_current_round, player_current_rolls_this_round, roll_history)
		current_game_roll_state = GameRollState.LOOT_SELECTION
		_prepare_and_show_loot_screen()
	else: # LOSS
		PlayerNotificationSystem.display_message("Round %d Failed." % current_round_number_local)
		current_game_roll_state = GameRollState.GAME_OVER

# --- Signal Handlers for ProgressionManager ---
func _on_progression_game_phase_changed(new_phase_enum_value: int):
	current_game_phase_local = new_phase_enum_value # Sync local copy
	print("Game: Received game_phase_changed from ProgressionManager. New local phase: ", ProgressionManager.GamePhase.keys()[current_game_phase_local])
	# Additional logic if Game.gd needs to react directly to phase changes,
	# besides what _start_new_round_setup does.

func _on_progression_cornerstone_unlocked(slot_index_zero_based: int, is_unlocked: bool):
	print("Game: Received cornerstone_slot_unlocked for slot_idx %d, unlocked: %s" % [slot_index_zero_based, str(is_unlocked)])
	if is_instance_valid(hud_instance) and hud_instance.has_method("update_cornerstone_display"):
		hud_instance.update_cornerstone_display(slot_index_zero_based, is_unlocked)
	# Update Game.gd's own flag if it needs to directly know for logic (like the bonus)
	if slot_index_zero_based == 2: # Slot 3
		# This flag is already set by ProgressionManager, Game.gd queries it.
		# No, ProgressionManager has is_cornerstone_slot_3_active. Game.gd needs its own or query.
		# Let's have Game.gd query ProgressionManager.is_cornerstone_effect_active(2)
		pass


func _on_progression_boss_indicator_update(show: bool, message: String):
	if is_instance_valid(hud_instance) and hud_instance.has_method("show_boss_incoming_indicator"):
		hud_instance.show_boss_incoming_indicator(show, message)


func _update_hud_static_elements():
	if not is_instance_valid(hud_instance): return
	var rolls_available = max_rolls_for_current_round - player_current_rolls_this_round
	hud_instance.update_rolls_display(rolls_available, max_rolls_for_current_round)
	hud_instance.update_score_target_display(current_round_score, target_score_for_current_round)
	hud_instance.update_level_display(current_round_number_local)

# --- Roll Processing Logic (largely unchanged below, but uses updated vars) ---
func _on_roll_button_pressed():
	# print("Game: _on_roll_button_pressed CALLED. State: %s, Rolls available: %d" % [GameRollState.keys()[current_game_roll_state], (max_rolls_for_current_round - player_current_rolls_this_round)])
	if current_game_roll_state == GameRollState.PLAYING and (max_rolls_for_current_round - player_current_rolls_this_round) > 0 :
		# print("Game: _on_roll_button_pressed: Conditions MET, proceeding.")
		current_game_roll_state = GameRollState.ROLLING
		if is_instance_valid(roll_button): roll_button.disabled = true
		if is_instance_valid(hud_instance) and hud_instance.has_method("start_roll_button_animation"): hud_instance.start_roll_button_animation()
		var on_button_glyph_display = roll_button.get_node_or_null("RolledGlyphOnButtonDisplay")
		if is_instance_valid(on_button_glyph_display): on_button_glyph_display.visible = false
		roll_animation_timer.start()
	# else: print("Game: _on_roll_button_pressed: Conditions NOT MET.")


func _on_roll_animation_timer_timeout():
	if current_game_roll_state == GameRollState.ROLLING:
		_perform_roll()
		if not is_instance_valid(last_rolled_glyph):
			current_game_roll_state = GameRollState.PLAYING
			if is_instance_valid(roll_button): roll_button.disabled = (player_current_rolls_this_round >= max_rolls_for_current_round)
			return
		if is_instance_valid(hud_instance) and hud_instance.has_method("stop_roll_button_animation_show_result"):
			hud_instance.stop_roll_button_animation_show_result(last_rolled_glyph) 
		var on_button_glyph_display = roll_button.get_node_or_null("RolledGlyphOnButtonDisplay")
		if is_instance_valid(on_button_glyph_display):
			if is_instance_valid(last_rolled_glyph) and is_instance_valid(last_rolled_glyph.texture):
				on_button_glyph_display.texture = last_rolled_glyph.texture; on_button_glyph_display.visible = true
			else: on_button_glyph_display.visible = false
		current_game_roll_state = GameRollState.RESULT_REVEAL
		reveal_on_button_timer.start()

func _perform_roll(): # Selects the glyph
	if current_player_dice.is_empty(): printerr("CRITICAL: Player dice is empty!"); return
	var rolled_glyph_index = randi() % current_player_dice.size()
	last_rolled_glyph = current_player_dice[rolled_glyph_index]
	if not is_instance_valid(last_rolled_glyph): printerr("CRITICAL: last_rolled_glyph invalid post-roll!")

func _on_reveal_on_button_timer_timeout():
	if current_game_roll_state == GameRollState.RESULT_REVEAL:
		current_game_roll_state = GameRollState.FANFARE_ANIMATION
		_start_glyph_fanfare_animation()

func _start_glyph_fanfare_animation(): # Creates temp glyph, tweens to center, calls HUD fanfare
	if not is_instance_valid(last_rolled_glyph): 
		_finalize_roll_logic_and_proceed()
		return
	if is_instance_valid(animating_glyph_node): 
		animating_glyph_node.queue_free()
	
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
	else: 
		animating_glyph_node.global_position = roll_button.global_position # Fallback

	# CORRECTED if/else block:
	if is_instance_valid(ui_canvas): 
		ui_canvas.add_child(animating_glyph_node)
	else: 
		add_child(animating_glyph_node) # Fallback if ui_canvas is somehow not valid

	var screen_center = get_viewport_rect().size / 2.0
	var tween_to_center = create_tween()
	tween_to_center.tween_property(animating_glyph_node, "global_position", screen_center - (animating_glyph_node.size / 2.0), 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	
	var temp_history_for_synergy_check = roll_history.duplicate(true) # Deep copy if GlyphData are objects
	temp_history_for_synergy_check.append(last_rolled_glyph)
	
	var score_data = _calculate_score_and_synergies(temp_history_for_synergy_check) # Pass temp history

	if is_instance_valid(hud_instance) and hud_instance.has_method("play_score_fanfare"):
		hud_instance.play_score_fanfare(score_data.points_from_roll, score_data.points_from_synergy, current_round_score, score_data.synergy_messages, current_success_tier)
	else: 
		call_deferred("_on_hud_fanfare_animation_finished")

func _calculate_score_and_synergies(p_history_for_check: Array[GlyphData]) -> Dictionary:
	var points_from_roll: int = 0; var points_from_synergy: int = 0
	var synergy_messages: Array[String] = []; current_success_tier = SuccessTier.NONE
	if not is_instance_valid(last_rolled_glyph): return {"points_from_roll":0,"points_from_synergy":0,"synergy_messages":[]}
	points_from_roll = last_rolled_glyph.value
	if last_rolled_glyph.type == "dice" and active_boons.has("sun_power"): points_from_roll += extra_points_per_dice_glyph_boon
	var current_logical_slot_index = p_history_for_check.size() - 1
	if ProgressionManager.is_cornerstone_effect_active(2) and current_logical_slot_index == 2: # Query PM for slot 3 (index 2)
		points_from_roll += CORNERSTONE_SLOT_3_BONUS
		PlayerNotificationSystem.display_message("Cornerstone Slot 3 Bonus: +%d Score!" % CORNERSTONE_SLOT_3_BONUS)
	current_round_score += points_from_roll
	var synergy_result = _evaluate_synergies_and_boons(p_history_for_check)
	points_from_synergy = synergy_result.bonus_score; synergy_messages = synergy_result.messages
	if points_from_synergy > 0: current_round_score += points_from_synergy
	total_accumulated_score += points_from_roll + points_from_synergy
	var total_this_roll = points_from_roll + points_from_synergy
	if total_this_roll >= 25: current_success_tier = SuccessTier.JACKPOT
	elif total_this_roll >= 15: current_success_tier = SuccessTier.MAJOR
	elif total_this_roll >= 8: current_success_tier = SuccessTier.MEDIUM
	elif total_this_roll > 0: current_success_tier = SuccessTier.MINOR
	player_current_rolls_this_round += 1 # Increment actual rolls used
	print("Game: Roll %d/%d processed." % [player_current_rolls_this_round, max_rolls_for_current_round])
	return {"points_from_roll":points_from_roll,"points_from_synergy":points_from_synergy,"synergy_messages":synergy_messages}

func _evaluate_synergies_and_boons(p_history_for_check: Array[GlyphData]) -> Dictionary: # Uses passed history
	# ... (synergy logic as before, using p_history_for_check) ...
	var total_synergy_bonus: int = 0; var messages: Array[String] = []
	if p_history_for_check.is_empty(): return {"bonus_score": 0, "messages": []}
	if not synergies_fired_this_round.has("numeric_double"):
		var d_seen:Dictionary={}; for r in p_history_for_check: if r.type=="dice": d_seen[r.value]=d_seen.get(r.value,0)+1; if d_seen[r.value]>=2: total_synergy_bonus+=5;synergies_fired_this_round["numeric_double"]=true;messages.append("NUMERIC DOUBLE! +5");break
	if not synergies_fired_this_round.has("roman_gathering"):
		var rg_c:int=0; for r in p_history_for_check: if r.type=="roman": rg_c+=1
		if rg_c>=2: total_synergy_bonus+=10;synergies_fired_this_round["roman_gathering"]=true;messages.append("ROMAN GATHERING! +10")
	if not synergies_fired_this_round.has("card_pair"):
		var c_seen:Dictionary={}; for r in p_history_for_check: if r.type=="card": c_seen[r.value]=c_seen.get(r.value,0)+1; if c_seen[r.value]>=2: total_synergy_bonus+=8;synergies_fired_this_round["card_pair"]=true;messages.append("CARD PAIR! +8");break
	if not synergies_fired_this_round.has("simple_flush"):
		var s_c:Dictionary={"hearts":0,"diamonds":0,"clubs":0,"spades":0}; for r in p_history_for_check: if r.type=="card" and r.suit!="": if s_c.has(r.suit):s_c[r.suit]+=1
		for s_n in s_c: if s_c[s_n]>=3: total_synergy_bonus+=15;synergies_fired_this_round["simple_flush"]=true;messages.append("FLUSH (%s)! +15"%s_n.capitalize());break
	var runes_hist:Array[String]=[]; for r in p_history_for_check: if r.type=="rune" and r.id!="": runes_hist.append(r.id)
	if not runes_hist.is_empty():
		for pk in RUNE_PHRASES: var pd=RUNE_PHRASES[pk]; var pid=pd.id; if not active_boons.has(pid):
			var found_all=true; for req_rid in pd.runes_required: if not req_rid in runes_hist: found_all=false;break
			if found_all: active_boons[pid]=true;messages.append("BOON: %s! (%s)"%[pd.display_name,pd.boon_description]);_apply_boon_effect(pid)
	return {"bonus_score": total_synergy_bonus, "messages": messages}


func _on_hud_fanfare_animation_finished():
	if current_game_roll_state == GameRollState.FANFARE_ANIMATION:
		current_game_roll_state = GameRollState.GLYPH_TO_HISTORY
		_start_glyph_to_history_animation()

func _start_glyph_to_history_animation(): # Tweens animating_glyph_node to history slot
	if not is_instance_valid(animating_glyph_node) or not is_instance_valid(last_rolled_glyph):
		if is_instance_valid(animating_glyph_node): animating_glyph_node.queue_free(); animating_glyph_node = null
		_finalize_roll_logic_and_proceed(); return
	var target_pos: Vector2
	if is_instance_valid(hud_instance) and hud_instance.has_method("get_next_history_slot_global_position"): target_pos = hud_instance.get_next_history_slot_global_position()
	else: target_pos = Vector2(100,100)
	var tween = create_tween(); tween.finished.connect(_on_glyph_to_history_animation_finished); tween.set_parallel(true)
	tween.tween_property(animating_glyph_node, "global_position", target_pos - (HISTORY_SLOT_GLYPH_SIZE/2.0), 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(animating_glyph_node, "custom_minimum_size", HISTORY_SLOT_GLYPH_SIZE, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(animating_glyph_node, "size", HISTORY_SLOT_GLYPH_SIZE, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func _on_glyph_to_history_animation_finished():
	if is_instance_valid(animating_glyph_node): animating_glyph_node.queue_free(); animating_glyph_node = null
	if is_instance_valid(hud_instance) and hud_instance.has_method("add_glyph_to_visual_history"):
		hud_instance.add_glyph_to_visual_history(last_rolled_glyph)
	_finalize_roll_logic_and_proceed()

func _finalize_roll_logic_and_proceed(): # Updates history, checks for round end
	if is_instance_valid(last_rolled_glyph): roll_history.append(last_rolled_glyph)
	print("Game: Roll finalized. Rolls used: %d/%d. Round Score: %d" % [player_current_rolls_this_round, max_rolls_for_current_round, current_round_score])
	last_rolled_glyph = null; _update_hud_static_elements()
	if player_current_rolls_this_round >= max_rolls_for_current_round or current_round_score >= target_score_for_current_round:
		_end_round()
	else:
		current_game_roll_state = GameRollState.PLAYING
		if is_instance_valid(roll_button): roll_button.disabled = false
		_try_start_auto_roll()

# --- Other Callbacks & Helpers ---
func add_glyph_to_player_dice(glyph_data: GlyphData): # Called by loot screen
	if glyph_data and glyph_data is GlyphData: current_player_dice.append(glyph_data)
	if is_instance_valid(hud_instance): hud_instance.update_dice_inventory_display(current_player_dice)

func _on_main_menu_start_game():
	if is_instance_valid(main_menu_instance): main_menu_instance.hide()
	current_game_roll_state = GameRollState.INITIALIZING_GAME

func _prepare_and_show_loot_screen():
	if not is_instance_valid(loot_screen_instance): call_deferred("_start_new_round_setup"); return
	var loot_options = GlyphDB.get_random_loot_options(3)
	if not loot_options.is_empty(): loot_screen_instance.display_loot_options(loot_options); play_sound(sfx_loot_appears)
	else: PlayerNotificationSystem.display_message("No loot options."); call_deferred("_start_new_round_setup")

func _on_loot_selected(chosen_glyph: GlyphData):
	if is_instance_valid(loot_screen_instance): loot_screen_instance.hide()
	add_glyph_to_player_dice(chosen_glyph); total_accumulated_score += 50; play_sound(sfx_glyph_added)
	call_deferred("_start_new_round_setup")

func _on_loot_screen_closed(): # Skip
	if is_instance_valid(loot_screen_instance): loot_screen_instance.hide()
	PlayerNotificationSystem.display_message("Loot skipped.")
	call_deferred("_start_new_round_setup")

func _on_hud_inventory_toggled(is_inventory_visible: bool):
	if is_inventory_visible and is_instance_valid(hud_instance): hud_instance.update_dice_inventory_display(current_player_dice)

func _on_game_over_retry_pressed():
	if is_instance_valid(game_over_instance): game_over_instance.hide()
	current_game_roll_state = GameRollState.INITIALIZING_GAME
func _on_game_over_main_menu_pressed():
	if is_instance_valid(game_over_instance): game_over_instance.hide()
	current_game_roll_state = GameRollState.MENU

func _load_high_score(): # Could move to ScoreManager
	if FileAccess.file_exists(HIGH_SCORE_FILE_PATH):
		var f = FileAccess.open(HIGH_SCORE_FILE_PATH,FileAccess.READ); if is_instance_valid(f): high_score=f.get_as_text().to_int();f.close()
func _save_high_score(): # Could move to ScoreManager
	var f = FileAccess.open(HIGH_SCORE_FILE_PATH,FileAccess.WRITE); if is_instance_valid(f): f.store_string(str(high_score));f.close()

func _apply_boon_effect(boon_id: String): # Could move to BoonManager
	if boon_id=="sun_power": extra_points_per_dice_glyph_boon=2
	elif boon_id=="water_flow": extra_max_rolls_boon+=1; _update_hud_static_elements()
func _reset_boons_and_effects(): # Could move to BoonManager
	active_boons.clear();run_score_multiplier_boon=1.0;extra_points_per_dice_glyph_boon=0;extra_max_rolls_boon=0

func play_sound(sound_resource: AudioStream, volume: int = 0): # Could move to SoundManager
	if sfx_player and sound_resource: sfx_player.stream=sound_resource;sfx_player.volume_db=volume;sfx_player.play()
	
# --- Auto-Roll / Playback Speed Handlers ---
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

# _unhandled_input for debug rolls - ensure it's adapted if used
