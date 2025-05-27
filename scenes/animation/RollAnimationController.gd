# res://scripts/animation/RollAnimationController.gd
# TABS FOR INDENTATION
extends Node

# --- Signals to Game.gd ---
signal visual_roll_animation_started
signal logical_roll_requested
signal glyph_revealed_on_button(glyph_data: GlyphData)
signal fanfare_start_requested(rolled_glyph: GlyphData, temp_anim_glyph_node: TextureRect)
signal move_to_history_requested(temp_anim_glyph_node: TextureRect, final_glyph: GlyphData)
signal full_animation_sequence_complete(final_glyph_data: GlyphData)

enum AnimState {
	IDLE,
	DICE_ROLL_VISUAL,
	REVEAL_ON_BUTTON,
	MOVING_TO_CENTER,
	AWAITING_HUD_FANFARE,
	MOVING_TO_HISTORY
}
var current_anim_state: AnimState = AnimState.IDLE

var game_roll_button: TextureButton
var game_ui_canvas: CanvasLayer
var game_hud_instance: Control # For getting history slot positions via TrackManager

var animating_glyph_node: TextureRect = null

@onready var dice_roll_effect_timer: Timer = $DiceRollEffectTimer
@onready var reveal_on_button_timer: Timer = $RevealOnButtonTimer

const DICE_ROLL_EFFECT_DURATION: float = 0.1 
const REVEAL_ON_BUTTON_DURATION: float = 0.75

var _current_logically_rolled_glyph: GlyphData = null

func _ready():
	if is_instance_valid(dice_roll_effect_timer):
		dice_roll_effect_timer.one_shot = true
		dice_roll_effect_timer.wait_time = DICE_ROLL_EFFECT_DURATION
		dice_roll_effect_timer.timeout.connect(Callable(self, "_on_dice_roll_effect_timer_timeout"))
	else:
		printerr("RollAnimationController: DiceRollEffectTimer node not found!")

	if is_instance_valid(reveal_on_button_timer):
		reveal_on_button_timer.one_shot = true
		reveal_on_button_timer.wait_time = REVEAL_ON_BUTTON_DURATION
		reveal_on_button_timer.timeout.connect(Callable(self, "_on_reveal_on_button_timer_timeout"))
	else:
		printerr("RollAnimationController: RevealOnButtonTimer node not found!")
	
	current_anim_state = AnimState.IDLE

func setup_references(p_roll_button: TextureButton, p_ui_canvas: CanvasLayer, p_hud: Control):
	game_roll_button = p_roll_button
	game_ui_canvas = p_ui_canvas
	game_hud_instance = p_hud # Game.gd will pass its hud_instance
	print("RollAnimationController: References set up.")

func start_full_roll_sequence():
	if current_anim_state != AnimState.IDLE:
		printerr("RollAnimationController: Cannot start new sequence, busy: ", AnimState.keys()[current_anim_state])
		return

	print("RollAnimationController: Starting full roll sequence.")
	_current_logically_rolled_glyph = null
	current_anim_state = AnimState.DICE_ROLL_VISUAL
	emit_signal("visual_roll_animation_started")

	var roll_anim_player = game_roll_button.get_node_or_null("RollAnimationDisplay")
	if is_instance_valid(roll_anim_player) and roll_anim_player is AnimatedSprite2D:
		roll_anim_player.play("default") 
	
	var on_button_glyph_display = game_roll_button.get_node_or_null("RolledGlyphOnButtonDisplay")
	if is_instance_valid(on_button_glyph_display):
		on_button_glyph_display.visible = false
		
	if is_instance_valid(dice_roll_effect_timer):
		dice_roll_effect_timer.start()
	else:
		printerr("RollAnimationController: DiceRollEffectTimer invalid, attempting skip.")
		_on_dice_roll_effect_timer_timeout()

func _on_dice_roll_effect_timer_timeout():
	if current_anim_state != AnimState.DICE_ROLL_VISUAL: return
	print("RollAnimationController: Dice roll visual effect finished. Requesting logical roll.")
	emit_signal("logical_roll_requested") 

func set_logical_roll_result(rolled_glyph: GlyphData):
	if not is_instance_valid(rolled_glyph):
		printerr("RollAnimationController: Received invalid glyph. Aborting.")
		_reset_and_idle()
		emit_signal("full_animation_sequence_complete", null)
		return

	_current_logically_rolled_glyph = rolled_glyph
	print("RollAnimationController: Logical roll result: ", _current_logically_rolled_glyph.display_name)
	
	var roll_anim_player = game_roll_button.get_node_or_null("RollAnimationDisplay")
	if is_instance_valid(roll_anim_player) and roll_anim_player is AnimatedSprite2D:
		roll_anim_player.stop()

	var on_button_glyph_display = game_roll_button.get_node_or_null("RolledGlyphOnButtonDisplay")
	if is_instance_valid(on_button_glyph_display) and on_button_glyph_display is TextureRect:
		on_button_glyph_display.texture = _current_logically_rolled_glyph.texture
		on_button_glyph_display.visible = true
	
	current_anim_state = AnimState.REVEAL_ON_BUTTON
	emit_signal("glyph_revealed_on_button", _current_logically_rolled_glyph)
	if is_instance_valid(reveal_on_button_timer):
		reveal_on_button_timer.start()
	else:
		printerr("RollAnimationController: RevealOnButtonTimer invalid, attempting skip.")
		_on_reveal_on_button_timer_timeout()

func _on_reveal_on_button_timer_timeout():
	if current_anim_state != AnimState.REVEAL_ON_BUTTON: return
	print("RollAnimationController: Reveal on button finished. Starting move to center.")
	current_anim_state = AnimState.MOVING_TO_CENTER
	
	if is_instance_valid(animating_glyph_node): animating_glyph_node.queue_free()
	animating_glyph_node = TextureRect.new()
	animating_glyph_node.texture = _current_logically_rolled_glyph.texture
	animating_glyph_node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	animating_glyph_node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	
	# Assumes Game.gd has class_name Game for this to work:
	animating_glyph_node.custom_minimum_size = Game.ROLL_BUTTON_GLYPH_SIZE 
	animating_glyph_node.size = Game.ROLL_BUTTON_GLYPH_SIZE

	var on_button_glyph_display = game_roll_button.get_node_or_null("RolledGlyphOnButtonDisplay")
	if is_instance_valid(on_button_glyph_display):
		animating_glyph_node.global_position = on_button_glyph_display.global_position - (animating_glyph_node.size / 2.0) + (on_button_glyph_display.size / 2.0)
		on_button_glyph_display.visible = false
	else:
		animating_glyph_node.global_position = game_roll_button.global_position

	if is_instance_valid(game_ui_canvas): game_ui_canvas.add_child(animating_glyph_node)
	else: printerr("RollAnimationController: game_ui_canvas is not valid!")

	# CORRECTED: Use get_viewport().get_visible_rect()
	var screen_center = get_viewport().get_visible_rect().size / 2.0 
	var tween_to_center = create_tween()
	tween_to_center.tween_property(animating_glyph_node, "global_position", screen_center - (animating_glyph_node.size / 2.0), 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween_to_center.finished.connect(Callable(self, "_on_move_to_center_finished"))

func _on_move_to_center_finished():
	if current_anim_state != AnimState.MOVING_TO_CENTER: return
	print("RollAnimationController: Glyph moved to center. Requesting fanfare start.")
	current_anim_state = AnimState.AWAITING_HUD_FANFARE
	emit_signal("fanfare_start_requested", _current_logically_rolled_glyph, animating_glyph_node)

func hud_fanfare_has_completed():
	if current_anim_state != AnimState.AWAITING_HUD_FANFARE:
		print("RollAnimationController: hud_fanfare_has_completed in wrong state: ", AnimState.keys()[current_anim_state])
		return
	print("RollAnimationController: HUD fanfare completed. Requesting move to history.")
	current_anim_state = AnimState.MOVING_TO_HISTORY
	emit_signal("move_to_history_requested", animating_glyph_node, _current_logically_rolled_glyph)

func animation_move_to_history_finished():
	if current_anim_state != AnimState.MOVING_TO_HISTORY: return
	print("RollAnimationController: Glyph move to history finished.")
	if is_instance_valid(animating_glyph_node):
		animating_glyph_node.queue_free()
		animating_glyph_node = null
	
	var final_glyph = _current_logically_rolled_glyph
	_reset_and_idle()
	emit_signal("full_animation_sequence_complete", final_glyph)

func _reset_and_idle():
	print("RollAnimationController: Resetting to IDLE.")
	current_anim_state = AnimState.IDLE
	_current_logically_rolled_glyph = null
	if is_instance_valid(animating_glyph_node):
		animating_glyph_node.queue_free()
		animating_glyph_node = null
