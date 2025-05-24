# res://scripts/Game.gd
# TABS FOR INDENTATION
extends Node2D

# --- Game State Enum ---
enum GameState {
	MENU,
	INITIALIZING_GAME,
	INITIALIZING_ROUND,
	PLAYING,
	ROLL_ANIMATION,
	PROCESSING_ROLL,
	LOOT_SELECTION,
	ROUND_SUMMARY,
	GAME_OVER
}
var current_game_state: GameState = GameState.MENU # Start in MENU state

# --- Player's DICE & Roll History (LOGIC ONLY) ---
var current_player_dice: Array[GlyphData] = []
var roll_history: Array[GlyphData] = [] # For current round's synergies
var last_rolled_glyph: GlyphData = null # Still useful for logic, HUD will also get it

# --- Scoring & Progression ---
var current_round_score: int = 0
var target_score: int = 0
var rolls_left: int = 0
var current_level: int = 1
var total_accumulated_score: int = 0

# --- Configurable Game Parameters ---
const STARTING_ROLLS: int = 6
const BASE_TARGET_SCORE: int = 15
const TARGET_SCORE_PER_LEVEL_INCREASE: int = 7
const ROLLS_INCREASE_EVERY_X_LEVELS: int = 2
const MAX_ROLLS_CAP: int = 15 # Using the visual history slot count from HUD later if needed, or keep separate

# --- Synergy Tracking ---
var synergies_fired_this_round: Dictionary = {}

# --- CORE UI Node References (Only those Game.gd directly interacts with for non-display logic) ---
@onready var roll_button: TextureButton = $UICanvas/MainGameUI/AnimatedRollButton
# @onready var main_game_ui_root: Control = $UICanvas/MainGameUI # Optional: To show/hide the whole game UI block

# --- Scene Preloads & Instances ---
var main_menu_scene: PackedScene = preload("res://scenes/ui/MainMenu.tscn")
@onready var main_menu_instance: Control

var loot_screen_scene: PackedScene = preload("res://scenes/ui/LootScreen.tscn")
@onready var loot_screen_instance: Control

var hud_scene: PackedScene = preload("res://scenes/ui/HUD.tscn") # Preload HUD scene
@onready var hud_instance: Control # Instance of the HUD

# --- REMOVED UI VARS (now in HUD.gd) ---
# @onready var score_label: Label
# @onready var target_label: Label
# @onready var rolls_label: Label
# @onready var level_label: Label
# @onready var dice_face_display_container: GridContainer 
# @onready var last_roll_display: TextureRect
# @onready var synergy_notification_label: Label
# const MAX_VISUAL_HISTORY_SLOTS: int = 15 
# var roll_history_slot_positions: Array[Vector2] = []
# @onready var roll_history_display_container: Control
# var current_visual_history_index: int = 0
# @onready var inventory_toggle_button: TextureButton # This button is part of HUD.tscn now
# @onready var dice_face_scroll_container: ScrollContainer # This is part of HUD.tscn now


func _ready():
	# --- 1. Get Core Node References ---
	# Ensure @onready vars for roll_button (and main_game_ui_root if you use it) have correct paths
	roll_button = $UICanvas/MainGameUI/AnimatedRollButton # Example path, verify yours

	# --- 2. Instantiate and Setup HUD ---
	if hud_scene:
		hud_instance = hud_scene.instantiate()
		var ui_canvas = $UICanvas # Assuming $UICanvas is a direct child of Game node
		if is_instance_valid(ui_canvas):
			ui_canvas.add_child(hud_instance) # Add HUD to the canvas
			# Connect inventory toggle from HUD if Game.gd needs to react (e.g. to update data for it)
			# For now, HUD's inventory button directly toggles its own scroll container.
			# If Game.gd needed to trigger the update:
			# hud_instance.get_node("InventoryToggleButton").pressed.connect(Callable(self, "_on_hud_inventory_toggle_pressed"))
		else:
			printerr("ERROR: UICanvas node not found for adding HUD! Adding to self.")
			add_child(hud_instance)
		hud_instance.visible = false # HUD might start hidden if MainMenu is shown first
	else:
		printerr("ERROR: HUD.tscn not preloaded!")

	# --- 3. Instantiate and Setup Main Menu ---
	if main_menu_scene:
		main_menu_instance = main_menu_scene.instantiate()
		var ui_canvas = $UICanvas 
		if is_instance_valid(ui_canvas):
			ui_canvas.add_child(main_menu_instance)
		else:
			add_child(main_menu_instance)
		if main_menu_instance.has_signal("start_game_pressed"):
			main_menu_instance.start_game_pressed.connect(Callable(self, "_on_main_menu_start_game"))
		else:
			printerr("ERROR: main_menu_instance does NOT have signal 'start_game_pressed'.")
	else:
		printerr("ERROR: MainMenu.tscn not preloaded!")

	# --- 4. Instantiate and Setup Loot Screen ---
	if loot_screen_scene:
		loot_screen_instance = loot_screen_scene.instantiate()
		var ui_canvas = $UICanvas
		if is_instance_valid(ui_canvas):
			ui_canvas.add_child(loot_screen_instance)
		else:
			add_child(loot_screen_instance)
		if loot_screen_instance.has_signal("loot_selected"):
			loot_screen_instance.loot_selected.connect(Callable(self, "_on_loot_selected"))
		if loot_screen_instance.has_signal("loot_screen_closed"):
			loot_screen_instance.loot_screen_closed.connect(Callable(self, "_on_loot_screen_closed"))
		loot_screen_instance.hide() # Loot screen starts hidden
	else:
		printerr("ERROR: LootScreen.tscn not preloaded correctly!")
	
	# --- 5. Connect Signals for Game-Interactive UI elements ---
	if is_instance_valid(roll_button):
		roll_button.pressed.connect(Callable(self, "_on_roll_button_pressed"))
	else:
		printerr("ERROR: RollButton in _ready() is not valid for signal connection.")
	
	# --- 6. Initial Game State ---
	current_game_state = GameState.MENU 
	print("Game scene _ready complete. Initial game state set to MENU.")


func _process(delta):
	match current_game_state:
		GameState.MENU:
			if is_instance_valid(main_menu_instance) and not main_menu_instance.visible:
				main_menu_instance.show_menu()
			if is_instance_valid(hud_instance): hud_instance.visible = false # Hide HUD
			# Hide other game-specific UI if you have a main container for it
			if is_instance_valid($UICanvas/MainGameUI): $UICanvas/MainGameUI.visible = false
			
		GameState.INITIALIZING_GAME:
			_initialize_new_game_session() # Sets up data
			if is_instance_valid(hud_instance): hud_instance.reset_round_visuals() # Reset HUD visuals
			current_game_state = GameState.INITIALIZING_ROUND
			
		GameState.INITIALIZING_ROUND:
			_initialize_current_round_setup() # Sets up data
			if is_instance_valid(hud_instance): 
				hud_instance.reset_round_visuals() # Reset HUD visuals for the round
				# Update HUD with initial round data
				var effective_max_rolls = min(STARTING_ROLLS + int((current_level - 1) / ROLLS_INCREASE_EVERY_X_LEVELS), MAX_ROLLS_CAP)
				hud_instance.update_rolls_display(rolls_left, effective_max_rolls)
				hud_instance.update_score_target_display(current_round_score, target_score)
				hud_instance.update_level_display(current_level)
				hud_instance.update_dice_inventory_display(current_player_dice) # Show current dice
				hud_instance.update_last_rolled_glyph_display(null) # Clear last roll display
			current_game_state = GameState.PLAYING
			
		GameState.PLAYING:
			if is_instance_valid(hud_instance) and not hud_instance.visible: hud_instance.visible = true # Show HUD
			# Update roll button disabled state (now done via _update_hud_elements)
			_update_hud_elements() # Call this to ensure button state is correct
			
		GameState.ROLL_ANIMATION:
			# For now, immediate transition. Later, a Timer would be used here.
			current_game_state = GameState.PROCESSING_ROLL
			
		GameState.PROCESSING_ROLL:
			_process_the_finished_roll_outcome() # Handles logic, calls HUD updates internally now
			if rolls_left <= 0:
				current_game_state = GameState.ROUND_SUMMARY
			else:
				current_game_state = GameState.PLAYING
				
		GameState.LOOT_SELECTION:
			# Game.gd waits for signals from loot_screen_instance
			# HUD might be partially obscured or still visible
			pass 
			
		GameState.ROUND_SUMMARY:
			if current_round_score >= target_score:
				current_game_state = GameState.LOOT_SELECTION
				_prepare_and_show_loot_screen()
			else:
				current_game_state = GameState.GAME_OVER
				# _setup_game_over_ui() # Later
				
		GameState.GAME_OVER:
			if is_instance_valid(hud_instance): hud_instance.visible = true # Or show a specific Game Over UI
			print("GAME OVER! Final Score:", total_accumulated_score, "Reached Level:", current_level)
			# Add logic to show a GameOverScreen instance later
			if Input.is_action_just_pressed("confirm_action"):
				current_game_state = GameState.MENU # Go back to menu
	
	# _update_all_ui_elements() # This function is now effectively replaced by specific calls to hud_instance


func _initialize_new_game_session():
	print("Initializing new game session...")
	current_level = 1
	total_accumulated_score = 0
	current_player_dice.clear()

	if GlyphDB and not GlyphDB.starting_dice_configuration.is_empty():
		current_player_dice = GlyphDB.starting_dice_configuration.duplicate(true)
		print("Player dice initialized with: ", current_player_dice.size(), " faces.")
		if is_instance_valid(hud_instance): # Update HUD after dice are set
			hud_instance.update_dice_inventory_display(current_player_dice)
	else:
		printerr("Game Error: GlyphDB not ready or starting_dice_configuration is empty!")


func _initialize_current_round_setup():
	print("Initializing round setup for level: ", current_level)
	current_round_score = 0
	target_score = BASE_TARGET_SCORE + (current_level - 1) * TARGET_SCORE_PER_LEVEL_INCREASE
	var calculated_rolls = STARTING_ROLLS + int((current_level - 1) / ROLLS_INCREASE_EVERY_X_LEVELS)
	rolls_left = min(calculated_rolls, MAX_ROLLS_CAP) 
	
	# Logical resets
	roll_history.clear() 
	synergies_fired_this_round.clear()
	last_rolled_glyph = null 
	
	print("Round ", current_level, " initialized. Target: ", target_score, ". Rolls: ", rolls_left, " (Capped at ", MAX_ROLLS_CAP, ")")
	# HUD updates will be triggered by INITIALIZING_ROUND state in _process


func _update_hud_elements(): # New function to centralize HUD updates based on game state
	if not is_instance_valid(hud_instance): return

	var effective_max_rolls = min(STARTING_ROLLS + int((current_level - 1) / ROLLS_INCREASE_EVERY_X_LEVELS), MAX_ROLLS_CAP)
	hud_instance.update_rolls_display(rolls_left, effective_max_rolls)
	hud_instance.update_score_target_display(current_round_score, target_score)
	hud_instance.update_level_display(current_level)
	hud_instance.update_last_rolled_glyph_display(last_rolled_glyph) # For the separate display
	
	# Update roll button disabled state
	if is_instance_valid(roll_button):
		roll_button.disabled = not (current_game_state == GameState.PLAYING and rolls_left > 0)


func _on_roll_button_pressed():
	if current_game_state == GameState.PLAYING and rolls_left > 0:
		print("Roll button pressed.")
		# Reset on-button glyph display if you have one (now handled by HUD if it's the separate one)
		# If the button itself shows the last roll, clear it here or show rolling anim
		current_game_state = GameState.ROLL_ANIMATION
	else:
		print("Cannot roll. State:", GameState.keys()[current_game_state], "Rolls left:", rolls_left)


func _process_the_finished_roll_outcome():
	if current_player_dice.is_empty():
		printerr("CRITICAL: Player dice is empty! Cannot process roll.")
		current_game_state = GameState.PLAYING
		return

	var rolled_glyph_index = randi() % current_player_dice.size()
	last_rolled_glyph = current_player_dice[rolled_glyph_index]

	if not is_instance_valid(last_rolled_glyph):
		printerr("CRITICAL: last_rolled_glyph invalid post-roll! Index: ", rolled_glyph_index)
		current_game_state = GameState.PLAYING 
		return

	print("Rolled: '", last_rolled_glyph.display_name, "' (Val: ", str(last_rolled_glyph.value), ")")
	
	# Update on-button glyph display (if it's different from the main hud_instance.last_roll_display)
	var rolled_glyph_display_on_button = roll_button.get_node_or_null("RolledGlyphOnButtonDisplay")
	if is_instance_valid(rolled_glyph_display_on_button):
		rolled_glyph_display_on_button.texture = last_rolled_glyph.texture
		rolled_glyph_display_on_button.visible = true
	
	current_round_score += last_rolled_glyph.value
	total_accumulated_score += last_rolled_glyph.value 
	roll_history.append(last_rolled_glyph)

	if is_instance_valid(hud_instance): # Add rolled glyph to visual history track in HUD
		hud_instance.add_glyph_to_visual_history(last_rolled_glyph)
	
	_check_and_apply_synergies() # This will call hud_instance.show_synergy_message()
	
	rolls_left -= 1
	# _update_hud_elements() will be called by _process in PLAYING or other states
	print("Roll processed. Score: ", current_round_score, ". Rolls left: ", rolls_left)


func add_glyph_to_player_dice(glyph_data: GlyphData):
	if glyph_data and glyph_data is GlyphData:
		current_player_dice.append(glyph_data)
		print("Added glyph '", glyph_data.display_name, "' to player dice. Total: ", current_player_dice.size())
		# HUD will be updated via _on_loot_selected -> hud_instance.update_dice_inventory_display
	else:
		printerr("Attempted to add invalid glyph data to dice.")


func _check_and_apply_synergies():
	if roll_history.is_empty():
		return

	# --- Re-declare these local variables here ---
	var total_synergy_bonus: int = 0
	var synergy_message: String = "" # To build a combined message if multiple trigger

	# --- Synergy 1: Numeric Double ---
	if not synergies_fired_this_round.has("numeric_double"):
		var dice_values_seen: Dictionary = {}
		for roll_data in roll_history:
			if roll_data.type == "dice":
				if not dice_values_seen.has(roll_data.value):
					dice_values_seen[roll_data.value] = 1
				else:
					dice_values_seen[roll_data.value] += 1
				
				if dice_values_seen[roll_data.value] >= 2:
					total_synergy_bonus += 5 # Apply bonus to local var
					synergies_fired_this_round["numeric_double"] = true
					synergy_message += "NUMERIC DOUBLE! +5\n" # Append to local var
					sfx(10) 
					print("Synergy: Numeric Double triggered!")
					break 

	# --- Synergy 2: Roman Gathering ---
	if not synergies_fired_this_round.has("roman_gathering"):
		var roman_glyph_count: int = 0
		for roll_data in roll_history:
			if roll_data.type == "roman":
				roman_glyph_count += 1
		
		if roman_glyph_count >= 2:
			total_synergy_bonus += 10 # Apply bonus to local var
			synergies_fired_this_round["roman_gathering"] = true
			synergy_message += "ROMAN GATHERING! +10\n" # Append to local var
			sfx(11) 
			print("Synergy: Roman Gathering triggered!")

	# --- Synergy 3: Card Pair ---
	if not synergies_fired_this_round.has("card_pair"):
		var card_values_seen: Dictionary = {}
		for roll_data in roll_history:
			if roll_data.type == "card":
				if not card_values_seen.has(roll_data.value):
					card_values_seen[roll_data.value] = 1
				else:
					card_values_seen[roll_data.value] += 1

				if card_values_seen[roll_data.value] >= 2:
					total_synergy_bonus += 8 # Apply bonus to local var
					synergies_fired_this_round["card_pair"] = true
					synergy_message += "CARD PAIR! +8\n" # Append to local var
					sfx(12) 
					print("Synergy: Card Pair triggered!")
					break

	# --- Apply Bonuses to Game Score and Tell HUD to Display Message ---
	if total_synergy_bonus > 0:
		current_round_score += total_synergy_bonus
		total_accumulated_score += total_synergy_bonus
		print("Total synergy bonus this roll: ", total_synergy_bonus)
		if is_instance_valid(hud_instance): # Call HUD to show the combined message
			hud_instance.show_synergy_message(synergy_message.strip_edges(true, true)) # strip_edges(true,true) removes leading/trailing newlines
	
	# No need to call _update_hud_elements() here, as score changes will be reflected
	# when _update_hud_elements() is called in the _process loop by the PLAYING state,
	# or if you want immediate update:
	# if total_synergy_bonus > 0 and is_instance_valid(hud_instance):
	#     hud_instance.update_score_target_display(current_round_score, target_score)
	# For now, relying on the next _process cycle's _update_hud_elements call is fine.

# --- Scene/UI Management Callbacks ---
func _on_main_menu_start_game():
	if is_instance_valid(main_menu_instance):
		main_menu_instance.hide_menu()
	# if is_instance_valid($UICanvas/MainGameUI): $UICanvas/MainGameUI.visible = true # HUD visibility handled by PLAYING state
	current_game_state = GameState.INITIALIZING_GAME

func _prepare_and_show_loot_screen():
	# ... (same as before, calls loot_screen_instance.display_loot_options) ...
	print("Preparing loot screen...")
	if not is_instance_valid(loot_screen_instance):
		printerr("Loot screen instance is not valid! Skipping loot.")
		_on_loot_screen_closed()
		return
	var loot_options = GlyphDB.get_random_loot_options(3) # Removed current_player_dice from here
	if loot_options.is_empty():
		print("No loot options available. Skipping loot.")
		_on_loot_screen_closed()
		return
	loot_screen_instance.display_loot_options(loot_options)

func _on_loot_selected(chosen_glyph: GlyphData):
	print("Game: Loot selected - ", chosen_glyph.display_name)
	add_glyph_to_player_dice(chosen_glyph)
	if is_instance_valid(hud_instance): # Tell HUD to update inventory
		hud_instance.update_dice_inventory_display(current_player_dice)
	
	current_level += 1
	total_accumulated_score += 50 
	current_game_state = GameState.INITIALIZING_ROUND

func _on_loot_screen_closed():
	print("Game: Loot screen closed, proceeding to next round without new glyph.")
	current_level += 1
	current_game_state = GameState.INITIALIZING_ROUND

# --- SFX Placeholder ---
func sfx(sfx_id: int): # This can stay in Game.gd or move to an Audio Manager Autoload
	print("SFX Player: Playing sound id ", sfx_id)
