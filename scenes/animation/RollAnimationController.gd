# res://scripts/animation/RollAnimationController.gd
# TABS FOR INDENTATION
extends Node

# --- Signals to Game.gd ---
signal visual_roll_animation_started
signal logical_roll_requested # Game.gd provides initial (possibly superposition) glyph
signal glyph_revealed_on_button(glyph_data: GlyphData) # Shows initial (superposition) glyph
signal superposition_collapse_requested(superposition_glyph: GlyphData, resolved_glyph: GlyphData) # New: For collapse animation
signal fanfare_start_requested(resolved_glyph: GlyphData, temp_anim_glyph_node: TextureRect) # Uses resolved_glyph
signal move_to_history_requested(temp_anim_glyph_node: TextureRect, final_glyph: GlyphData) # Uses resolved_glyph
signal full_animation_sequence_complete(final_glyph_data: GlyphData) # Uses resolved_glyph

enum AnimState {
	IDLE,
	DICE_ROLL_VISUAL, # Initial animation of roll button
	AWAITING_LOGICAL_ROLL, # Waiting for Game.gd to provide the initial glyph
	REVEAL_INITIAL_ON_BUTTON, # Showing the initial (superposition?) glyph on button
	SUPERPOSITION_COLLAPSING, # Animating the collapse if it's a superposition glyph
	REVEAL_RESOLVED_ON_BUTTON, # Showing the final resolved glyph on button (after collapse)
	MOVING_TO_CENTER,
	AWAITING_HUD_FANFARE,
	MOVING_TO_HISTORY
}
var current_anim_state: AnimState = AnimState.IDLE

var game_roll_button: TextureButton
var game_ui_canvas: CanvasLayer
var game_hud_instance: Control

var animating_glyph_node: TextureRect = null

# Score fanfare animations are handled by HUD.gd
@onready var dice_roll_effect_timer: Timer = $DiceRollEffectTimer
@onready var reveal_on_button_timer: Timer = $RevealOnButtonTimer
@onready var collapse_effect_timer: Timer = $CollapseEffectTimer

const DICE_ROLL_EFFECT_DURATION: float = 0.1 
const REVEAL_INITIAL_ON_BUTTON_DURATION: float = 0.5 # Can be shorter if followed by collapse
const COLLAPSE_ANIMATION_DURATION: float = 0.4
const REVEAL_RESOLVED_DURATION: float = 0.3 # Time to show resolved glyph before moving to center

var _initial_rolled_glyph: GlyphData = null # Could be a superposition glyph
var _resolved_glyph: GlyphData = null    # The final, non-superposition glyph

func _ready():
	if is_instance_valid(dice_roll_effect_timer):
		dice_roll_effect_timer.one_shot = true
		dice_roll_effect_timer.wait_time = DICE_ROLL_EFFECT_DURATION
		dice_roll_effect_timer.timeout.connect(_on_dice_roll_effect_timer_timeout)
	else:
		printerr("RollAnimationController: DiceRollEffectTimer node not found! Check scene setup.")

	if is_instance_valid(reveal_on_button_timer): # Will be reused for initial and resolved reveal
		reveal_on_button_timer.one_shot = true
		# reveal_on_button_timer.wait_time set dynamically
		reveal_on_button_timer.timeout.connect(_on_reveal_timer_timeout)
	else:
		printerr("RollAnimationController: RevealOnButtonTimer node not found! Check scene setup.")

	# collapse_effect_timer should now be assigned by @onready
	if is_instance_valid(collapse_effect_timer):
		collapse_effect_timer.one_shot = true
		collapse_effect_timer.wait_time = COLLAPSE_ANIMATION_DURATION
		collapse_effect_timer.timeout.connect(_on_collapse_effect_timer_timeout)
	else:
		printerr("RollAnimationController: CollapseEffectTimer node not found! Check scene setup or @onready var.")
	
	current_anim_state = AnimState.IDLE

func setup_references(p_roll_button: TextureButton, p_ui_canvas: CanvasLayer, p_hud: Control):
	game_roll_button = p_roll_button
	game_ui_canvas = p_ui_canvas
	game_hud_instance = p_hud
	print("RollAnimationController: References set up.")

func start_full_roll_sequence():
	if current_anim_state != AnimState.IDLE:
		printerr("RollAnimationController: Cannot start new sequence, busy: ", AnimState.keys()[current_anim_state])
		return

	print("RollAnimationController: Starting full roll sequence.")
	_initial_rolled_glyph = null
	_resolved_glyph = null
	current_anim_state = AnimState.DICE_ROLL_VISUAL
	emit_signal("visual_roll_animation_started")

	var roll_anim_player = game_roll_button.get_node_or_null("RollAnimationDisplay")
	if is_instance_valid(roll_anim_player) and roll_anim_player is AnimatedSprite2D:
		roll_anim_player.play("default") 
	
	var on_button_glyph_display = game_roll_button.get_node_or_null("RolledGlyphOnButtonDisplay")
	if is_instance_valid(on_button_glyph_display):
		on_button_glyph_display.visible = false
		
	dice_roll_effect_timer.start()

func _on_dice_roll_effect_timer_timeout():
	if current_anim_state != AnimState.DICE_ROLL_VISUAL: return
	print("RollAnimationController: Dice roll visual effect finished. Requesting logical roll.")
	current_anim_state = AnimState.AWAITING_LOGICAL_ROLL
	emit_signal("logical_roll_requested") 

# Game.gd calls this with the initially rolled glyph (could be superposition)
func set_logical_roll_result(initial_glyph: GlyphData):
	if current_anim_state != AnimState.AWAITING_LOGICAL_ROLL:
		printerr("RollAnimationController: set_logical_roll_result called in wrong state: ", AnimState.keys()[current_anim_state])
		_reset_and_idle()
		emit_signal("full_animation_sequence_complete", null) # Signal failure
		return

	if not is_instance_valid(initial_glyph):
		printerr("RollAnimationController: Received invalid initial_glyph. Aborting.")
		_reset_and_idle()
		emit_signal("full_animation_sequence_complete", null)
		return

	_initial_rolled_glyph = initial_glyph
	print("RollAnimationController: Initial logical roll result: ", _initial_rolled_glyph.display_name)
	
	# Stop roll button animation
	var roll_anim_player = game_roll_button.get_node_or_null("RollAnimationDisplay")
	if is_instance_valid(roll_anim_player) and roll_anim_player is AnimatedSprite2D:
		roll_anim_player.stop()

	# Show initial glyph (superposition or normal) on button
	var on_button_glyph_display = game_roll_button.get_node_or_null("RolledGlyphOnButtonDisplay")
	if is_instance_valid(on_button_glyph_display) and on_button_glyph_display is TextureRect:
		on_button_glyph_display.texture = _initial_rolled_glyph.texture # Show superposition texture
		on_button_glyph_display.visible = true
	
	current_anim_state = AnimState.REVEAL_INITIAL_ON_BUTTON
	emit_signal("glyph_revealed_on_button", _initial_rolled_glyph) # Game.gd might use this for early UI hints
	
	reveal_on_button_timer.wait_time = REVEAL_INITIAL_ON_BUTTON_DURATION
	reveal_on_button_timer.start()

# This timer is now generic for any reveal phase on the button
func _on_reveal_timer_timeout():
	match current_anim_state:
		AnimState.REVEAL_INITIAL_ON_BUTTON:
			print("RollAnimationController: Initial reveal on button finished.")
			if _initial_rolled_glyph.is_superposition:
				_resolved_glyph = _initial_rolled_glyph.resolve_superposition()
				if not is_instance_valid(_resolved_glyph) or _resolved_glyph == _initial_rolled_glyph: # Resolution failed or no valid outcomes
					printerr("RollAnimationController: Superposition resolution failed for '%s'. Treating as non-superposition." % _initial_rolled_glyph.id)
					_resolved_glyph = _initial_rolled_glyph # Fallback to initial if resolution fails
					_start_move_to_center(_resolved_glyph) # Skip collapse
				else:
					print("RollAnimationController: Superposition glyph '%s' resolved to '%s'." % [_initial_rolled_glyph.display_name, _resolved_glyph.display_name])
					_start_superposition_collapse()
			else: # Not a superposition glyph
				_resolved_glyph = _initial_rolled_glyph
				_start_move_to_center(_resolved_glyph) # Proceed directly to moving the (only) glyph

		AnimState.REVEAL_RESOLVED_ON_BUTTON:
			print("RollAnimationController: Resolved glyph reveal on button finished.")
			_start_move_to_center(_resolved_glyph) # Now move the resolved glyph to center
		_:
			printerr("RollAnimationController: _on_reveal_timer_timeout in unexpected state: ", AnimState.keys()[current_anim_state])


func _start_superposition_collapse():
	current_anim_state = AnimState.SUPERPOSITION_COLLAPSING
	emit_signal("superposition_collapse_requested", _initial_rolled_glyph, _resolved_glyph)
	
	var on_button_glyph_display = game_roll_button.get_node_or_null("RolledGlyphOnButtonDisplay")
	if is_instance_valid(on_button_glyph_display) and on_button_glyph_display is TextureRect:
		# Example simple collapse: quick scale down/up, change texture mid-way
		var tween = create_tween()
		tween.set_parallel(false) # Sequential
		tween.tween_property(on_button_glyph_display, "scale", Vector2(0.1, 0.1), COLLAPSE_ANIMATION_DURATION / 2.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_callback(Callable(self, "_swap_texture_for_collapse").bind(on_button_glyph_display, _resolved_glyph.texture))
		tween.tween_property(on_button_glyph_display, "scale", Vector2(1.0, 1.0), COLLAPSE_ANIMATION_DURATION / 2.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	collapse_effect_timer.start() # Timer to mark end of visual collapse

func _swap_texture_for_collapse(node: TextureRect, new_texture: Texture2D):
	if is_instance_valid(node):
		node.texture = new_texture

func _on_collapse_effect_timer_timeout():
	if current_anim_state != AnimState.SUPERPOSITION_COLLAPSING: return
	print("RollAnimationController: Superposition collapse animation finished.")
	
	# Now reveal the resolved glyph briefly on the button
	current_anim_state = AnimState.REVEAL_RESOLVED_ON_BUTTON
	# emit_signal("glyph_revealed_on_button", _resolved_glyph) # Game already knows initial, this is more for visual timing
	
	reveal_on_button_timer.wait_time = REVEAL_RESOLVED_DURATION
	reveal_on_button_timer.start()


func _start_move_to_center(glyph_to_move: GlyphData):
	if not is_instance_valid(glyph_to_move):
		printerr("RollAnimationController: _start_move_to_center called with invalid glyph.")
		_reset_and_idle()
		emit_signal("full_animation_sequence_complete", null)
		return

	current_anim_state = AnimState.MOVING_TO_CENTER
	print("RollAnimationController: Starting move to center for glyph: ", glyph_to_move.display_name)
	
	if is_instance_valid(animating_glyph_node): animating_glyph_node.queue_free()
	animating_glyph_node = TextureRect.new()
	animating_glyph_node.texture = glyph_to_move.texture # Use the (resolved) glyph's texture
	animating_glyph_node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	animating_glyph_node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	animating_glyph_node.custom_minimum_size = Game.ROLL_BUTTON_GLYPH_SIZE 
	animating_glyph_node.size = Game.ROLL_BUTTON_GLYPH_SIZE

	var on_button_glyph_display = game_roll_button.get_node_or_null("RolledGlyphOnButtonDisplay")
	if is_instance_valid(on_button_glyph_display):
		animating_glyph_node.global_position = on_button_glyph_display.global_position
		on_button_glyph_display.visible = false # Hide the one on the button
	else:
		animating_glyph_node.global_position = game_roll_button.global_position # Fallback

	if is_instance_valid(game_ui_canvas): game_ui_canvas.add_child(animating_glyph_node)
	else: printerr("RollAnimationController: game_ui_canvas is not valid!")

	var screen_center = get_viewport().get_visible_rect().size / 2.0 
	var target_pos_center = screen_center - (animating_glyph_node.size / 2.0)
	
	var tween_to_center = create_tween()
	tween_to_center.tween_property(animating_glyph_node, "global_position", target_pos_center, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween_to_center.finished.connect(_on_move_to_center_finished)

func _on_move_to_center_finished():
	if current_anim_state != AnimState.MOVING_TO_CENTER: return
	print("RollAnimationController: Glyph moved to center. Requesting fanfare start.")
	current_anim_state = AnimState.AWAITING_HUD_FANFARE
	# Fanfare always uses the _resolved_glyph
	emit_signal("fanfare_start_requested", _resolved_glyph, animating_glyph_node)

func hud_fanfare_has_completed():
	if current_anim_state != AnimState.AWAITING_HUD_FANFARE:
		print("RollAnimationController: hud_fanfare_has_completed in wrong state: ", AnimState.keys()[current_anim_state])
		return
	print("RollAnimationController: HUD fanfare completed. Requesting move to history.")
	current_anim_state = AnimState.MOVING_TO_HISTORY
	# Move to history always uses the _resolved_glyph
	emit_signal("move_to_history_requested", animating_glyph_node, _resolved_glyph)

func animation_move_to_history_finished():
	if current_anim_state != AnimState.MOVING_TO_HISTORY: return
	print("RollAnimationController: Glyph move to history finished.")
	if is_instance_valid(animating_glyph_node):
		animating_glyph_node.queue_free()
		animating_glyph_node = null
	
	var final_glyph_to_report = _resolved_glyph # Report the resolved glyph
	_reset_and_idle()
	emit_signal("full_animation_sequence_complete", final_glyph_to_report)

func _reset_and_idle():
	print("RollAnimationController: Resetting to IDLE.")
	current_anim_state = AnimState.IDLE
	_initial_rolled_glyph = null
	_resolved_glyph = null
	if is_instance_valid(animating_glyph_node):
		animating_glyph_node.queue_free()
		animating_glyph_node = null
	
	# Ensure on-button display is hidden
	var on_button_glyph_display = game_roll_button.get_node_or_null("RolledGlyphOnButtonDisplay")
	if is_instance_valid(on_button_glyph_display):
		on_button_glyph_display.visible = false
