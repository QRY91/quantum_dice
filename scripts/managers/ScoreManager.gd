# res://scripts/managers/ScoreManager.gd
# TABS FOR INDENTATION
extends Node

signal round_score_updated(new_round_score: int)
signal total_score_updated(new_total_score: int)
signal high_score_updated(new_high_score: int)

var current_round_score: int = 0
var total_accumulated_score: int = 0
var high_score: int = 0

const HIGH_SCORE_FILE_PATH: String = "user://quantum_dice_highscore.dat" # Keep consistent

func _ready():
	load_high_score()

func reset_for_new_run():
	current_round_score = 0
	total_accumulated_score = 0
	# High score persists across runs
	print("ScoreManager: Scores reset for new run.")
	emit_signal("round_score_updated", current_round_score)
	emit_signal("total_score_updated", total_accumulated_score)

func reset_for_new_round():
	current_round_score = 0
	print("ScoreManager: Round score reset.")
	emit_signal("round_score_updated", current_round_score)

func add_to_round_score(points: int):
	if points == 0: return # No change, no signal
	current_round_score += points
	print("ScoreManager: Added %d to round score. New round score: %d" % [points, current_round_score])
	emit_signal("round_score_updated", current_round_score)

func add_to_total_score(points: int):
	if points == 0: return
	total_accumulated_score += points
	print("ScoreManager: Added %d to total score. New total score: %d" % [points, total_accumulated_score])
	emit_signal("total_score_updated", total_accumulated_score)
	
	# Check and update high score if total score surpasses it
	if total_accumulated_score > high_score:
		set_high_score(total_accumulated_score)

func get_current_round_score() -> int:
	return current_round_score

func get_total_accumulated_score() -> int:
	return total_accumulated_score

func get_high_score() -> int:
	return high_score

func set_high_score(new_score: int):
	if new_score > high_score:
		high_score = new_score
		save_high_score()
		emit_signal("high_score_updated", high_score)
		print("ScoreManager: New high score set: %d" % high_score)

func load_high_score():
	if FileAccess.file_exists(HIGH_SCORE_FILE_PATH):
		var file = FileAccess.open(HIGH_SCORE_FILE_PATH, FileAccess.READ)
		if is_instance_valid(file):
			var loaded_val = file.get_as_text().to_int()
			high_score = loaded_val
			file.close()
			print("ScoreManager: High score loaded: ", high_score)
			emit_signal("high_score_updated", high_score)
		else:
			printerr("ScoreManager: Failed to open high score file for reading. Error: ", FileAccess.get_open_error())
	else:
		print("ScoreManager: No high score file found. Starting fresh.")
		high_score = 0 # Ensure it's initialized
		emit_signal("high_score_updated", high_score)


func save_high_score():
	var file = FileAccess.open(HIGH_SCORE_FILE_PATH, FileAccess.WRITE)
	if is_instance_valid(file):
		file.store_string(str(high_score))
		file.close()
		print("ScoreManager: High score saved: ", high_score)
	else:
		printerr("ScoreManager: Failed to open high score file for writing. Error: ", FileAccess.get_open_error())
