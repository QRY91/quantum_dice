class_name DiceState
extends Node

enum State {BASE, CLICKED, ROLLING, SCORING, RELEASED}

signal transition_requested(from: DiceState, to: State)

@export var state: State

var dice: Dice

func enter() -> void:
	pass

func exit() -> void:
	pass

func on_input(_event: InputEvent) -> void:
	pass

func on_gui_input(_event: InputEvent) -> void:
	pass
