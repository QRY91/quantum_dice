extends DiceState


func enter() -> void:
	if not dice.is_node_ready():
		await dice.ready

	dice.reparent_requested.emit(dice)
	dice.color.color = Color.WEB_GREEN
	dice.state.text = "BASE"
	dice.pivot_offset = Vector2.ZERO

