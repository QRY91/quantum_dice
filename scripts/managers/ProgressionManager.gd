# res://scripts/managers/ProgressionManager.gd
# TABS FOR INDENTATION
extends Node

signal game_phase_changed(new_phase: int) 
signal cornerstone_slot_unlocked(slot_index_zero_based: int, is_unlocked: bool)
signal boss_indicator_update(show: bool, message: String)

# DUPLICATE GamePhase Enum here for now
enum GamePhase {
	PRE_BOSS,
	FIRST_BOSS_ENCOUNTER,
	MID_GAME_CYCLE,
	MID_GAME_BOSS_ENCOUNTER
}

var current_round_number: int = 0
var current_game_phase: int = GamePhase.PRE_BOSS # Use local enum
var is_first_15_roll_round_reached: bool = false
var is_first_boss_defeated: bool = false
var is_cornerstone_slot_3_active: bool = false
var mid_game_cycle_round_counter: int = 0

const BASE_TARGET_SCORE_PM: int = 15
const TARGET_SCORE_PER_ROUND_INCREASE_PM: int = 7
const MAX_ROLLS_CAP_PM: int = 15
const FIRST_BOSS_SCORE_MULTIPLIER_PM: float = 1.25
const MID_GAME_BOSS_SCORE_MULTIPLIER_PM: float = 1.35

func initialize_new_run():
	print("ProgressionManager: Initializing new run.")
	current_round_number = 0
	is_first_15_roll_round_reached = false
	is_first_boss_defeated = false
	is_cornerstone_slot_3_active = false
	emit_signal("cornerstone_slot_unlocked", 2, false)
	mid_game_cycle_round_counter = 0
	set_game_phase(GamePhase.PRE_BOSS) # Use local enum

func set_game_phase(new_phase: int): # new_phase is an int from the local GamePhase enum
	if current_game_phase == new_phase:
		return
	current_game_phase = new_phase
	emit_signal("game_phase_changed", current_game_phase) # Emit the int value
	print("ProgressionManager: Game phase changed to ", GamePhase.keys()[current_game_phase])


func get_next_round_setup() -> Dictionary:
	current_round_number += 1
	print("ProgressionManager: --- Calculating setup for new round: %d ---" % current_round_number)

	var round_config = {
		"round_number": current_round_number,
		"max_rolls": 0,
		"target_score": 0,
		"is_boss_round": false,
		"current_phase_for_round": current_game_phase 
	}

	if current_round_number == 1: round_config.max_rolls = 7
	elif current_round_number == 2: round_config.max_rolls = 10
	elif current_round_number == 3: round_config.max_rolls = 12
	else: round_config.max_rolls = MAX_ROLLS_CAP_PM
	
	round_config.target_score = BASE_TARGET_SCORE_PM + (current_round_number - 1) * TARGET_SCORE_PER_ROUND_INCREASE_PM

	var phase_for_this_round_start = current_game_phase 

	if not is_first_boss_defeated:
		if is_first_15_roll_round_reached: 
			phase_for_this_round_start = GamePhase.FIRST_BOSS_ENCOUNTER # Use local enum
			round_config.is_boss_round = true
		else:
			phase_for_this_round_start = GamePhase.PRE_BOSS # Use local enum
	else: 
		if current_game_phase == GamePhase.MID_GAME_BOSS_ENCOUNTER: # If previous round was a boss
			mid_game_cycle_round_counter = 1 # Start new cycle
			phase_for_this_round_start = GamePhase.MID_GAME_CYCLE
		elif current_game_phase == GamePhase.MID_GAME_CYCLE:
			mid_game_cycle_round_counter += 1
			if mid_game_cycle_round_counter == 3:
				phase_for_this_round_start = GamePhase.MID_GAME_BOSS_ENCOUNTER
				round_config.is_boss_round = true
			else: # Still in MID_GAME_CYCLE (1 or 2)
				phase_for_this_round_start = GamePhase.MID_GAME_CYCLE
		elif current_game_phase == GamePhase.PRE_BOSS: # Should not happen if is_first_boss_defeated is true, but for safety
			mid_game_cycle_round_counter = 1
			phase_for_this_round_start = GamePhase.MID_GAME_CYCLE


	set_game_phase(phase_for_this_round_start)
	round_config.current_phase_for_round = current_game_phase


	var boss_indicator_msg: String = ""
	var show_indicator: bool = false

	if round_config.is_boss_round:
		if current_game_phase == GamePhase.FIRST_BOSS_ENCOUNTER:
			round_config.target_score = int(float(round_config.target_score) * FIRST_BOSS_SCORE_MULTIPLIER_PM)
			PlayerNotificationSystem.display_message("BOSS ENCOUNTER ROUND! (First)")
		elif current_game_phase == GamePhase.MID_GAME_BOSS_ENCOUNTER:
			round_config.target_score = int(float(round_config.target_score) * MID_GAME_BOSS_SCORE_MULTIPLIER_PM)
			PlayerNotificationSystem.display_message("BOSS ENCOUNTER ROUND (Mid-Game)!")
	else: 
		if current_game_phase == GamePhase.PRE_BOSS:
			if round_config.max_rolls == MAX_ROLLS_CAP_PM and not is_first_15_roll_round_reached:
				show_indicator = true
				boss_indicator_msg = "Win this 15-roll round to face the First Boss!"
		elif current_game_phase == GamePhase.MID_GAME_CYCLE:
			if mid_game_cycle_round_counter == 2: 
				show_indicator = true
				boss_indicator_msg = "Next Round: Mid-Game Boss!"
	
	emit_signal("boss_indicator_update", show_indicator, boss_indicator_msg)
	
	print("ProgressionManager: Round %d Setup: Target:%d, Rolls:%d, Phase:%s, MidCycle:%d, IsBoss:%s" % [
		current_round_number, round_config.target_score, round_config.max_rolls, 
		GamePhase.keys()[current_game_phase], mid_game_cycle_round_counter if is_first_boss_defeated else 0, str(round_config.is_boss_round)
	])
	return round_config


func process_round_win(p_current_round_number: int, p_max_rolls_this_round: int, p_rolls_used: int, p_roll_history: Array):
	print("ProgressionManager: Processing win for round ", p_current_round_number)
	
	var previous_phase_before_win_logic = current_game_phase

	if p_max_rolls_this_round == MAX_ROLLS_CAP_PM and not is_first_15_roll_round_reached:
		is_first_15_roll_round_reached = true
		PlayerNotificationSystem.display_message("First 15-roll round completed!")
		print("ProgressionManager: is_first_15_roll_round_reached set to true.")

	if previous_phase_before_win_logic == GamePhase.FIRST_BOSS_ENCOUNTER:
		var boss_condition_met = false
		if p_rolls_used == MAX_ROLLS_CAP_PM:
			if not p_roll_history.is_empty():
				var final_glyph: GlyphData = p_roll_history.back()
				if is_instance_valid(final_glyph) and final_glyph.value > 4:
					boss_condition_met = true
		
		if boss_condition_met:
			is_first_boss_defeated = true
			is_cornerstone_slot_3_active = true
			PlayerNotificationSystem.display_message("FIRST BOSS DEFEATED! Cornerstone Slot 3 Activated!")
			emit_signal("cornerstone_slot_unlocked", 2, true)
			print("ProgressionManager: First Boss defeated, Cornerstone 3 active.")
			set_game_phase(GamePhase.MID_GAME_CYCLE) 
			mid_game_cycle_round_counter = 0 
		else:
			PlayerNotificationSystem.display_message("Boss challenge condition missed, but round cleared!")

	elif previous_phase_before_win_logic == GamePhase.MID_GAME_BOSS_ENCOUNTER:
		PlayerNotificationSystem.display_message("Mid-Game Boss Defeated! (Placeholder)")
		print("ProgressionManager: Mid-Game Boss defeated.")
		set_game_phase(GamePhase.MID_GAME_CYCLE)
		mid_game_cycle_round_counter = 0
	
	# If it was MID_GAME_CYCLE and won, mid_game_cycle_round_counter is handled by get_next_round_setup
	# when it prepares for the *next* round.


func is_cornerstone_effect_active(slot_index_zero_based: int) -> bool:
	if slot_index_zero_based == 2:
		return is_cornerstone_slot_3_active
	return false
