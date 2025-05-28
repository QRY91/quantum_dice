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
var current_game_phase_local: GamePhase = GamePhase.PRE_BOSS


# --- Success Tier Enum ---
enum SuccessTier { NONE, MINOR, MEDIUM, MAJOR, JACKPOT }
var current_success_tier: SuccessTier = SuccessTier.NONE

var enable_debug_rolls: bool = false

# Player's DICE & Roll History
var roll_history: Array[GlyphData] = [] # Stores the RESOLVED glyphs
var initial_rolled_glyph: GlyphData = null # The glyph as it comes off the dice (could be superposition)
var last_resolved_glyph: GlyphData = null # The final glyph after any superposition collapse

# --- Round Parameters (Set by ProgressionManager) ---
var current_round_number_local: int = 0
var player_current_rolls_this_round: int = 0
var max_rolls_for_current_round: int = 0
var target_score_for_current_round: int = 0

# --- Configurable Game Parameters ---
const CORNERSTONE_SLOT_3_BONUS: int = 10
const DESIGN_BLOCK_SIZE: int = 80
const ROLL_BUTTON_GLYPH_SIZE: Vector2 = Vector2(160, 160)
const HISTORY_SLOT_GLYPH_SIZE: Vector2 = Vector2(80, 80)

# --- Synergy Tracking & Boons ---
var synergies_fired_this_round: Dictionary = {}
var run_score_multiplier_boon: float = 1.0
var extra_points_per_dice_glyph_boon: int = 0
var extra_max_rolls_boon: int = 0
var active_boons: Dictionary = {}


# --- Animation Control ---
@onready var roll_animation_controller: Node

# --- CORE UI Node References ---
@onready var roll_button: TextureButton = $UICanvas/MainGameUI/AnimatedRollButton
@onready var ui_canvas: CanvasLayer = $UICanvas

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
	roll_animation_controller = get_node_or_null("RollAnimationController")
	if not is_instance_valid(roll_animation_controller):
		printerr("CRITICAL: RollAnimationController node not found in Game.tscn!")
	else:
		print("Game: RollAnimationController node found.")
		# Connect to its signals
		if roll_animation_controller.has_signal("logical_roll_requested"):
			roll_animation_controller.logical_roll_requested.connect(_on_rac_logical_roll_requested)
		else: 
			printerr("ERROR: RollAnimationController missing 'logical_roll_requested' signal.")
		
		if roll_animation_controller.has_signal("fanfare_start_requested"):
			roll_animation_controller.fanfare_start_requested.connect(_on_rac_fanfare_start_requested)
		else: 
			printerr("ERROR: RollAnimationController missing 'fanfare_start_requested' signal.")

		if roll_animation_controller.has_signal("move_to_history_requested"):
			roll_animation_controller.move_to_history_requested.connect(_on_rac_move_to_history_requested)
		else: 
			printerr("ERROR: RollAnimationController missing 'move_to_history_requested' signal.")

		if roll_animation_controller.has_signal("full_animation_sequence_complete"):
			roll_animation_controller.full_animation_sequence_complete.connect(_on_rac_full_animation_sequence_complete)
		else: 
			printerr("ERROR: RollAnimationController missing 'full_animation_sequence_complete' signal.")

		# Setup references for the controller (this might be called again later once hud_instance is ready, which is fine)
		if roll_animation_controller.has_method("setup_references"):
			roll_animation_controller.setup_references(roll_button, ui_canvas, hud_instance) 
	auto_roll_delay_timer = Timer.new(); auto_roll_delay_timer.name = "AutoRollDelayTimer"
	auto_roll_delay_timer.wait_time = 0.25; auto_roll_delay_timer.one_shot = true
	auto_roll_delay_timer.timeout.connect(_on_auto_roll_delay_timer_timeout); add_child(auto_roll_delay_timer)

	if is_instance_valid(ui_canvas):
		SceneUIManager.set_ui_parent_node(ui_canvas)
	else:
		printerr("Game: CRITICAL - ui_canvas node not found, cannot set parent for SceneUIManager!")
		SceneUIManager.set_ui_parent_node(self)

	if hud_scene:
		hud_instance = hud_scene.instantiate()
		if is_instance_valid(ui_canvas): ui_canvas.add_child(hud_instance)
		else: add_child(hud_instance); printerr("UICanvas not found for HUD.")
		
		# Connect HUD signals
		if hud_instance.has_signal("inventory_toggled"): 
			hud_instance.inventory_toggled.connect(_on_hud_inventory_toggled)
		if hud_instance.has_signal("fanfare_animation_finished"): 
			hud_instance.fanfare_animation_finished.connect(_on_hud_fanfare_animation_finished)
		else: 
			printerr("WARNING: HUD.gd needs 'fanfare_animation_finished' signal.")
		hud_instance.visible = false # Initially hidden
		
		# Setup references for RollAnimationController again, now that hud_instance is valid
		if is_instance_valid(roll_animation_controller) and roll_animation_controller.has_method("setup_references"):
			roll_animation_controller.setup_references(roll_button, ui_canvas, hud_instance)

		playback_speed_button = hud_instance.get_node_or_null("PlaybackSpeedButton")
		if is_instance_valid(playback_speed_button) and playback_speed_button.has_signal("speed_changed"):
			playback_speed_button.speed_changed.connect(_on_playback_speed_changed)
			if playback_speed_button.has_method("get_current_speed"): Engine.time_scale = playback_speed_button.get_current_speed()
		
		auto_roll_button = hud_instance.get_node_or_null("AutoRollButton")
		if is_instance_valid(auto_roll_button) and auto_roll_button.has_signal("auto_roll_toggled"):
			auto_roll_button.auto_roll_toggled.connect(_on_auto_roll_toggled)
			if auto_roll_button.has_method("get_current_state"): auto_roll_enabled = auto_roll_button.get_current_state()
	else: 
		printerr("ERROR: HUD.tscn not preloaded!")
	
	# Connect to SceneUIManager signals
	SceneUIManager.main_menu_start_game_pressed.connect(_on_main_menu_start_game)
	SceneUIManager.loot_screen_loot_selected.connect(_on_loot_selected)
	SceneUIManager.loot_screen_skipped.connect(_on_loot_screen_closed)
	# NEW: Connect to the assumed signal from SceneUIManager for inventory requests from LootScreen
	if SceneUIManager.has_signal("loot_screen_inventory_requested"):
		SceneUIManager.loot_screen_inventory_requested.connect(_on_loot_screen_inventory_requested)
	else:
		printerr("Game: SceneUIManager does not have 'loot_screen_inventory_requested' signal. Loot screen inventory toggle may not work.")
	SceneUIManager.game_over_retry_pressed.connect(_on_game_over_retry_pressed)
	SceneUIManager.game_over_main_menu_pressed.connect(_on_game_over_main_menu_pressed)
	
	if not is_instance_valid(get_node_or_null("UICanvas")): 
		printerr("CRITICAL: UICanvas node not found in Game scene!")

	if is_instance_valid(roll_button): 
		roll_button.pressed.connect(_on_roll_button_pressed)
	
	if ProgressionManager.has_signal("game_phase_changed"): 
		ProgressionManager.game_phase_changed.connect(_on_progression_game_phase_changed)
	if ProgressionManager.has_signal("cornerstone_slot_unlocked"): 
		ProgressionManager.cornerstone_slot_unlocked.connect(_on_progression_cornerstone_unlocked)
	if ProgressionManager.has_signal("boss_indicator_update"): 
		ProgressionManager.boss_indicator_update.connect(_on_progression_boss_indicator_update)

	current_game_roll_state = GameRollState.MENU
	SceneUIManager.show_main_menu()
	print("Game: Requested SceneUIManager to show main menu.")


func _unhandled_input(event: InputEvent):
	if current_game_roll_state == GameRollState.LOOT_SELECTION:
		if Input.is_action_just_pressed("cancel_action"): # Escape key
			# Check if HUD's inventory panel is currently visible
			if is_instance_valid(hud_instance) and \
			   is_instance_valid(hud_instance.dice_face_scroll_container) and \
			   hud_instance.dice_face_scroll_container.visible:
				
				# If inventory is open, Escape closes inventory first.
				hud_instance.set_inventory_visibility(false)
				get_viewport().set_input_as_handled()
				print("Game: HUD Inventory closed by Escape key during loot selection.")
				return # Input handled, LootScreen remains. Press Escape again to skip loot.
			# If inventory was NOT visible, the input is NOT handled here.
			# It will fall through to LootScreen's _unhandled_input,
			# which will emit skip_loot_pressed, leading to _on_loot_screen_closed.


func _process(delta):
	match current_game_roll_state:
		GameRollState.MENU:
			var main_game_ui_node = get_node_or_null("UICanvas/MainGameUI")
			if is_instance_valid(main_game_ui_node): main_game_ui_node.visible = false
			if is_instance_valid(hud_instance): hud_instance.visible = false
		GameRollState.INITIALIZING_GAME:
			_initialize_new_game_run_setup() 
		GameRollState.INITIALIZING_ROUND:
			pass 
		GameRollState.PLAYING:
			var main_game_ui_node = get_node_or_null("UICanvas/MainGameUI")
			if is_instance_valid(main_game_ui_node) and not main_game_ui_node.visible: main_game_ui_node.visible = true
			if is_instance_valid(hud_instance) and not hud_instance.visible: hud_instance.visible = true
			if is_instance_valid(roll_button): roll_button.disabled = (player_current_rolls_this_round >= max_rolls_for_current_round)
			_update_hud_static_elements()
			_try_start_auto_roll()
		GameRollState.AWAITING_ANIMATION_COMPLETION:
			if is_instance_valid(roll_button): roll_button.disabled = true
		GameRollState.LOOT_SELECTION: 
			pass # Input handled by LootScreen and Game._unhandled_input
		GameRollState.GAME_OVER:
			if is_instance_valid(hud_instance): hud_instance.visible = false
			# SceneUIManager.show_game_over_screen is called in _end_round on loss
			pass


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
		if hud_instance.has_method("reset_full_game_visuals"): hud_instance.reset_full_game_visuals() # This now calls set_inventory_visibility(false)
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
	roll_history.clear(); synergies_fired_this_round.clear();
	print("Game: Round %d setup. Target:%d, MaxRolls:%d, Phase:%s" % [current_round_number_local, target_score_for_current_round, max_rolls_for_current_round, ProgressionManager.GamePhase.keys()[current_game_phase_local]])
	if is_instance_valid(hud_instance): 
		if hud_instance.has_method("reset_round_visuals"): hud_instance.reset_round_visuals()
		if hud_instance.has_method("activate_track_slots"): hud_instance.activate_track_slots(max_rolls_for_current_round)
		if hud_instance.has_method("update_dice_inventory_display"): # Ensure inventory is up-to-date if it was left open by HUD's own button
			if hud_instance.dice_face_scroll_container.visible:
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
		current_game_roll_state = GameRollState.GAME_OVER

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

func _perform_roll():
	print("Game: _perform_roll() CALLED.")
	# This now gets the glyph as it is on the dice, which might be a superposition type
	initial_rolled_glyph = PlayerDiceManager.get_random_glyph_from_dice()
	if not is_instance_valid(initial_rolled_glyph):
		printerr("CRITICAL ERROR in _perform_roll: PlayerDiceManager returned invalid glyph!")
		# Game.gd needs to handle this, perhaps by ending the roll or erroring out.
		# For now, RAC will also catch this if initial_rolled_glyph is null.
	else:
		print("Game: _perform_roll() - Initial roll: ", initial_rolled_glyph.display_name)

func _calculate_score_and_synergies(resolved_glyph_for_scoring: GlyphData, current_roll_history: Array[GlyphData]) -> Dictionary:
	var points_from_roll: int = 0
	var points_from_synergy: int = 0
	var points_from_entanglement: int = 0 # New variable for entanglement bonus
	var synergy_messages: Array[String] = []
	var entanglement_messages: Array[String] = [] # For entanglement feedback
	current_success_tier = SuccessTier.NONE

	if not is_instance_valid(resolved_glyph_for_scoring):
		printerr("Game: _calculate_score_and_synergies called with invalid resolved_glyph_for_scoring.")
		return {"points_from_roll":0, "points_from_synergy":0, "points_from_entanglement":0, "synergy_messages":[], "entanglement_messages":[]}
	
	# 1. Base score from the rolled (resolved) glyph
	points_from_roll = resolved_glyph_for_scoring.value 
	if resolved_glyph_for_scoring.type == "dice":
		points_from_roll += extra_points_per_dice_glyph_boon
	
	# 2. Cornerstone bonus (if applicable)
	var current_logical_slot_index = current_roll_history.size()
	if ProgressionManager.is_cornerstone_effect_active(2) and current_logical_slot_index == 2:
		points_from_roll += CORNERSTONE_SLOT_3_BONUS 
		PlayerNotificationSystem.display_message("Cornerstone Slot 3 Bonus: +%d Score!" % CORNERSTONE_SLOT_3_BONUS) # This could be part of synergy_messages

	# --- Entanglement Check (Photon Twins "Shared Momentum") ---
	if resolved_glyph_for_scoring.is_entangled and \
	   resolved_glyph_for_scoring.entangled_effect_type == GlyphData.EntangledEffectType.SHARED_MOMENTUM_SCORE_BONUS:
		
		var player_dice: Array[GlyphData] = PlayerDiceManager.get_current_dice()
		for glyph_on_die in player_dice:
			if is_instance_valid(glyph_on_die) and \
			   glyph_on_die.is_entangled and \
			   glyph_on_die.entanglement_id == resolved_glyph_for_scoring.entanglement_id and \
			   glyph_on_die.id != resolved_glyph_for_scoring.id:
				
				var entanglement_bonus_value = glyph_on_die.value # Get the bonus value
				points_from_entanglement += entanglement_bonus_value
				var message = "Entangled! '%s' on dice adds +%d (via %s)" % [glyph_on_die.display_name, entanglement_bonus_value, resolved_glyph_for_scoring.display_name]
				entanglement_messages.append(message)
				PlayerNotificationSystem.display_message(message)
				
				# Visual feedback trigger
				if is_instance_valid(hud_instance) and hud_instance.has_method("trigger_entanglement_visuals"):
					# We need the slot index of the resolved_glyph_for_scoring
					# current_roll_history.size() is the index where it WILL be placed.
					var rolled_glyph_slot_idx = current_roll_history.size() 
					hud_instance.trigger_entanglement_visuals(rolled_glyph_slot_idx, glyph_on_die, entanglement_bonus_value) # Pass index, partner, and bonus

				print("Game: Entanglement triggered: %s (rolled) with %s (on dice). Bonus: +%d" % [resolved_glyph_for_scoring.id, glyph_on_die.id, entanglement_bonus_value])
				break
	
	# Add points from roll and entanglement to score before synergy calculation
	ScoreManager.add_to_round_score(points_from_roll + points_from_entanglement)

	# 3. Standard Synergies and Boons
	# Synergies are checked with a temporary history that includes the current resolved glyph
	var temp_history_with_current_resolved_glyph = current_roll_history.duplicate(true)
	temp_history_with_current_resolved_glyph.append(resolved_glyph_for_scoring)
	
	var eval_result = _evaluate_synergies_and_boons(temp_history_with_current_resolved_glyph)
	points_from_synergy = eval_result.bonus_score
	synergy_messages.append_array(eval_result.messages) # Append boon messages
	
	if points_from_synergy > 0: 
		ScoreManager.add_to_round_score(points_from_synergy) # Add synergy points
	
	# Add all points for this roll to total accumulated score
	ScoreManager.add_to_total_score(points_from_roll + points_from_entanglement + points_from_synergy)
	
	# Combine messages for HUD
	var all_messages_for_fanfare = entanglement_messages.duplicate()
	all_messages_for_fanfare.append_array(synergy_messages)

	print("Game: Score calculated for resolved glyph '%s'. Roll: %d, Entangle: %d, Synergy: %d" % [resolved_glyph_for_scoring.display_name, points_from_roll, points_from_entanglement, points_from_synergy])
	return {
		"points_from_roll": points_from_roll, 
		"points_from_synergy": points_from_synergy, 
		"points_from_entanglement": points_from_entanglement, # Pass this back too
		"synergy_messages": all_messages_for_fanfare # Combined messages
	}

func _evaluate_synergies_and_boons(p_history_for_check: Array[GlyphData]) -> Dictionary:
	var total_synergy_bonus: int = 0
	var messages: Array[String] = []
	if p_history_for_check.is_empty(): return {"bonus_score": 0, "messages": []}

	if not synergies_fired_this_round.has("numeric_double"):
		var d_seen:Dictionary={}; for r in p_history_for_check: if r.type=="dice": d_seen[r.value]=d_seen.get(r.value,0)+1; if d_seen[r.value]>=2: total_synergy_bonus+=5;synergies_fired_this_round["numeric_double"]=true;messages.append("NUMERIC DOUBLE! +5");break
	
	var current_runes_in_history_ids: Array[String]=[]
	for roll_data in p_history_for_check:
		if roll_data.type == "rune" and is_instance_valid(roll_data) and roll_data.id != "":
			current_runes_in_history_ids.append(roll_data.id)
	
	var newly_activated_boons_info: Array[Dictionary] = BoonManager.check_and_activate_rune_phrases(current_runes_in_history_ids)
	for boon_info in newly_activated_boons_info:
		messages.append("BOON: %s! (%s)" % [boon_info.name, boon_info.description])
		active_boons[boon_info.name] = true
		_apply_boon_effect(boon_info.name)
	return {"bonus_score": total_synergy_bonus, "messages": messages}

func _on_hud_fanfare_animation_finished():
	print("Game: HUD reported fanfare animation finished.")
	if current_game_roll_state == GameRollState.AWAITING_ANIMATION_COMPLETION:
		if is_instance_valid(roll_animation_controller) and roll_animation_controller.has_method("hud_fanfare_has_completed"):
			roll_animation_controller.hud_fanfare_has_completed()
	else:
		print("Game: HUD fanfare finished, but GameRollState is not AWAITING_ANIMATION_COMPLETION. State: ", GameRollState.keys()[current_game_roll_state])

func _finalize_roll_logic_and_proceed():
	# This function is called AFTER full animation sequence is complete,
	# and last_resolved_glyph should be set by then.
	if not is_instance_valid(last_resolved_glyph):
		printerr("Game: _finalize_roll_logic_and_proceed called but last_resolved_glyph is invalid!")
		# Potentially end round or handle error, for now, try to continue if possible
		# but this indicates a flaw in the animation callback sequence.
	else:
		roll_history.append(last_resolved_glyph) # Add the RESOLVED glyph to history
		print("Game: Resolved glyph '%s' added to roll_history." % last_resolved_glyph.display_name)

	player_current_rolls_this_round += 1 # Increment rolls here, after all processing for the roll is done.
	
	var sm_round_score = ScoreManager.get_current_round_score()
	print("Game: Roll finalized. Rolls used: %d/%d. Round Score: %d" % [player_current_rolls_this_round, max_rolls_for_current_round, sm_round_score])
	
	initial_rolled_glyph = null # Clear initial for next roll
	last_resolved_glyph = null  # Clear resolved for next roll
	_update_hud_static_elements()
	
	if player_current_rolls_this_round >= max_rolls_for_current_round or sm_round_score >= target_score_for_current_round:
		_end_round()
	else:
		current_game_roll_state = GameRollState.PLAYING
		if is_instance_valid(roll_button): roll_button.disabled = false
		_try_start_auto_roll()

func _on_main_menu_start_game():
	print("Game: Start game triggered by SceneUIManager.")
	current_game_roll_state = GameRollState.INITIALIZING_GAME

func _prepare_and_show_loot_screen():
	var loot_options = GlyphDB.get_random_loot_options(3)
	if not loot_options.is_empty():
		SceneUIManager.show_loot_screen(loot_options) # SceneUIManager will connect to its signals
		play_sound(sfx_loot_appears)
	else:
		PlayerNotificationSystem.display_message("No loot options available this time.")
		call_deferred("_start_new_round_setup")

func _on_loot_screen_inventory_requested():
	print("Game: Loot screen requested inventory to be shown.")
	if is_instance_valid(hud_instance):
		hud_instance.set_inventory_visibility(true)

func _on_loot_selected(chosen_glyph: GlyphData):
	print("Game: Loot selected (via SceneUIManager): ", chosen_glyph.display_name)
	# Ensure HUD inventory is hidden when loot selection is done
	if is_instance_valid(hud_instance):
		hud_instance.set_inventory_visibility(false)
		
	PlayerDiceManager.add_glyph_to_dice(chosen_glyph)
	ScoreManager.add_to_total_score(50) # Bonus for selecting loot
	play_sound(sfx_glyph_added)
	call_deferred("_start_new_round_setup")

func _on_loot_screen_closed(): # Handles both skip button and Escape key from LootScreen
	print("Game: Loot screen closed/skipped (via SceneUIManager).")
	# Ensure HUD inventory is hidden when loot screen is closed/skipped
	if is_instance_valid(hud_instance):
		hud_instance.set_inventory_visibility(false)
		
	PlayerNotificationSystem.display_message("Loot skipped.")
	call_deferred("_start_new_round_setup")

func _on_game_over_retry_pressed():
	print("Game: Retry pressed (via SceneUIManager).")
	current_game_roll_state = GameRollState.INITIALIZING_GAME

func _on_game_over_main_menu_pressed():
	print("Game: Main Menu from GameOver pressed (via SceneUIManager).")
	current_game_roll_state = GameRollState.MENU
	SceneUIManager.show_main_menu()
	
func _on_hud_inventory_toggled(is_inventory_visible: bool):
	# This is for HUD's own inventory button.
	# If inventory becomes visible, ensure it's up-to-date.
	if is_inventory_visible and is_instance_valid(hud_instance):
		if hud_instance.has_method("update_dice_inventory_display"):
			hud_instance.update_dice_inventory_display(PlayerDiceManager.get_current_dice())

func play_sound(sound_resource: AudioStream, volume: int = 0):
	if sfx_player and sound_resource: sfx_player.stream=sound_resource;sfx_player.volume_db=volume;sfx_player.play()
	
func _on_playback_speed_changed(new_speed_multiplier: float):
	Engine.time_scale = new_speed_multiplier

func _on_auto_roll_toggled(is_enabled: bool):
	auto_roll_enabled = is_enabled
	if auto_roll_enabled: _try_start_auto_roll()
	elif is_instance_valid(auto_roll_delay_timer) and not auto_roll_delay_timer.is_stopped(): auto_roll_delay_timer.stop()

func _try_start_auto_roll():
	var can_roll=true
	if not auto_roll_enabled: can_roll=false
	elif current_game_roll_state!=GameRollState.PLAYING: can_roll=false
	elif (max_rolls_for_current_round-player_current_rolls_this_round)<=0: can_roll=false
	elif not is_instance_valid(roll_button) or roll_button.disabled: can_roll=false
	elif not is_instance_valid(auto_roll_delay_timer) or not auto_roll_delay_timer.is_stopped(): can_roll=false
	if can_roll: auto_roll_delay_timer.start()

func _on_auto_roll_delay_timer_timeout():
	var can_perform=true
	if not auto_roll_enabled: can_perform=false
	elif current_game_roll_state!=GameRollState.PLAYING: can_perform=false
	elif (max_rolls_for_current_round-player_current_rolls_this_round)<=0: can_perform=false
	elif not is_instance_valid(roll_button) or roll_button.disabled: can_perform=false
	if can_perform: _on_roll_button_pressed()
	else:
		if auto_roll_enabled and current_game_roll_state==GameRollState.PLAYING and (max_rolls_for_current_round-player_current_rolls_this_round)>0:
			_try_start_auto_roll()

func _on_roll_button_pressed():
	if current_game_roll_state == GameRollState.PLAYING and (max_rolls_for_current_round - player_current_rolls_this_round) > 0 :
		current_game_roll_state = GameRollState.AWAITING_ANIMATION_COMPLETION
		if is_instance_valid(roll_button): roll_button.disabled = true
		if is_instance_valid(roll_animation_controller) and roll_animation_controller.has_method("start_full_roll_sequence"):
			roll_animation_controller.start_full_roll_sequence()
		else:
			printerr("Game: RollAnimationController not valid or missing start_full_roll_sequence method!")
			current_game_roll_state = GameRollState.PLAYING 
			if is_instance_valid(roll_button): roll_button.disabled = (player_current_rolls_this_round >= max_rolls_for_current_round)

# --- Callbacks for RollAnimationController Signals ---
func _on_rac_logical_roll_requested():
	print("Game: RollAnimationController requested logical roll.")
	_perform_roll() # Sets Game.initial_rolled_glyph
	
	# Send the initial (possibly superposition) glyph to the RAC
	if is_instance_valid(roll_animation_controller) and roll_animation_controller.has_method("set_logical_roll_result"):
		roll_animation_controller.set_logical_roll_result(initial_rolled_glyph)
	else:
		printerr("Game: Cannot send logical roll result back to RollAnimationController.")

func _on_rac_fanfare_start_requested(p_resolved_glyph: GlyphData, _p_temp_anim_glyph_node: TextureRect):
	print("Game: RollAnimationController requested fanfare start for resolved_glyph: '%s'." % p_resolved_glyph.display_name if is_instance_valid(p_resolved_glyph) else "Invalid Glyph")
	
	if not is_instance_valid(p_resolved_glyph):
		printerr("Game: Fanfare requested with invalid resolved_glyph from RAC!")
		if is_instance_valid(roll_animation_controller) and roll_animation_controller.has_method("hud_fanfare_has_completed"):
			roll_animation_controller.hud_fanfare_has_completed()
		return

	last_resolved_glyph = p_resolved_glyph

	var score_data = _calculate_score_and_synergies(last_resolved_glyph, roll_history)

	if is_instance_valid(hud_instance) and hud_instance.has_method("play_score_fanfare"):
		# HUD's play_score_fanfare might need adjustment if you want to show entanglement points separately
		# For now, let's assume points_from_roll can include the entanglement bonus for the popup.
		# Or, add a new parameter to play_score_fanfare for entanglement points.
		# Let's combine them for the "roll points" for simplicity now.
		var combined_direct_points = score_data.points_from_roll + score_data.points_from_entanglement
		
		hud_instance.play_score_fanfare(
			combined_direct_points, # Roll points + Entanglement points
			score_data.points_from_synergy, 
			ScoreManager.get_current_round_score(), 
			score_data.synergy_messages, # Contains both entanglement and synergy/boon messages
			current_success_tier 
		)
	else: 
		print("Game: HUD cannot play score fanfare. Telling RollAnimationController it's complete.")
		if is_instance_valid(roll_animation_controller) and roll_animation_controller.has_method("hud_fanfare_has_completed"):
			roll_animation_controller.hud_fanfare_has_completed()

func _on_rac_move_to_history_requested(p_animating_glyph_node: TextureRect, p_final_glyph: GlyphData):
	# ----> ADD/CONFIRM THIS PRINT <----
	print("Game: _on_rac_move_to_history_requested CALLED for glyph: %s." % p_final_glyph.display_name if is_instance_valid(p_final_glyph) else "Invalid Glyph")
	
	if not is_instance_valid(p_animating_glyph_node) or not is_instance_valid(p_final_glyph):
		printerr("Game: Invalid node or glyph data for move_to_history_requested. Node: %s, Glyph: %s" % [str(p_animating_glyph_node), str(p_final_glyph)])
		if is_instance_valid(roll_animation_controller) and roll_animation_controller.has_method("animation_move_to_history_finished"):
			roll_animation_controller.animation_move_to_history_finished() 
		return

	var target_slot_center_pos: Vector2
	if is_instance_valid(hud_instance) and hud_instance.has_method("get_next_history_slot_global_position"):
		target_slot_center_pos = hud_instance.get_next_history_slot_global_position()
	else: 
		printerr("Game: HUD cannot provide history slot position for move_to_history.")
		target_slot_center_pos = get_viewport_rect().size / 2.0 

	var tween_to_history = create_tween()
	tween_to_history.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS) 
	tween_to_history.finished.connect(_on_internal_move_to_history_tween_finished)

	tween_to_history.set_parallel(true) 
	var target_visual_pos = target_slot_center_pos - (HISTORY_SLOT_GLYPH_SIZE / 2.0)
	
	if not is_instance_valid(p_animating_glyph_node) or not p_animating_glyph_node.is_inside_tree():
		printerr("Game: p_animating_glyph_node is invalid (%s) or not in tree for history tween." % str(p_animating_glyph_node))
		if is_instance_valid(roll_animation_controller) and roll_animation_controller.has_method("animation_move_to_history_finished"):
			roll_animation_controller.animation_move_to_history_finished()
		return
		
	tween_to_history.tween_property(p_animating_glyph_node, "global_position", target_visual_pos, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween_to_history.tween_property(p_animating_glyph_node, "custom_minimum_size", HISTORY_SLOT_GLYPH_SIZE, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween_to_history.tween_property(p_animating_glyph_node, "size", HISTORY_SLOT_GLYPH_SIZE, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	# ----> ADD/CONFIRM THIS PRINT <----
	print("Game: Tween to history STARTED for glyph: %s. Target pos: %s" % [p_final_glyph.display_name, str(target_visual_pos)])

func _on_internal_move_to_history_tween_finished():
	# ----> ADD/CONFIRM THIS PRINT <----
	print("Game: _on_internal_move_to_history_tween_finished CALLED.")
	if is_instance_valid(roll_animation_controller) and roll_animation_controller.has_method("animation_move_to_history_finished"):
		roll_animation_controller.animation_move_to_history_finished()

func _on_rac_full_animation_sequence_complete(final_resolved_glyph_data: GlyphData):
	# RAC now sends the FINAL RESOLVED glyph.
	print("Game: RollAnimationController reported full_animation_sequence_complete. Final resolved glyph: ", final_resolved_glyph_data.display_name if final_resolved_glyph_data else "N/A")
	
	if not is_instance_valid(final_resolved_glyph_data):
		printerr("Game: Animation sequence completed with invalid final_resolved_glyph_data. Problems may occur.")
		# It's crucial that last_resolved_glyph is valid for _finalize_roll_logic_and_proceed
		# If final_resolved_glyph_data is bad here, last_resolved_glyph might also be bad if fanfare was skipped.
		# For safety, if fanfare path didn't set last_resolved_glyph, try to set it here.
		if not is_instance_valid(last_resolved_glyph) and is_instance_valid(final_resolved_glyph_data):
			last_resolved_glyph = final_resolved_glyph_data
		elif not is_instance_valid(last_resolved_glyph) and not is_instance_valid(final_resolved_glyph_data):
			# Major issue, no valid glyph to proceed with.
			# Consider ending the round with an error state or special handling.
			# For now, _finalize_roll_logic_and_proceed will print an error.
			pass 
	elif not is_instance_valid(last_resolved_glyph):
		# If fanfare path was skipped or failed to set last_resolved_glyph, use the one from this signal
		last_resolved_glyph = final_resolved_glyph_data
	elif last_resolved_glyph != final_resolved_glyph_data:
		printerr("Game: Mismatch between last_resolved_glyph from fanfare ('%s') and final_resolved_glyph_data from sequence_complete ('%s'). Using sequence_complete." % [last_resolved_glyph.display_name, final_resolved_glyph_data.display_name])
		last_resolved_glyph = final_resolved_glyph_data # Prioritize the one from sequence complete

	# Update HUD's visual track with the resolved glyph
	if is_instance_valid(hud_instance) and hud_instance.has_method("add_glyph_to_visual_history"):
		if is_instance_valid(last_resolved_glyph): # Ensure we have a valid glyph to add
			hud_instance.add_glyph_to_visual_history(last_resolved_glyph)
		else:
			printerr("Game: Cannot add glyph to visual history, last_resolved_glyph is invalid at sequence_complete.")
	
	_finalize_roll_logic_and_proceed() # This updates logical history, checks for round end

func _reset_boons_and_effects():
	active_boons.clear()
	extra_points_per_dice_glyph_boon = 0
	extra_max_rolls_boon = 0

func _apply_boon_effect(boon_id: String):
	if boon_id == "sun_power":
		extra_points_per_dice_glyph_boon = BoonManager.get_extra_points_for_dice_glyph()
	elif boon_id == "water_flow":
		var current_bm_extra_rolls = BoonManager.get_extra_max_rolls()
		if current_bm_extra_rolls != extra_max_rolls_boon:
			extra_max_rolls_boon = current_bm_extra_rolls
			_update_hud_static_elements()
