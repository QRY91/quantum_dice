extends Node2D

@onready var progressbar = $ProgressBar

var score = 0

# Called when the node enters the scene tree for the first time.
func _ready():
	score = 50
	progressbar.init_score(score)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
