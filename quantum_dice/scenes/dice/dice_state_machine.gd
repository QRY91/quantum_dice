class_name DiceStateMachine
extends Node

@export var initial_state: DiceState

var current_state: DiceState
var states := {}

func init(dice: Dice) -> void:
	for child in get_children():
		if child is DiceState:
			states[child.state] = child
			child.transition_requested.connect(_on_transition_requested)
			child.dice = dice
	
	if initial_state:
		initial_state.enter()
		current_state = initial_state

func on_input(event: InputEvent) -> void:
	if current_state:
		current_state.on_input(event)

func on_gui_input(event: InputEvent) -> void:
	if current_state:
		current_state.on_gui_input(event)

func on_mouse_entered() -> void:
	if current_state:
		current_state.on_mouse_entered()

func on_mouse_exited() -> void:
	if current_state:
		current_state.on_mouse_exited()

func _on_transition_requested(from: DiceState, to: DiceState.State) -> void:
	if from != current_state:
		return
		
	var new_state: DiceState = states[to]
	if not new_state:
		return
	
	if current_state:
		current_state.exit()
	
	new_state.enter()
	current_state = new_state
