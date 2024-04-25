extends ProgressBar


@onready var timer = $Timer
@onready var score_bar = $ScoreBar

const TARGET_SCORE = 100

var score = 0 : set = _set_score

func _set_score(new_score):
	var prev_score = score
	score = min(max_value, new_score)
	value = score
	
	if score >= TARGET_SCORE:
		queue_free()
	
	if score > prev_score:
		timer.start()
	else:
		score_bar.value = score

func init_score(_score):
	score = _score
	max_value = score
	value = score
	
	score_bar.max_value = score
	score_bar.value = score


func _on_timer_timeout():
	score_bar.value = score
